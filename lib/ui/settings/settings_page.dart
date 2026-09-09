import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

class SettingsPage extends StatefulWidget {
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
    this.onBack,
    this.showSidebar = true,
  });
  final Json? account;
  final Json sync;
  final bool dark, showSidebar;
  final String? dataDirectory;
  final Widget connectionSettings;
  final VoidCallback onAccountAction, onCancelSignIn, onOpenVideo;
  final VoidCallback? onBack;
  final ValueChanged<bool> onThemeChanged;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int selected = 0;
  static const categories = ['账户与同步', '界面与外观', '服务连接', '播放', '应用数据'];
  static const icons = [
    Icons.person_outline,
    Icons.palette_outlined,
    Icons.dns_outlined,
    Icons.play_circle_outline,
    Icons.folder_outlined,
  ];
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (widget.showSidebar)
        Container(
          width: 236,
          decoration: BoxDecoration(gradient: sidebarSurface(context)),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: TextButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('返回'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(26, 0, 0, 24),
                  child: Text(
                    '设置',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                for (var i = 0; i < categories.length; i++)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: ListTile(
                      selected: selected == i,
                      leading: Icon(icons[i], size: 20),
                      titleTextStyle: Theme.of(context).textTheme.titleSmall,
                      title: Text(categories[i]),
                      onTap: () => setState(() => selected = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
              child: Text(
                categories[selected],
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: selected,
                children: [
                  PageScroll(
                    children: [
                      Text(
                        '管理你的 Bangumi 账户连接与数据同步。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      const SectionTitle(title: '账户'),
                      MelonPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  backgroundColor: grape,
                                  child: Icon(
                                    Icons.person_outline,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${widget.account?['nickname'] ?? '连接 Bangumi'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.account == null
                                            ? '同步你的追番收藏与章节记录'
                                            : '@${widget.account!['username'] ?? ''}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.account != null)
                                  const MelonBadge('已连接'),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: widget.onAccountAction,
                                  icon: const Icon(
                                    Icons.account_circle_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    widget.account == null
                                        ? '登录 Bangumi'
                                        : '退出登录',
                                  ),
                                ),
                                if (widget.account == null)
                                  TextButton(
                                    onPressed: widget.onCancelSignIn,
                                    child: const Text('取消登录'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SectionTitle(title: '同步'),
                      MelonPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '追番记录自动保存在本机',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.account == null
                                  ? '登录后可同步到 Bangumi，未登录也能记录追番。'
                                  : '${number(widget.sync['pendingMutationCount']).toInt()} 项修改等待同步',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            if (widget.sync['lastSyncError'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  '${widget.sync['lastSyncError']}',
                                  style: const TextStyle(color: coral),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  PageScroll(
                    children: [
                      const SectionTitle(title: '主题模式'),
                      MelonPanel(
                        padding: EdgeInsets.zero,
                        child: SwitchListTile(
                          contentPadding: const EdgeInsets.all(20),
                          shape: CardTheme.of(context).shape,
                          title: const Text('深色主题'),
                          subtitle: const Text('浅色模式使用中性灰白页面与白色卡片'),
                          value: widget.dark,
                          onChanged: widget.onThemeChanged,
                        ),
                      ),
                    ],
                  ),
                  PageScroll(children: [widget.connectionSettings]),
                  PageScroll(
                    children: [
                      const SectionTitle(title: '本地播放'),
                      MelonPanel(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.video_file_outlined,
                            color: mint,
                          ),
                          title: const Text('从本地文件开始观看'),
                          subtitle: const Text('支持内嵌字幕、音轨和弹幕'),
                          trailing: FilledButton(
                            onPressed: widget.onOpenVideo,
                            child: const Text('打开'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  PageScroll(
                    children: [
                      const SectionTitle(title: '应用数据'),
                      MelonPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('追番记录、播放进度与安装目录分开保存。'),
                            const SizedBox(height: 14),
                            SelectableText(
                              widget.dataDirectory ?? '正在准备…',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
