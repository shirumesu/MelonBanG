import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error_message.dart';
import '../../domain/sources.dart';
import '../core/page_widgets.dart';

/// Sign-in of the PikPak account the PikPak source downloads with.
class PikPakAccount extends StatefulWidget {
  const PikPakAccount({
    super.key,
    required this.onLogin,
    required this.onLogout,
    required this.onUnlock,
    this.account,
    this.needsAuthorization = false,
    this.verificationUrl,
  });

  final Future<void> Function(String, String) onLogin;
  final Future<void> Function() onLogout;

  /// Signed-in PikPak account name.
  final String? account;
  final bool needsAuthorization;
  final Future<void> Function() onUnlock;
  final Uri? verificationUrl;

  @override
  State<PikPakAccount> createState() => _PikPakAccountState();
}

class _PikPakAccountState extends State<PikPakAccount> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  Uri? captcha;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      captcha = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(() {
          if (failure is SourceVerificationRequired) {
            error = 'PikPak 需要网页验证，请完成验证后重试';
            captcha = Uri.parse(failure.url);
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
    await widget.onLogin(username.text.trim(), password.text);
    password.clear();
  });

  Future<void> openCaptcha(Uri url) async {
    if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    if (mounted) setState(() => error = '无法打开验证页面，请稍后重试');
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final verificationUrl = captcha ?? widget.verificationUrl;
    return MelonPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.needsAuthorization) ...[
            const Text('PikPak 登录凭据待解锁'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : () => run(widget.onUnlock),
              icon: const Icon(Icons.lock_open_outlined, size: 18),
              label: const Text('解锁 PikPak'),
            ),
          ] else if (account != null) ...[
            Text(account, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: busy ? null : () => run(widget.onLogout),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('退出 PikPak'),
            ),
          ] else ...[
            const Text('登录后可用 PikPak 云端离线下载'),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('pikpak-username'),
                    controller: username,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'PikPak 账号',
                      hintText: '邮箱或手机号',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('pikpak-password'),
                    controller: password,
                    enabled: !busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => login(),
                    decoration: const InputDecoration(labelText: '密码'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : login,
              icon: const Icon(Icons.cloud_outlined, size: 18),
              label: Text(busy ? '连接中…' : '登录 PikPak'),
            ),
          ],
          if (error case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (verificationUrl != null) ...[
            const SizedBox(height: 8),
            Text(
              account == null
                  ? '在 PikPak 官方页面完成验证后，再点击「登录 PikPak」重试。'
                  : '在 PikPak 官方页面完成验证后，回到缓存页面继续下载任务。',
            ),
            TextButton.icon(
              onPressed: busy ? null : () => openCaptcha(verificationUrl),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('打开 PikPak 验证'),
            ),
          ],
        ],
      ),
    );
  }
}
