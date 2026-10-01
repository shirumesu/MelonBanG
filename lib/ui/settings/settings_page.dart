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
    this.onSync,
    this.storageSettings,
    this.cacheSettings,
    this.syncBusy = false,
    this.needsAuthorization = false,
    this.accountBusy = false,
  });
  final Widget? storageSettings;
  final Widget? cacheSettings;
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
  final ValueChanged<bool> onThemeChanged;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int selected = 0;
  List<String> get categories => [
    '账户与同步',
    '界面与外观',
    '播放',
    if (widget.cacheSettings != null) '缓存方式',
    '下载与做种',
    '应用数据',
  ];
  List<IconData> get icons => [
    Icons.person_outline,
    Icons.palette_outlined,
    Icons.play_circle_outline,
    if (widget.cacheSettings != null) Icons.download_outlined,
    Icons.swap_vert,
    Icons.folder_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final account = widget.account;
    final signedIn = account != null && !widget.needsAuthorization;
    final pending = number(widget.sync['pendingMutationCount']).toInt();
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: constraints.maxWidth < 820 ? 176 : 204,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(pageGutter, Gap.lg, 0, Gap.lg),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, 0, Gap.md),
                  child: Text(
                    '设置',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                for (var i = 0; i < categories.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.xs),
                    child: ListTile(
                      dense: true,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    pageGutter,
                    Gap.lg + Gap.xs,
                    pageGutter,
                    0,
                  ),
                  child: Text(
                    categories[selected],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: _pages(context, account, signedIn, pending, muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pages(
    BuildContext context,
    Json? account,
    bool signedIn,
    int pending,
    Color muted,
  ) => IndexedStack(
    index: selected,
    children: [
      PageScroll(
        key: const PageStorageKey('settings-account'),
        children: [
          const SectionTitle(title: '账户'),
          MelonPanel(
            padding: EdgeInsets.zero,
            child: SettingRow(
              leading: AccountAvatar(
                url: account?['avatarUrl'] as String?,
                name: '${account?['nickname'] ?? ''}',
                size: 44,
              ),
              title: '${account?['nickname'] ?? '连接 Bangumi'}',
              subtitle: account == null
                  ? '同步你的追番收藏与章节记录'
                  : '@${account['username'] ?? ''} · ${widget.needsAuthorization ? '登录凭据待解锁' : '已连接 Bangumi'}',
              trailing: Wrap(
                spacing: Gap.sm,
                children: [
                  if (widget.accountBusy && !signedIn)
                    TextButton(
                      onPressed: widget.onCancelSignIn,
                      child: const Text('取消登录'),
                    ),
                  if (signedIn)
                    OutlinedButton.icon(
                      onPressed: widget.accountBusy
                          ? null
                          : widget.onAccountAction,
                      icon: const Icon(Icons.logout, size: 18),
                      label: Text(widget.accountBusy ? '退出中…' : '退出登录'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: widget.accountBusy
                          ? null
                          : widget.onAccountAction,
                      icon: const Icon(Icons.account_circle_outlined, size: 18),
                      label: Text(
                        widget.accountBusy
                            ? '连接中…'
                            : widget.needsAuthorization
                            ? '解锁同步'
                            : '登录 Bangumi',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SectionTitle(title: '同步'),
          MelonPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SettingRow(
                  title: account == null ? '追番记录保存在本机' : 'Bangumi 收藏与章节同步',
                  subtitle: widget.needsAuthorization
                      ? '登录凭据待授权，本地追番和播放记录仍可使用。点击「解锁同步」恢复连接。'
                      : account == null
                      ? '登录后可同步到 Bangumi，未登录也能记录追番。'
                      : pending > 0
                      ? '$pending 项修改等待上传，连接恢复后自动重试'
                      : '没有待上传修改；联网时自动同步收藏与章节记录。',
                  trailing: signedIn
                      ? OutlinedButton.icon(
                          onPressed: widget.syncBusy ? null : widget.onSync,
                          icon: const Icon(Icons.sync, size: 18),
                          label: Text(widget.syncBusy ? '同步中…' : '立即同步'),
                        )
                      : null,
                ),
                if (widget.sync['lastSyncError'] != null) ...[
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  SettingRow(
                    title: '上次同步失败',
                    subtitle: '${widget.sync['lastSyncError']}',
                    subtitleColor: coral,
                  ),
                ],
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
            child: SettingRow(
              title: '深色主题',
              subtitle: '浅色模式使用中性灰白页面与白色卡片',
              onTap: () => widget.onThemeChanged(!widget.dark),
              trailing: Switch(
                value: widget.dark,
                onChanged: widget.onThemeChanged,
              ),
            ),
          ),
        ],
      ),
      PageScroll(
        key: const PageStorageKey('settings-playback'),
        children: [
          const SectionTitle(title: '播放快捷键'),
          MelonPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, (action, keys)) in const [
                  ('播放 / 暂停', 'Space'),
                  ('后退 / 前进 5 秒', '← / →'),
                  ('显示屏全屏', 'F / F11'),
                  ('退出全屏或关闭菜单', 'Esc'),
                  ('静音', 'M'),
                  ('切换显示屏全屏', '双击画面'),
                ].indexed) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 20, endIndent: 20),
                  SettingRow(
                    title: action,
                    trailing: Text(
                      keys,
                      style: TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      if (widget.cacheSettings != null) widget.cacheSettings!,
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
  );
}

/// A settings line: label and explanation on the left, its control at the end.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.subtitleColor,
  });
  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    customBorder: CardTheme.of(context).shape,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: Gap.lg),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: Gap.lg)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: subtitleColor),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: Gap.lg), trailing!],
        ],
      ),
    ),
  );
}
