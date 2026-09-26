import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/cache_method.dart';
import '../../data/json.dart';
import '../../data/pikpak.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';

class CacheSettings extends StatefulWidget {
  const CacheSettings({
    super.key,
    required this.defaultMethod,
    required this.onMethodChanged,
    required this.onLogin,
    required this.onLogout,
    this.account,
    this.busy = false,
    this.error,
    this.needsAuthorization = false,
    this.onUnlock,
    this.verificationUrl,
  });

  final CacheMethod defaultMethod;
  final Future<void> Function(CacheMethod) onMethodChanged;
  final Future<void> Function(String, String) onLogin;
  final Future<void> Function() onLogout;
  final Json? account;
  final bool busy;
  final String? error;
  final bool needsAuthorization;
  final Future<void> Function()? onUnlock;
  final Uri? verificationUrl;

  @override
  State<CacheSettings> createState() => _CacheSettingsState();
}

class _CacheSettingsState extends State<CacheSettings> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool pending = false;
  String? error;
  Uri? captcha;

  bool get busy => pending || widget.busy;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      pending = true;
      error = null;
      captcha = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = '$failure'.replaceFirst('Bad state: ', '');
          if (failure is PikPakCaptchaRequired) captcha = failure.url;
        });
      }
    } finally {
      if (mounted) setState(() => pending = false);
    }
  }

  Future<void> login() => run(() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      throw StateError('请输入 PikPak 账号和密码。');
    }
    await widget.onLogin(username.text.trim(), password.text);
    password.clear();
  });

  Future<void> openCaptcha(Uri url) async {
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => error = '无法打开验证页面，请稍后重试。');
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final message = error ?? widget.error;
    final verificationUrl = captcha ?? widget.verificationUrl;
    return PageScroll(
      key: const PageStorageKey('settings-cache'),
      children: [
        const SectionTitle(title: '默认缓存方式'),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 280,
                child: MelonSegmentedControl<CacheMethod>(
                  options: {
                    for (final method in CacheMethod.values)
                      method: method.label,
                  },
                  value: widget.defaultMethod,
                  semanticLabel: '默认缓存方式',
                  onChanged: busy
                      ? null
                      : (method) => run(() => widget.onMethodChanged(method)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('BT 直接从节点下载到本机；PikPak 先在云端完成离线下载，再缓存到本机。'),
              const SizedBox(height: 8),
              Text(
                '下载按钮使用默认方式，右侧下拉菜单可为单个资源选择另一种方式。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SectionTitle(title: 'PikPak 账户'),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.needsAuthorization) ...[
                const Text('PikPak 凭据等待系统授权，解锁后可继续使用云端下载。'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy || widget.onUnlock == null
                      ? null
                      : () => run(widget.onUnlock!),
                  icon: const Icon(Icons.lock_open_outlined, size: 18),
                  label: const Text('解锁 PikPak'),
                ),
              ] else if (account != null) ...[
                Text(
                  '${account['displayName'] ?? account['name'] ?? account['username'] ?? account['email'] ?? 'PikPak'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const MelonBadge('已连接'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => run(widget.onLogout),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('退出 PikPak'),
                ),
              ] else ...[
                const Text('连接 PikPak 后可使用云端离线下载。云端任务完成后，即可开始缓存和播放。'),
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
              const SizedBox(height: 16),
              Text(
                'PikPak 的云端容量和离线下载额度取决于你的账户。移除本机缓存会保留云端文件。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
        ),
      ],
    );
  }
}
