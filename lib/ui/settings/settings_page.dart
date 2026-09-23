import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/account_avatar.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.account,
    required this.sync,
    required this.dark,
    required this.dataDirectory,
    required this.bitTorrentSettings,
    required this.onAccountAction,
    required this.onCancelSignIn,
    required this.onThemeChanged,
    this.onBack,
    this.onSync,
    this.storageSettings,
    this.syncBusy = false,
    this.needsAuthorization = false,
    this.accountBusy = false,
  });
  final Widget? storageSettings;
  final VoidCallback? onSync;
  final bool syncBusy;
  final Json? account;
  final Json sync;
  final bool dark;
  final bool needsAuthorization;
  final bool accountBusy;
  final String? dataDirectory;
  final Widget bitTorrentSettings;
  final VoidCallback onAccountAction, onCancelSignIn;
  final VoidCallback? onBack;
  final ValueChanged<bool> onThemeChanged;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int selected = 0;
  static const categories = ['账户与同步', '界面与外观', '播放', '下载与做种', '应用数据'];
  static const icons = [
    Icons.person_outline,
    Icons.palette_outlined,
    Icons.play_circle_outline,
    Icons.swap_vert,
    Icons.folder_outlined,
  ];
  @override
  Widget build(BuildContext context) => Row(
    children: [
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
              Padding(
                padding: const EdgeInsets.fromLTRB(pageGutter, 0, 0, 24),
                child: Text(
                  '设置',
                  style: Theme.of(context).textTheme.titleLarge,
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
              padding: const EdgeInsets.fromLTRB(
                pageGutter,
                28,
                pageGutter,
                20,
              ),
              child: Text(
                categories[selected],
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: selected,
                children: [
                  PageScroll(
                    key: const PageStorageKey('settings-account'),
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
                                AccountAvatar(
                                  url: widget.account?['avatarUrl'] as String?,
                                  name: '${widget.account?['nickname'] ?? ''}',
                                  size: 54,
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
                                  MelonBadge(
                                    widget.needsAuthorization ? '待解锁' : '已连接',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              children: [
                                if (widget.account != null &&
                                    !widget.needsAuthorization)
                                  OutlinedButton.icon(
                                    onPressed: widget.accountBusy
                                        ? null
                                        : widget.onAccountAction,
                                    icon: const Icon(Icons.logout, size: 18),
                                    label: Text(
                                      widget.accountBusy ? '退出中…' : '退出登录',
                                    ),
                                  )
                                else
                                  FilledButton.icon(
                                    onPressed: widget.accountBusy
                                        ? null
                                        : widget.onAccountAction,
                                    icon: const Icon(
                                      Icons.account_circle_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      widget.accountBusy
                                          ? '连接中…'
                                          : widget.needsAuthorization
                                          ? '解锁同步'
                                          : '登录 Bangumi',
                                    ),
                                  ),
                                if (widget.accountBusy &&
                                    (widget.account == null ||
                                        widget.needsAuthorization))
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
                            Text(
                              widget.account == null
                                  ? '追番记录保存在本机'
                                  : 'Bangumi 收藏与章节同步',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.needsAuthorization
                                  ? '登录凭据待授权，本地追番和播放记录仍可使用。点击「解锁同步」恢复连接。'
                                  : widget.account == null
                                  ? '登录后可同步到 Bangumi，未登录也能记录追番。'
                                  : number(
                                          widget.sync['pendingMutationCount'],
                                        ) >
                                        0
                                  ? '${number(widget.sync['pendingMutationCount']).toInt()} 项修改等待上传，连接恢复后自动重试'
                                  : '没有待上传修改；联网时自动同步收藏与章节记录。',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            if (widget.account != null &&
                                !widget.needsAuthorization)
                              TextButton.icon(
                                onPressed: widget.syncBusy
                                    ? null
                                    : widget.onSync,
                                icon: const Icon(Icons.sync),
                                label: Text(widget.syncBusy ? '同步中…' : '立即同步'),
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
                    key: const PageStorageKey('settings-appearance'),
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
                  PageScroll(
                    key: const PageStorageKey('settings-playback'),
                    children: [
                      const SectionTitle(title: '播放快捷键'),
                      const MelonPanel(
                        child: Column(
                          children: [
                            ListTile(
                              title: Text('播放 / 暂停'),
                              trailing: Text('Space'),
                            ),
                            ListTile(
                              title: Text('后退 / 前进 5 秒'),
                              trailing: Text('← / →'),
                            ),
                            ListTile(
                              title: Text('显示屏全屏'),
                              trailing: Text('F / F11'),
                            ),
                            ListTile(
                              title: Text('退出全屏或关闭菜单'),
                              trailing: Text('Esc'),
                            ),
                            ListTile(title: Text('静音'), trailing: Text('M')),
                            ListTile(
                              title: Text('切换显示屏全屏'),
                              trailing: Text('双击画面'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  widget.bitTorrentSettings,
                  PageScroll(
                    key: const PageStorageKey('settings-data'),
                    children: [
                      if (widget.storageSettings != null)
                        widget.storageSettings!
                      else ...[
                        const SectionTitle(title: '应用数据'),
                        MelonPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('追番记录、播放进度与安装目录分开保存。'),
                              const SizedBox(height: 14),
                              SelectableText(
                                widget.dataDirectory ?? '正在准备…',
                                key: const PageStorageKey('settings-data-path'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
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
