import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/error_message.dart';
import '../../domain/sources.dart';
import '../../features/sync/library_sync.dart';
import '../../features/sync/settings_sync.dart';
import '../../features/tracking/tracking_controller.dart';
import '../../integrations/sources/bilibili_account.dart';
import '../../integrations/transfer/pikpak.dart';
import '../core/account_avatar.dart';
import '../core/action_feedback.dart';
import '../core/external_link.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'settings_page.dart';
import 'sync_conflicts.dart';

/// 账户与同步: the Bangumi account first, as everything personal follows
/// it, with settings sync under it; then the other services signed in to,
/// one compact row each that opens its sign-in in place.
SettingsSection accountSection({
  required TrackingController personal,
  required SettingsSync sync,
  required LibrarySync library,
  required Future<void> Function(SubscriptionSync value) onSubscriptionSync,
  required PikPakTransfer pikpak,
  required BilibiliAccount bilibili,
  required VoidCallback onAccountAction,
  required VoidCallback onCancelSignIn,
  required VoidCallback onUnlock,
  required VoidCallback onSaveCredentials,
}) => SettingsSection(
  id: 'account',
  title: '账户与同步',
  icon: Icons.person_outline,
  groups: [
    SettingsGroup([
      SettingsItem(
        '账户 登录 退出 Bangumi 收藏 进度',
        _BangumiRow(
          personal: personal,
          onAccountAction: onAccountAction,
          onCancelSignIn: onCancelSignIn,
          onUnlock: onUnlock,
          onSaveCredentials: onSaveCredentials,
        ),
      ),
      SettingsItem(
        '设置同步 云端 多设备 同步 冲突 上传 下载 订阅 来源 弹幕匹配 播放记录',
        _SyncRow(sync: sync),
      ),
      SettingsItem(
        '订阅同步 其他设备 临时 不缓存 只同步 同步并缓存 下载',
        _watch(
          library.settings,
          (context) => SettingRow(
            title: '订阅同步',
            subtitle: switch (library.subscriptionSync) {
              SubscriptionSync.off => '这台设备的订阅只留在本机，也不显示其他设备的订阅',
              SubscriptionSync.keep => '其他设备的订阅在这里显示，新一话不下载',
              SubscriptionSync.cache => '其他设备的订阅在这里也缓存新一话',
            },
            help:
                '只对这台设备生效，其他设备的订阅不受影响\n'
                '在这台设备上订阅的番照常缓存；某部番也可在订阅窗口中单独开关缓存',
            trailing: SizedBox(
              width: 300,
              child: MelonSegmentedControl<SubscriptionSync>(
                semanticLabel: '订阅同步',
                options: {
                  for (final value in SubscriptionSync.values)
                    value: value.label,
                },
                value: library.subscriptionSync,
                onChanged: (value) => unawaited(onSubscriptionSync(value)),
              ),
            ),
          ),
        ),
      ),
    ]),
    SettingsGroup([
      SettingsItem('PikPak 登录 云盘 离线下载 账号 密码', _PikPakRow(pikpak: pikpak)),
      SettingsItem(
        'B 站 哔哩哔哩 bilibili 扫码 登录 大会员 弹幕',
        _BilibiliRow(account: bilibili),
      ),
    ], title: '其他服务'),
  ],
);

Widget _watch(Listenable listenable, WidgetBuilder builder) =>
    ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => builder(context),
    );

class _BangumiRow extends StatelessWidget {
  const _BangumiRow({
    required this.personal,
    required this.onAccountAction,
    required this.onCancelSignIn,
    required this.onUnlock,
    required this.onSaveCredentials,
  });
  final TrackingController personal;
  final VoidCallback onAccountAction, onCancelSignIn, onUnlock;
  final VoidCallback onSaveCredentials;

  bool get signedIn =>
      personal.profile != null &&
      !personal.needsAuthorization &&
      !personal.sessionExpired;

