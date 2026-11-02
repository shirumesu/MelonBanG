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
  CollectionStatus filter = CollectionStatus.watching;
  bool accountBusy = false;
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
    notifyListeners();
  }

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
    String? error;
    try {
      await tracking.refresh();
      _pulledAt = DateTime.now();
    } catch (e) {
      error = errorMessage(e);
    }
    if (user != account.userId) return;
    pullError = error;
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
    notifyListeners();
    try {
      if (account.profile == null ||
          account.needsAuthorization ||
          account.sessionExpired) {
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
