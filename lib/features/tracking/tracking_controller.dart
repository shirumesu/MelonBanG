import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tracking_repository.dart';
import '../../core/error_message.dart';
import '../../domain/catalog.dart';

/// The Bangumi account, its collection and sync state.
class TrackingController extends ChangeNotifier {
  TrackingController(this.account, this.tracking) {
    _accountChanges = account.changes.listen((_) => notifyListeners());
  }
  final Account account;
  final TrackingRepository tracking;
  late final StreamSubscription<void> _accountChanges;

  AccountProfile? profile;
  List<Subject> collection = [];

  /// Why the last pull from Bangumi failed; the saved collection stays.
  String? pullError;
  DateTime? _pulledAt;

  /// Whether the saved collection has been read once; until then an empty
  /// one is not known to be empty.
  bool loaded = false;

  /// Whether a pull from Bangumi is running.
  bool get syncing => _pulls > 0;
  int _pulls = 0;

  /// The subjects the last pull added or changed (status, progress or
  /// score); empty after the first pull of an empty collection, which adds
  /// everything. Kept a few minutes, for a page shown later to mark them.
  Set<int> get updated =>
      _syncedAt != null &&
          DateTime.now().difference(_syncedAt!) < const Duration(minutes: 5)
      ? _updated
      : const {};
  Set<int> _updated = const {};

  /// When the last pull succeeded; it tells marks of one pull from the next.
  DateTime? get syncedAt => _syncedAt;
  DateTime? _syncedAt;
  CollectionStatus filter = CollectionStatus.watching;
  bool accountBusy = false;

  /// Whether the busy account action signs in; the login turns valid
  /// before its first pull ends.
  bool signingIn = false;
  int _ticket = 0;

  bool get signedIn => profile != null;
  bool get needsAuthorization => account.needsAuthorization;
  bool get sessionExpired => account.sessionExpired;
  bool get credentialsUnsaved => account.credentialsUnsaved;
  String get userId => account.userId;
  List<Subject> get watching => collection
      .where((item) => item.status == CollectionStatus.watching)
      .toList();

  void setFilter(CollectionStatus value) {
    filter = value;
    notifyListeners();
  }

  /// Reloads the local collection; results for a replaced account are dropped.
  Future<void> refresh() async {
    final ticket = ++_ticket;
    final user = account.userId;
    final items = await tracking.collection();
    if (ticket != _ticket || user != account.userId) return;
    profile = account.profile;
    collection = items;
    loaded = true;
    notifyListeners();
  }

  static Map<int, Object> _marks(List<Subject> items) => {
    for (final item in items)
      item.id: (item.status, item.watchedEpisodes, item.collection?.score),
  };

  /// Pulls the remote collection when signed in, unless the last pull is
  /// under half a minute old; a failure is kept in [pullError].
  Future<void> pull({bool force = false}) async {
    if (account.profile == null || account.sessionExpired) return;
    final pulledAt = _pulledAt;
    if (!force &&
        pulledAt != null &&
        DateTime.now().difference(pulledAt) < const Duration(seconds: 30)) {
      return;
    }
    final user = account.userId;
    final before = _marks(collection);
    String? error;
    _pulls++;
    notifyListeners();
    try {
      await tracking.refresh();
      _pulledAt = DateTime.now();
      // Read here too, not only on the change event, to tell what changed.
      await refresh();
    } catch (e) {
      error = errorMessage(e);
    } finally {
      _pulls--;
    }
    if (user != account.userId) {
      notifyListeners();
      return;
    }
    pullError = error;
    if (error == null) {
      final after = _marks(collection);
      _updated = before.isEmpty
          ? const {}
          : {
              for (final MapEntry(:key, :value) in after.entries)
                if (before[key] != value) key,
            };
      _syncedAt = DateTime.now();
    }
    notifyListeners();
  }

  /// Asks the keychain for the saved login, then pulls.
  Future<void> unlock() async {
    await account.unlock();
    await refresh();
    await pull(force: true);
  }

  /// Signs in (or unlocks stored credentials), or signs out.
  Future<void> toggleAccount() async {
    if (accountBusy) return;
    accountBusy = true;
    signingIn =
        account.profile == null ||
        account.needsAuthorization ||
        account.sessionExpired;
    notifyListeners();
    try {
      if (signingIn) {
        await account.signIn();
        await refresh();
        await pull(force: true);
      } else {
        await account.signOut();
        pullError = null;
        _pulledAt = null;
      }
    } finally {
      // A network failure must not hide a successfully restored login.
      accountBusy = false;
      signingIn = false;
      notifyListeners();
      await refresh();
    }
  }

  Future<void> cancelSignIn() => account.cancelSignIn();

  Future<void> saveCredentials() => account.saveCredentials();

  @override
  void dispose() {
    _accountChanges.cancel();
    super.dispose();
  }
}