  @override
  Widget build(BuildContext context) => _watch(personal, (context) {
    final account = personal.profile;
    final theme = Theme.of(context);
    final problem =
        account != null && (!signedIn || personal.credentialsUnsaved);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: Gap.md),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: Gap.md,
        spacing: Gap.xl,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AccountAvatar(
                url: account?.avatarUrl,
                name: account?.nickname ?? '',
                size: 52,
              ),
              const SizedBox(width: Gap.lg),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account?.nickname ?? '登录 Bangumi',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(
                      account == null
                          ? '登录后同步收藏、观看进度和设置'
                          : personal.sessionExpired
                          ? '登录已过期，重新登录后继续同步'
                          : personal.needsAuthorization
                          ? '没有获得钥匙串授权，暂时无法同步'
                          : personal.credentialsUnsaved
                          ? '登录信息未保存，下次启动需重新登录'
                          : '@${account.username ?? ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: problem ? theme.colorScheme.error : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              if (personal.accountBusy && !signedIn)
                TextButton(
                  onPressed: onCancelSignIn,
                  child: const Text('取消登录'),
                ),
              if (signedIn && personal.credentialsUnsaved)
                FilledButton(
                  onPressed: onSaveCredentials,
                  child: const Text('保存'),
                ),
              if (signedIn)
                OutlinedButton.icon(
                  onPressed: personal.accountBusy
                      ? null
                      : () => _confirmSignOut(
                          context,
                          title: '退出 Bangumi 登录？',
                          message:
                              '退出后不再同步收藏、观看进度和设置，需要时可以重新在浏览器中授权登录。'
                              '已缓存的番剧、订阅和本机的设置不受影响。',
                          onSignOut: onAccountAction,
                        ),
                  icon: const Icon(Icons.logout, size: 18),
                  label: Text(
                    !personal.accountBusy
                        ? '退出登录'
                        : personal.signingIn
                        ? '登录中…'
                        : '退出中…',
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: personal.accountBusy
                      ? null
                      : personal.needsAuthorization && !personal.sessionExpired
                      ? onUnlock
                      : onAccountAction,
                  icon: const Icon(Icons.account_circle_outlined, size: 18),
                  label: Text(
                    personal.accountBusy
                        ? '等待浏览器授权…'
                        : personal.sessionExpired
                        ? '重新登录'
                        : personal.needsAuthorization
                        ? '授权钥匙串'
                        : '登录 Bangumi',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  });
}

/// Asks before signing out of a service, with what signing out changes.
Future<void> _confirmSignOut(
  BuildContext context, {
  required String title,
  required String message,
  required VoidCallback onSignOut,
}) async {
  final confirmed = await showMelonDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: SizedBox(width: 400, child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
      );
    },
  );
  if (confirmed == true) onSignOut();
}

/// The settings sync switch, where it stands, and a way to sync now; what
/// else syncs with the settings is behind its ? mark.
class _SyncRow extends StatefulWidget {
  const _SyncRow({required this.sync});
  final SettingsSync sync;

  @override
  State<_SyncRow> createState() => _SyncRowState();
}

class _SyncRowState extends State<_SyncRow> {
  /// Rewrites "n 分钟前" as time passes.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _watch(widget.sync, (context) {
    final sync = widget.sync;
    final scheme = Theme.of(context).colorScheme;
    final (String? subtitle, Color? color) = switch (sync.status) {
      SettingsSyncStatus.off => (null, null),
      SettingsSyncStatus.signedOut => ('登录 Bangumi 后，设置在登录同一账号的设备间同步', null),
      SettingsSyncStatus.syncing => ('正在同步…', null),
      SettingsSyncStatus.conflict => (
        '${sync.conflicts.length} 项设置在这台和其他设备上改得不一样，选好保留哪边后继续同步',
        scheme.error,
      ),
      SettingsSyncStatus.failed => (
        '同步失败：${sync.error ?? '未知错误'}',
        scheme.error,
      ),
      SettingsSyncStatus.idle => switch (sync.syncedAt) {
        final at? => (syncedAgo(at), null),
        null => ('等待第一次同步', null),
      },
    };
    final busy = sync.status == SettingsSyncStatus.syncing;
    // Tapping the row flips the switch, as a switch row does; the switch
    // stays its own keyboard stop beside the other actions.
    return SettingRow(
      title: '设置同步',
      subtitle: subtitle,
      subtitleColor: color,
      help: '订阅、偏好来源、手动匹配的弹幕、播放记录等非设置项会一起同步',
      onTap: () => unawaited(sync.setEnabled(!sync.enabled)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sync.status == SettingsSyncStatus.conflict)
            FilledButton(
              onPressed: () => showSyncConflicts(context, sync),
              child: const Text('选择'),
            )
          else if (sync.enabled && sync.status != SettingsSyncStatus.signedOut)
            IconButton(
              tooltip: '立即同步',
              onPressed: busy ? null : () => unawaited(sync.syncNow()),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 20),
            ),
          const SizedBox(width: Gap.sm),
          Switch(
            value: sync.enabled,
            onChanged: (value) => unawaited(sync.setEnabled(value)),
          ),
        ],
      ),
    );
  });
}

