import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app_services.dart';

class ConnectionSettings extends StatefulWidget {
  const ConnectionSettings({super.key, required this.services});
  final AppServices services;
  @override
  State<ConnectionSettings> createState() => _ConnectionSettingsState();
}

class _ConnectionSettingsState extends State<ConnectionSettings> {
  final clientId = TextEditingController(),
      clientSecret = TextEditingController(),
      redirect = TextEditingController(text: 'http://127.0.0.1:14567/callback'),
      appId = TextEditingController(),
      appSecret = TextEditingController();
  String? error;
  bool saving = false, loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final oauth = await widget.services.account.configuration();
      final dandan = object(
        jsonDecode(
          await widget.services.credentials!.read('dandanplay') ?? '{}',
        ),
      );
      if (!mounted) return;
      clientId.text = '${oauth['clientId'] ?? ''}';
      clientSecret.text = '${oauth['clientSecret'] ?? ''}';
      redirect.text = '${oauth['redirectUri'] ?? redirect.text}';
      appId.text = '${dandan['appId'] ?? ''}';
      appSecret.text = '${dandan['appSecret'] ?? ''}';
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    final oauthId = clientId.text;
    final oauthSecret = clientSecret.text;
    final callback = redirect.text;
    final dandanId = appId.text;
    final dandanSecret = appSecret.text;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.services.account.configure(
        clientId: oauthId,
        clientSecret: oauthSecret,
        redirectUri: callback,
      );
      await widget.services.danmaku.configure(dandanId, dandanSecret);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('连接配置已加密保存')));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [clientId, clientSecret, redirect, appId, appSecret]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextField(
      controller: controller,
      enabled: !loading && !saving,
      obscureText: secret,
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
          const Text(
            '服务连接',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('浏览番剧和本地追番无需登录。连接 Bangumi 后可同步该账号的收藏；弹弹play凭据用于自动匹配弹幕。'),
          field('Bangumi Client ID', clientId),
          field('Bangumi Client Secret', clientSecret, secret: true),
          field('OAuth 回调地址', redirect),
          field('弹弹play App ID', appId),
          field('弹弹play App Secret', appSecret, secret: true),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: saving || loading ? null : _save,
            child: Text(saving ? '正在保存…' : '保存连接配置'),
          ),
        ],
      ),
    ),
  );
}
