import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app_services.dart';

class ConnectionSettings extends StatelessWidget {
  const ConnectionSettings({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text(
          '仅在登录、使用对应服务或点击编辑时读取凭据，本次运行内复用。macOS 使用钥匙串，Windows 使用系统账户加密。',
        ),
      ),
      _ServiceConnection(services: services, oauth: true),
      const SizedBox(height: 12),
      _ServiceConnection(services: services, oauth: false),
    ],
  );
}

class _ServiceConnection extends StatefulWidget {
  const _ServiceConnection({required this.services, required this.oauth});
  final AppServices services;
  final bool oauth;
  @override
  State<_ServiceConnection> createState() => _ServiceConnectionState();
}

class _ServiceConnectionState extends State<_ServiceConnection> {
  final id = TextEditingController(),
      secret = TextEditingController(),
      redirect = TextEditingController(text: 'http://127.0.0.1:14567/callback');
  bool editing = false, busy = false, saved = false;
  String? error;
  String get name => widget.oauth ? 'Bangumi' : '弹弹play';

  Future<void> edit() async {
    setState(() {
      busy = true;
      error = null;
      saved = false;
    });
    try {
      final config = widget.oauth
          ? await widget.services.account.configuration()
          : object(
              jsonDecode(
                await widget.services.credentials!.read('dandanplay') ?? '{}',
              ),
            );
      if (!mounted) return;
      id.text = '${config[widget.oauth ? 'clientId' : 'appId'] ?? ''}';
      secret.text =
          '${config[widget.oauth ? 'clientSecret' : 'appSecret'] ?? ''}';
      redirect.text = '${config['redirectUri'] ?? redirect.text}';
      setState(() => editing = true);
    } catch (e) {
      if (mounted) setState(() => error = '读取失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.oauth) {
        await widget.services.account.configure(
          clientId: id.text,
          clientSecret: secret.text,
          redirectUri: redirect.text,
        );
      } else {
        await widget.services.danmaku.configure(id.text, secret.text);
      }
      if (mounted) {
        setState(() {
          editing = false;
          saved = true;
          secret.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    id.dispose();
    secret.dispose();
    redirect.dispose();
    super.dispose();
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: PageStorageKey('connection-field:$label'),
      controller: controller,
      enabled: !busy,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      widget.oauth ? '登录并同步该账号的收藏' : '匹配、搜索和加载弹幕',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!editing)
                TextButton.icon(
                  onPressed: busy ? null : edit,
                  icon: Icon(
                    saved ? Icons.check : Icons.edit_outlined,
                    size: 18,
                  ),
                  label: Text(
                    busy
                        ? '正在读取…'
                        : saved
                        ? '已保存 · 编辑 $name'
                        : '编辑 $name',
                  ),
                ),
            ],
          ),
          if (editing) ...[
            field(widget.oauth ? 'Bangumi Client ID' : '弹弹play App ID', id),
            field(
              widget.oauth ? 'Bangumi Client Secret' : '弹弹play App Secret',
              secret,
              obscure: true,
            ),
            if (widget.oauth) field('OAuth 回调地址', redirect),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? '正在保存…' : '保存 $name'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          editing = false;
                          secret.clear();
                          error = null;
                        }),
                  child: const Text('取消'),
                ),
              ],
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}