/// When settings last synced: 刚刚同步, 3 分钟前已同步, 5 月 3 日已同步.
String syncedAgo(DateTime at) {
  final passed = DateTime.now().difference(at);
  if (passed.inMinutes < 1) return '刚刚同步';
  if (passed.inHours < 1) return '${passed.inMinutes} 分钟前已同步';
  if (passed.inDays < 1) return '${passed.inHours} 小时前已同步';
  return '${at.month} 月 ${at.day} 日已同步';
}

/// A service's row: its logo, its name and who is signed in, and one
/// action; signing in opens below the row instead of in a dialog.
class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.logo,
    required this.name,
    required this.status,
    required this.action,
    this.badge,
    this.statusColor,
    this.expanded,
  });

  /// The service's own app icon, from `assets/images/services`.
  final String logo;
  final String name, status;
  final Widget? badge, expanded;
  final Color? statusColor;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: motionDuration(context, 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingRow(
            leading: ClipRRect(
              borderRadius: controlBorderRadius,
              child: Image.asset(
                logo,
                width: 36,
                height: 36,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
            title: name,
            subtitle: status,
            subtitleColor: statusColor,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (badge case final badge?) ...[
                  badge,
                  const SizedBox(width: Gap.md),
                ],
                action,
              ],
            ),
          ),
          if (expanded case final child?)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 20, 20),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _PikPakRow extends StatefulWidget {
  const _PikPakRow({required this.pikpak});
  final PikPakTransfer pikpak;

  @override
  State<_PikPakRow> createState() => _PikPakRowState();
}

class _PikPakRowState extends State<_PikPakRow> {
  final username = TextEditingController();
  final password = TextEditingController();
  final passwordFocus = FocusNode();
  bool open = false, busy = false;
  String? error, captcha;

  PikPakTransfer get pikpak => widget.pikpak;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = captcha = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(() {
          if (failure is SourceVerificationRequired) {
            // The verification hint under the row says what to do.
            captcha = failure.url;
          } else {
            error = errorMessage(failure);
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> login() => run(() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      throw StateError('请输入 PikPak 账号和密码');
    }
    await pikpak.signIn(username.text.trim(), password.text);
    password.clear();
    if (mounted) setState(() => open = false);
  });

  @override
  Widget build(BuildContext context) {
    final account = pikpak.accountName;
    final verification = captcha ?? pikpak.verificationUrl?.toString();
    final locked = pikpak.needsAuthorization;
    return _ServiceRow(
      logo: 'assets/images/services/pikpak.png',
      name: 'PikPak',
      status: locked ? '登录凭据待解锁' : account ?? '登录后可用云端离线下载',
      action: locked
          ? FilledButton(
              onPressed: busy ? null : () => run(pikpak.unlock),
              child: const Text('解锁'),
            )
          : account != null
          ? TextButton(
              onPressed: busy
                  ? null
                  : () => _confirmSignOut(
                      context,
                      title: '退出 PikPak 登录？',
                      message: '退出后订阅和缓存不能再使用 PikPak 云端离线下载，需要时可以重新登录。',
                      onSignOut: () => run(pikpak.signOut),
                    ),
              child: Text(busy ? '退出中…' : '退出登录'),
            )
          : open
          ? TextButton(
              onPressed: busy ? null : () => setState(() => open = false),
              child: const Text('取消'),
            )
          : OutlinedButton(
              onPressed: () => setState(() => open = true),
              child: const Text('登录'),
            ),
      expanded: !open && error == null && verification == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (open && account == null && !locked) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: AutofillGroup(
                      child: Column(
                        children: [
                          TextField(
                            key: const ValueKey('pikpak-username'),
                            controller: username,
                            enabled: !busy,
                            autofocus: true,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            onSubmitted: (_) => passwordFocus.requestFocus(),
                            decoration: const InputDecoration(
                              labelText: 'PikPak 账号',
                              hintText: '邮箱或手机号',
                            ),
                          ),
                          const SizedBox(height: Gap.md),
                          TextField(
                            key: const ValueKey('pikpak-password'),
                            controller: password,
                            focusNode: passwordFocus,
                            enabled: !busy,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => login(),
                            decoration: const InputDecoration(labelText: '密码'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  FilledButton(
                    onPressed: busy ? null : login,
                    child: Text(busy ? '连接中…' : '登录 PikPak'),
                  ),
                ],
                if (error case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.md),
                    child: InlineIssue(message),
                  ),
                if (verification != null) ...[
                  const SizedBox(height: Gap.sm),
                  InlineIssue(
                    account == null
                        ? '在 PikPak 官方页面完成验证后，再点「登录 PikPak」重试'
                        : '在 PikPak 官方页面完成验证后，回到缓存页继续下载任务',
                  ),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => openExternal(context, verification),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('打开 PikPak 验证'),
                  ),
                ],
              ],
            ),
    );
  }
}

class _BilibiliRow extends StatefulWidget {
  const _BilibiliRow({required this.account});
  final BilibiliAccount account;

