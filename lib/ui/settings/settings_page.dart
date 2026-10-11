import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../features/tracking/tracking_controller.dart';
import '../core/account_avatar.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';
import '../core/selection_controls.dart';
import '../../features/playback/playback.dart';
import '../player/danmaku_preferences_editor.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.personal,
    required this.dark,
    required this.dataDirectory,
    required this.bitTorrentSettings,
    required this.onAccountAction,
    required this.onCancelSignIn,
    required this.onThemeChanged,
    this.onSync,
    this.playback,
    this.storageSettings,
    this.cacheSettings,
    this.syncBusy = false,
  });
  final TrackingController personal;
  final Playback? playback;
  final Widget? storageSettings;
  final Widget? cacheSettings;
  final VoidCallback? onSync;
  final bool syncBusy;
  final bool dark;
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

  TrackingController get personal => widget.personal;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: personal, builder: _page);

  Widget _page(BuildContext context, Widget? _) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final account = personal.profile;
    final signedIn = account != null && !personal.needsAuthorization;
    final pending = personal.sync.pending;
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
    AccountProfile? account,
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
                url: account?.avatarUrl,
                name: account?.nickname ?? '',
                size: 44,
              ),
              title: account?.nickname ?? '未登录',
              subtitle: account == null
                  ? '登录 Bangumi 后同步收藏和观看进度'
                  : personal.needsAuthorization
                  ? '登录凭据待解锁'
                  : '@${account.username ?? ''}',
              trailing: Wrap(
                spacing: Gap.sm,
                children: [
                  if (personal.accountBusy && !signedIn)
                    TextButton(
                      onPressed: widget.onCancelSignIn,
                      child: const Text('取消登录'),
                    ),
                  if (signedIn)
                    OutlinedButton.icon(
                      onPressed: personal.accountBusy
                          ? null
                          : widget.onAccountAction,
                      icon: const Icon(Icons.logout, size: 18),
                      label: Text(personal.accountBusy ? '退出中…' : '退出登录'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: personal.accountBusy
                          ? null
                          : widget.onAccountAction,
                      icon: const Icon(Icons.account_circle_outlined, size: 18),
                      label: Text(
                        personal.accountBusy
                            ? '连接中…'
                            : personal.needsAuthorization
                            ? '解锁同步'
                            : '登录 Bangumi',
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (signedIn) ...[
            const SectionTitle(title: '同步'),
            MelonPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SettingRow(
                    title: pending > 0 ? '$pending 项修改待上传' : '已全部同步',
                    subtitle: '联网时自动同步',
                    trailing: OutlinedButton.icon(
                      onPressed: widget.syncBusy ? null : widget.onSync,
                      icon: const Icon(Icons.sync, size: 18),
                      label: Text(widget.syncBusy ? '同步中…' : '立即同步'),
                    ),
                  ),
                  if (personal.sync.error case final error?) ...[
                    const Divider(height: 1, indent: 20, endIndent: 20),
                    SettingRow(
                      title: '上次同步失败',
                      subtitle: error,
                      subtitleColor: coral,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
      PageScroll(
        key: const PageStorageKey('settings-appearance'),
        children: [
          const SectionTitle(title: '主题'),
          MelonPanel(
            padding: EdgeInsets.zero,
            child: SettingRow(
              title: '深色主题',
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
          if (widget.playback != null) ...playbackSettings(),
          const SectionTitle(title: '播放快捷键'),
          MelonPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, (action, keys)) in const [
                  ('播放 / 暂停', 'Space / K / 单击画面'),
                  ('后退 / 前进 5 秒', '← / →'),
                  ('跳到 0%–90%', '0–9'),
                  ('回到开头', 'Home'),
                  ('上一帧 / 下一帧', ', / .'),
                  ('减速 / 加速', 'Shift + , / .'),
                  ('音量', '↑ / ↓'),
                  ('静音', 'M'),
                  ('弹幕开关', 'D'),
                  ('关灯', 'L'),
                  ('全屏', 'F / F11 / 双击画面'),
                  ('退出全屏', 'Esc'),
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
  List<Widget> playbackSettings() {
    final playback = widget.playback!;
    final prefs = playback.settings;
    Widget choice(
      String title,
      Map<String, String> values,
      String value,
      ValueChanged<String> change,
    ) => SettingRow(
      title: title,
      trailing: MelonChoiceMenu<String>(
        options: values,
        value: value,
        onSelected: change,
      ),
    );
    return [
      const SectionTitle(title: '播放偏好'),
      ListenableBuilder(
        listenable: prefs,
        builder: (_, _) => MelonPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SettingRow(
                title: '自动连播',
                subtitle: '播完 5 秒后播放下一话',
                trailing: Switch(
                  value: prefs.autoplay,
                  onChanged: prefs.setAutoplay,
                ),
              ),
              SettingRow(
                title: '自动标记为看过',
                subtitle: '播放进度达到 80% 时将本话标为看过',
                trailing: Switch(
                  value: prefs.autoMarkWatched,
                  onChanged: prefs.setAutoMarkWatched,
                ),
              ),
              choice(
                '字幕语言',
                const {'chs': '简体中文', 'cht': '繁体中文', 'ja': '日语', 'auto': '自动'},
                prefs.subtitleLanguage,
                prefs.setSubtitleLanguage,
              ),
              choice(
                '音轨语言',
                const {'ja': '日语', 'zh': '中文', 'auto': '自动'},
                prefs.audioLanguage,
                prefs.setAudioLanguage,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: prefs.resetLanguages,
                  child: const Text('恢复语言默认'),
                ),
              ),
            ],
          ),
        ),
      ),
      const SectionTitle(title: '来源优先级'),
      ListenableBuilder(
        listenable: prefs,
        builder: (_, _) => MelonPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              choice(
                '放送中的番',
                const {'bt': 'BT 优先', 'online': '在线优先'},
                prefs.airingPriority,
                prefs.setAiringPriority,
              ),
              choice(
                '已完结的番',
                const {'bt': 'BT 优先', 'online': '在线优先'},
                prefs.completedPriority,
                prefs.setCompletedPriority,
              ),
            ],
          ),
        ),
      ),
      const SectionTitle(title: '弹幕'),
      MelonPanel(
        child: DanmakuPreferencesEditor(
          preferences: playback.danmaku.preferences,
        ),
      ),
    ];
  }
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
