import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/error_message.dart';
import '../../integrations/sources/bilibili_account.dart';
import '../core/action_feedback.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

/// Sign-in of the Bilibili account the Bilibili video source and danmaku
/// read as: a QR code to scan with the Bilibili app, then the account.
class BilibiliAccountPanel extends StatefulWidget {
  const BilibiliAccountPanel({super.key, required this.account});
  final BilibiliAccount account;

  @override
  State<BilibiliAccountPanel> createState() => _BilibiliAccountPanelState();
}

class _BilibiliAccountPanelState extends State<BilibiliAccountPanel> {
  /// The QR code shown, while signing in.
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
    unawaited(account.refresh());
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: account,
    builder: (context, _) => MelonPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (account.signedIn && qr == null)
            ..._signedIn(context)
          else if (qr case final code?)
            ..._scanning(context, code)
          else
            ..._signedOut(),
          if (error case final message?)
            Padding(
              padding: const EdgeInsets.only(top: Gap.md),
              child: InlineIssue(message),
            ),
        ],
      ),
    ),
  );

  List<Widget> _signedIn(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Wrap(
        spacing: Gap.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(account.name ?? 'B 站账号', style: theme.textTheme.titleMedium),
          if (account.membership case final membership?)
            MelonBadge(membership, color: coral),
        ],
      ),
      const SizedBox(height: Gap.xs),
      Text(
        account.vip
            ? 'B 站的弹幕和视频按这个账号读取：弹幕更全，会员集可以播放，画质随大会员'
            : 'B 站的弹幕和视频按这个账号读取，弹幕比游客多得多',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: Gap.lg),
      OutlinedButton.icon(
        onPressed: busy ? null : () => run(account.signOut),
        icon: const Icon(Icons.logout, size: 18),
        label: const Text('退出 B 站'),
      ),
    ];
  }

  List<Widget> _signedOut() => [
    if (account.lapsed case final reason?) ...[
      InlineIssue(reason),
      const SizedBox(height: Gap.sm),
    ],
    const Text('登录后读到的 B 站弹幕多得多；大会员还能播放会员集、看更高画质。用 B 站 App 扫码，不用输入密码。'),
    const SizedBox(height: Gap.lg),
    FilledButton.icon(
      onPressed: busy ? null : start,
      icon: const Icon(Icons.qr_code_2_rounded, size: 18),
      label: Text(busy ? '正在获取二维码…' : '扫码登录'),
    ),
  ];

  List<Widget> _scanning(BuildContext context, BilibiliQr code) {
    final expired = state == BilibiliQrState.expired;
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Black on white whatever the theme, as phone cameras read it.
          Opacity(
            opacity: expired ? .25 : 1,
            child: ClipRRect(
              borderRadius: controlBorderRadius,
              child: QrImageView(
                data: code.url,
                size: 168,
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
                  BilibiliQrState.expired => '二维码过期了',
                  _ => '用 B 站 App 扫码，在手机上确认登录',
                }),
                const SizedBox(height: Gap.xs),
                Text(
                  '二维码 3 分钟内有效',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: Gap.lg),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [
                    if (expired)
                      FilledButton.icon(
                        onPressed: busy ? null : start,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('换一个'),
                      ),
                    TextButton(onPressed: cancel, child: const Text('取消')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }
}