  @override
  State<_BilibiliRow> createState() => _BilibiliRowState();
}

class _BilibiliRowState extends State<_BilibiliRow> {
  /// The QR code shown while signing in.
  BilibiliQr? qr;
  BilibiliQrState state = BilibiliQrState.waiting;
  Timer? timer;
  bool busy = false, polling = false;
  String? error;

  BilibiliAccount get account => widget.account;

  @override
  void initState() {
    super.initState();
    // The membership may have changed since the app started.
    unawaited(check());
  }

  /// Reads the account's name and membership, showing why it could not.
  Future<void> check() async {
    try {
      await account.refresh();
    } catch (failure) {
      if (mounted) setState(() => error = errorMessage(failure));
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) setState(() => error = errorMessage(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Shows a new QR code and asks every two seconds whether it was
  /// scanned, until it signs in or expires.
  Future<void> start() => run(() async {
    timer?.cancel();
    final code = await account.startLogin();
    if (!mounted) return;
    setState(() {
      qr = code;
      state = BilibiliQrState.waiting;
    });
    timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  });

  Future<void> poll() async {
    final code = qr;
    if (code == null || polling) return;
    polling = true;
    try {
      final next = await account.poll(code);
      // Signed in even if the code was cancelled meanwhile; the name and
      // membership follow.
      if (next == BilibiliQrState.signedIn) unawaited(check());
      if (!mounted || !identical(qr, code)) return;
      setState(() {
        state = next;
        if (next == BilibiliQrState.signedIn) qr = null;
      });
      if (next == BilibiliQrState.signedIn || next == BilibiliQrState.expired) {
        timer?.cancel();
      }
    } catch (failure) {
      // A failed look is tried again on the next tick; a lasting one shows.
      if (mounted) setState(() => error = errorMessage(failure));
    } finally {
      polling = false;
    }
  }

  void cancel() {
    timer?.cancel();
    setState(() {
      qr = null;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) => _watch(account, (context) {
    final theme = Theme.of(context);
    final signedIn = account.signedIn && qr == null;
    final code = qr;
    return _ServiceRow(
      logo: 'assets/images/services/bilibili.png',
      name: '哔哩哔哩',
      status: signedIn
          ? account.name ?? 'B 站账号'
          : account.lapsed ?? '登录后可获取更多弹幕，大会员可播放会员剧集',
      statusColor: !signedIn && account.lapsed != null
          ? theme.colorScheme.error
          : null,
      badge: signedIn
          ? switch (account.membership) {
              final membership? => MelonBadge(membership, color: coral),
              null => null,
            }
          : null,
      action: signedIn
          ? TextButton(
              onPressed: busy
                  ? null
                  : () => _confirmSignOut(
                      context,
                      title: '退出 B 站登录？',
                      message: '退出后按访客读取 B 站的弹幕和视频，弹幕会变少，会员剧集无法播放。需要时可以重新扫码登录。',
                      onSignOut: () => run(account.signOut),
                    ),
              child: Text(busy ? '退出中…' : '退出登录'),
            )
          : code != null
          ? TextButton(onPressed: cancel, child: const Text('取消'))
          : OutlinedButton(
              onPressed: busy ? null : start,
              child: Text(busy ? '获取二维码…' : '扫码登录'),
            ),
      expanded: code == null && error == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (code != null) _scanning(context, code),
                if (error case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.md),
                    child: InlineIssue(message),
                  ),
              ],
            ),
    );
  });

  Widget _scanning(BuildContext context, BilibiliQr code) {
    final expired = state == BilibiliQrState.expired;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Black on white whatever the theme, as phone cameras read it.
        Opacity(
          opacity: expired ? .25 : 1,
          child: ClipRRect(
            borderRadius: controlBorderRadius,
            child: QrImageView(
              data: code.url,
              size: 148,
              backgroundColor: Colors.white,
              semanticsLabel: 'B 站登录二维码',
            ),
          ),
        ),
        const SizedBox(width: Gap.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (state) {
                BilibiliQrState.scanned => '已扫码，在手机上确认登录',
                BilibiliQrState.expired => '二维码已过期',
                _ => '用 B 站 App 扫码，在手机上确认登录',
              }),
              const SizedBox(height: Gap.xs),
              Text(
                '二维码 3 分钟内有效，不用输入密码',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (expired) ...[
                const SizedBox(height: Gap.md),
                FilledButton.icon(
                  onPressed: busy ? null : start,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('刷新二维码'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
