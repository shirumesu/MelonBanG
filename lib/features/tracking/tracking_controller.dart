import 'package:flutter/foundation.dart';

import '../../data/account.dart';
import '../../data/tracking.dart';
import '../../domain/catalog.dart';

/// The Bangumi account, its collection and sync state.
class TrackingController extends ChangeNotifier {
  TrackingController(this.account, this.tracking);
  final AccountRepository account;
  final TrackingRepository tracking;

  AccountProfile? profile;
  List<Subject> collection = [];
  SyncState sync = const SyncState();
  CollectionStatus filter = CollectionStatus.watching;
  bool accountBusy = false;
  int _ticket = 0;

  bool get signedIn => profile != null;
  bool get needsAuthorization => account.needsAuthorization;
  String get userId => account.userId;

  /// Why the last upload of local edits failed.
  String? get lastSyncError => tracking.lastSyncError;
  Future<void> flush() => tracking.flush();
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
    final values = await Future.wait<dynamic>([
      tracking.collection(),
      tracking.syncState(),
    ]);
    if (ticket != _ticket || user != account.userId) return;
    profile = account.profile;
    collection = values[0] as List<Subject>;
    sync = values[1] as SyncState;
    notifyListeners();
  }

  /// Pulls the remote collection; returns what still needs attention.
  Future<String?> synchronize() async {
    final user = account.userId;
    if (account.session == null) return '登录 Bangumi 后可同步收藏。';
    try {
      await tracking.refresh();
      await refresh();
      if (user != account.userId) return '账号已切换，请重新同步。';
      final status = await tracking.syncState();
      if (status.pending > 0) return '已拉取收藏，仍有 ${status.pending} 项修改待上传。';
      if (status.error != null) return '部分修改未能同步，请重试。';
      return null;
    } catch (_) {
      return '同步失败，本地收藏已保留。';
    }
  }

  /// Refreshes the remote collection when signed in.
  Future<void> pull() async {
    if (account.session != null && !account.needsAuthorization) {
      await tracking.refresh();
    }
  }

  /// Signs in (or unlocks stored credentials), or signs out.
  Future<void> toggleAccount() async {
    if (accountBusy) return;
    accountBusy = true;
    notifyListeners();
    try {
      if (account.session == null || account.needsAuthorization) {
        await account.signIn();
        await refresh();
        await tracking.refresh();
      } else {
        await account.signOut();
      }
    } finally {
      // A network failure must not hide a successfully restored login.
      accountBusy = false;
      notifyListeners();
      await refresh();
    }
  }

  Future<void> cancelSignIn() => account.cancelSignIn();
}
