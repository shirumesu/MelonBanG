import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.account,
    required this.sync,
    required this.dark,
    required this.dataDirectory,
    required this.connectionSettings,
    required this.onAccountAction,
    required this.onCancelSignIn,
    required this.onThemeChanged,
    required this.onOpenVideo,
  });
  final Json? account;
  final Json sync;
  final bool dark;
  final String? dataDirectory;
  final Widget connectionSettings;
  final VoidCallback onAccountAction;
  final VoidCallback onCancelSignIn;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onOpenVideo;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      SectionTitle(title: '账户'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account == null
                    ? '连接 Bangumi，同步你的追番记录。'
                    : '已登录 · ${account!['nickname']}',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: onAccountAction,
                    icon: const Icon(Icons.account_circle_outlined),
                    label: Text(account == null ? '登录 Bangumi' : '退出登录'),
                  ),
                  TextButton(
                    onPressed: onCancelSignIn,
                    child: const Text('取消登录'),
                  ),
                ],
              ),
              if (sync['lastSyncError'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${sync['lastSyncError']}',
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
            ],
          ),
        ),
      ),
      connectionSettings,
      SectionTitle(title: '外观'),
      Card(
        child: SwitchListTile(
          title: const Text('深色主题'),
          value: dark,
          onChanged: onThemeChanged,
        ),
      ),
      SectionTitle(title: '本地播放'),
      Card(
        child: ListTile(
          leading: const Icon(Icons.video_file_outlined, color: mint),
          title: const Text('从本地文件开始观看'),
          subtitle: const Text('选择视频，或将视频文件路径作为启动参数。'),
          trailing: FilledButton(
            onPressed: onOpenVideo,
            child: const Text('打开'),
          ),
        ),
      ),
      SectionTitle(title: '应用数据'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('追番数据和播放进度保存在应用数据目录，独立于安装目录。'),
              const SizedBox(height: 8),
              SelectableText(dataDirectory ?? '正在准备…'),
            ],
          ),
        ),
      ),
    ],
  );
}
