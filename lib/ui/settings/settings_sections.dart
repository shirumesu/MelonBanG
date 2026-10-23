import 'package:flutter/material.dart';

import '../../features/appearance/appearance.dart';
import '../../features/danmaku/danmaku_preferences.dart';
import '../../features/playback/playback_preferences.dart';
import '../../features/tracking/tracking_controller.dart';
import '../core/account_avatar.dart';
import '../core/action_feedback.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'settings_page.dart';

/// Rebuilds [builder] when [listenable] changes.
Widget _watch(Listenable listenable, WidgetBuilder builder) =>
    ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => builder(context),
    );

Widget _switch(bool value, ValueChanged<bool> onChanged) =>
    Switch(value: value, onChanged: onChanged);

Widget _menu<T>(Map<T, String> options, T value, ValueChanged<T> onSelected) =>
    MelonChoiceMenu<T>(options: options, value: value, onSelected: onSelected);

SettingsSection accountSection({
  required TrackingController personal,
  required VoidCallback onAccountAction,
  required VoidCallback onCancelSignIn,
  required VoidCallback? onSync,
  required bool syncBusy,
}) {
  bool signedIn() => personal.profile != null && !personal.needsAuthorization;
  return SettingsSection(
    id: 'account',
    title: '账户与同步',
    icon: Icons.person_outline,
    groups: [
      SettingsGroup([
        SettingsItem(
          '账户 登录 退出 Bangumi',
          _watch(personal, (context) {
            final account = personal.profile;
            return SettingRow(
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
                  if (personal.accountBusy && !signedIn())
                    TextButton(
                      onPressed: onCancelSignIn,
                      child: const Text('取消登录'),
                    ),
                  if (signedIn())
                    OutlinedButton.icon(
                      onPressed: personal.accountBusy ? null : onAccountAction,
                      icon: const Icon(Icons.logout, size: 18),
                      label: Text(personal.accountBusy ? '退出中…' : '退出登录'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: personal.accountBusy ? null : onAccountAction,
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
            );
          }),
        ),
        if (signedIn())
          SettingsItem(
            '同步 上传 收藏 进度',
            _watch(personal, (context) {
              final pending = personal.sync.pending;
              return SettingRow(
                title: pending > 0 ? '$pending 项修改待上传' : '已全部同步',
                subtitle: personal.sync.error == null
                    ? '联网时自动同步'
                    : '上次同步失败：${personal.sync.error}',
                subtitleColor: personal.sync.error == null ? null : coral,
                trailing: OutlinedButton.icon(
                  onPressed: syncBusy ? null : onSync,
                  icon: const Icon(Icons.sync, size: 18),
                  label: Text(syncBusy ? '同步中…' : '立即同步'),
                ),
              );
            }),
          ),
      ]),
    ],
  );
}

SettingsSection appearanceSection(Appearance appearance) => SettingsSection(
  id: 'appearance',
  title: '外观',
  icon: Icons.palette_outlined,
  groups: [
    SettingsGroup([
      SettingsItem(
        '主题模式 深色 浅色 跟随系统 暗色 夜间',
        _watch(
          appearance,
          (context) => SettingRow(
            title: '主题模式',
            trailing: SizedBox(
              width: 252,
              child: MelonSegmentedControl<ThemeChoice>(
                options: {
                  for (final choice in ThemeChoice.values) choice: choice.label,
                },
                value: appearance.mode,
                onChanged: appearance.setMode,
              ),
            ),
          ),
        ),
      ),
      SettingsItem(
        '主题色 颜色 强调色 系统强调色 配色',
        _watch(
          appearance,
          (context) => SettingRow(
            title: '主题色',
            subtitle:
                appearance.accent == 'system' && appearance.systemAccent == null
                ? '系统没有提供强调色，暂用薄荷'
                : null,
            trailing: _AccentPicker(appearance: appearance),
          ),
        ),
      ),
      SettingsItem(
        '封面取色 动态 动态配色 番剧封面',
        _watch(
          appearance,
          (context) => SettingRow(
            title: '封面取色',
            subtitle: '番剧详情和播放器使用这部番封面的颜色',
            onTap: () => appearance.setCoverColor(!appearance.coverColor),
            trailing: _switch(appearance.coverColor, appearance.setCoverColor),
          ),
        ),
      ),
    ]),
  ],
);

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.appearance});
  final Appearance appearance;

  @override
  Widget build(BuildContext context) {
    Widget swatch(String id, String name, Color? color) {
      final selected = appearance.accent == id;
      final scheme = Theme.of(context).colorScheme;
      return Tooltip(
        message: name,
        child: InkResponse(
          onTap: () => appearance.setAccent(id),
          radius: 20,
          child: AnimatedContainer(
            duration: motionDuration(context, 200),
            curve: Curves.easeOutCubic,
            width: 30,
            height: 30,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                gradient: color == null
                    ? const SweepGradient(
                        colors: [
                          Color(0xffff6b81),
                          Color(0xffffb83d),
                          Color(0xff22b388),
                          Color(0xff3b82e6),
                          Color(0xff8b6cf0),
                          Color(0xffff6b81),
                        ],
                      )
                    : null,
              ),
              child: AnimatedScale(
                scale: selected ? 1 : 0,
                duration: motionDuration(context, 220),
                curve: selected ? Curves.easeOutBack : Curves.easeIn,
                child: const Icon(Icons.check, size: 15, color: Colors.white),
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: Gap.xs,
      runSpacing: Gap.xs,
      children: [
        for (final preset in accentPresets)
          swatch(preset.id, preset.name, preset.color),
        swatch('system', '跟随系统强调色', appearance.systemAccent),
      ],
    );
  }
}

SettingsSection playbackSection(PlaybackPreferences prefs) {
  SettingsItem toggle(
    String keywords,
    String title,
    bool Function() value,
    Future<void> Function(bool) change, {
    String? subtitle,
  }) => SettingsItem(
    '$title $keywords ${subtitle ?? ''}',
    _watch(
      prefs,
      (context) => SettingRow(
        title: title,
        subtitle: subtitle,
        onTap: () => change(!value()),
        trailing: _switch(value(), change),
      ),
    ),
  );
  SettingsItem choice(
    String keywords,
    String title,
    Map<String, String> options,
    String Function() value,
    Future<void> Function(String) change, {
    String? subtitle,
    String? help,
  }) => SettingsItem(
    '$title $keywords ${options.values.join(' ')} ${subtitle ?? ''}',
    _watch(
      prefs,
      (context) => SettingRow(
        title: title,
        subtitle: subtitle,
        help: help,
        trailing: _menu(options, value(), change),
      ),
    ),
  );
  return SettingsSection(
    id: 'playback',
    title: '播放',
    icon: Icons.play_circle_outline,
    groups: [
      SettingsGroup([
        toggle(
          '连续播放 下一集',
          '自动连播',
          () => prefs.autoplay,
          prefs.setAutoplay,
          subtitle: '播完 5 秒后播放下一话',
        ),
        toggle(
          '看过 进度 标记',
          '自动标记为看过',
          () => prefs.autoMarkWatched,
          prefs.setAutoMarkWatched,
          subtitle: '播放进度达到 80% 时将本话标为已看',
        ),
        toggle(
          'op 片头 跳过',
          '自动跳过片头',
          () => prefs.skipOpening,
          prefs.setSkipOpening,
          subtitle: '视频内嵌章节标出 OP 时，播到片头直接跳到正片',
        ),
        toggle(
          'ed 片尾 跳过',
          '自动跳过片尾',
          () => prefs.skipEnding,
          prefs.setSkipEnding,
          subtitle: '视频内嵌章节标出 ED 时，播到片尾直接跳过',
        ),
      ], title: '播放'),
      SettingsGroup([
        choice(
          '硬解 硬件加速 解码器 hwdec gpu',
          '硬件解码',
          const {'auto': '自动', 'auto-copy': '兼容模式', 'no': '关闭'},
          () => prefs.hardwareDecoding,
          prefs.setHardwareDecoding,
          help:
              '自动：显卡解码，最省电\n'
              '兼容模式：可避开个别驱动的花屏、黑屏\n'
              '关闭：只用 CPU 解码',
        ),
      ], title: '画面'),
      SettingsGroup([
        choice(
          '字幕 语言 简体 繁体',
          '字幕语言',
          const {'chs': '简体中文', 'cht': '繁体中文', 'ja': '日语', 'auto': '自动'},
          () => prefs.subtitleLanguage,
          prefs.setSubtitleLanguage,
        ),
        choice(
          '音轨 语言 配音',
          '音轨语言',
          const {'ja': '日语', 'zh': '中文', 'auto': '自动'},
          () => prefs.audioLanguage,
          prefs.setAudioLanguage,
        ),
      ], title: '字幕与音轨'),
    ],
  );
}

SettingsSection sourcesSection(
  PlaybackPreferences prefs, {
  required Future<void> Function() onForgetSources,
}) {
  return SettingsSection(
    id: 'sources',
    title: '资源选择',
    icon: Icons.travel_explore,
    groups: [
      SettingsGroup([
        for (final (airing, title) in [(true, '放送中的番'), (false, '已完结的番')])
          SettingsItem(
            '$title 来源 优先级 在线 bt 优先',
            _watch(
              prefs,
              (context) => SettingRow(
                title: title,
                trailing: _menu(
                  const {'bt': 'BT 优先', 'online': '在线优先'},
                  airing ? prefs.airingPriority : prefs.completedPriority,
                  airing ? prefs.setAiringPriority : prefs.setCompletedPriority,
                ),
              ),
            ),
          ),
      ], title: '来源优先级'),
      SettingsGroup([
        SettingsItem(
          '记住 记忆 上次 来源 线路 字幕组 偏好',
          _watch(
            prefs,
            (context) => SettingRow(
              title: '记住每部番的来源',
              subtitle: '再看这部番时优先用上次的站点线路或字幕组，优先于上面的全局顺序',
              onTap: () => prefs.setRememberSource(!prefs.rememberSource),
              trailing: _switch(prefs.rememberSource, prefs.setRememberSource),
            ),
          ),
        ),
        SettingsItem(
          '清除 来源 记忆 忘记',
          SettingRow(
            title: '清除所有番剧的来源记忆',
            trailing: _ForgetSources(onForget: onForgetSources),
          ),
        ),
        SettingsItem(
          '自动 缓存 下一集 下一话 预下载',
          _watch(
            prefs,
            (context) => SettingRow(
              title: '播放时缓存下一话',
              subtitle: '一话看了两分钟后，用同一字幕组或线路缓存已播出的下一话',
              onTap: () => prefs.setCacheNext(!prefs.cacheNext),
              trailing: _switch(prefs.cacheNext, prefs.setCacheNext),
            ),
          ),
        ),
      ], title: '记忆与缓存'),
    ],
  );
}

class _ForgetSources extends StatefulWidget {
  const _ForgetSources({required this.onForget});
  final Future<void> Function() onForget;
  @override
  State<_ForgetSources> createState() => _ForgetSourcesState();
}

class _ForgetSourcesState extends State<_ForgetSources> {
  final feedback = ActionFeedback();

  @override
  void dispose() {
    feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FeedbackButton(
    feedback: feedback,
    label: '清除',
    runningLabel: '正在清除…',
    successLabel: '已清除',
    icon: Icons.delete_sweep_outlined,
    onPressed: () => feedback.run(() async {
      await widget.onForget();
      return null;
    }),
  );
}

SettingsSection danmakuSection(DanmakuPreferences prefs) {
  SettingsItem slider(
    String title,
    double Function() value,
    double min,
    double max,
    String Function() label,
    void Function(double) change,
  ) => SettingsItem(
    '弹幕 $title',
    _watch(
      prefs,
      (context) => SettingSlider(
        title: title,
        value: value(),
        min: min,
        max: max,
        label: label(),
        onChanged: (value) => prefs.update(() => change(value)),
      ),
    ),
  );
  Widget chip(String label, bool value, void Function(bool) change) =>
      FilterChip(
        label: Text(label),
        selected: value,
        onSelected: (value) => prefs.update(() => change(value)),
      );
  return SettingsSection(
    id: 'danmaku',
    title: '弹幕',
    icon: Icons.subtitles_outlined,
    groups: [
      SettingsGroup([
        SettingsItem(
          '显示弹幕 开关',
          _watch(
            prefs,
            (context) => SettingRow(
              title: '显示弹幕',
              onTap: () => prefs.update(() => prefs.enabled = !prefs.enabled),
              trailing: _switch(
                prefs.enabled,
                (value) => prefs.update(() => prefs.enabled = value),
              ),
            ),
          ),
        ),
        slider(
          '字号',
          () => prefs.size,
          14,
          36,
          () => '${prefs.size.round()}',
          (value) => prefs.size = value,
        ),
        slider(
          '不透明度',
          () => prefs.opacity,
          .1,
          1,
          () => '${(prefs.opacity * 100).round()}%',
          (value) => prefs.opacity = value,
        ),
        slider(
          '显示区域',
          () => prefs.area,
          .2,
          1,
          () => '${(prefs.area * 100).round()}%',
          (value) => prefs.area = value,
        ),
        SettingsItem(
          '弹幕 速度 极慢 较慢 适中 较快 极快',
          _watch(
            prefs,
            (context) => SettingRow(
              title: '速度',
              trailing: SizedBox(
                width: 300,
                child: MelonSegmentedControl<int>(
                  value: prefs.speed,
                  options: const {0: '极慢', 1: '较慢', 2: '适中', 3: '较快', 4: '极快'},
                  onChanged: (value) => prefs.update(() => prefs.speed = value),
                ),
              ),
            ),
          ),
        ),
        SettingsItem(
          '弹幕 密度 稀疏 正常 密集 全部',
          _watch(
            prefs,
            (context) => SettingRow(
              title: '密度',
              trailing: SizedBox(
                width: 252,
                child: MelonSegmentedControl<int>(
                  value: prefs.density,
                  options: const {0: '稀疏', 1: '正常', 2: '密集', 3: '全部'},
                  onChanged: (value) =>
                      prefs.update(() => prefs.density = value),
                ),
              ),
            ),
          ),
        ),
        SettingsItem(
          '弹幕 去重 合并 重复',
          _watch(
            prefs,
            (context) => SettingRow(
              title: '合并重复弹幕',
              subtitle: '10 秒内内容相同的弹幕只显示一条，并标出次数',
              onTap: () => prefs.update(() => prefs.merge = !prefs.merge),
              trailing: _switch(
                prefs.merge,
                (value) => prefs.update(() => prefs.merge = value),
              ),
            ),
          ),
        ),
        SettingsItem(
          '弹幕 类型 样式 滚动 顶部 底部 彩色 描边 重叠 防挡字幕',
          _watch(
            prefs,
            (context) => SettingRow(
              title: '类型与样式',
              trailing: Wrap(
                spacing: Gap.xs,
                runSpacing: Gap.xs,
                children: [
                  chip('滚动', prefs.scroll, (v) => prefs.scroll = v),
                  chip('顶部', prefs.top, (v) => prefs.top = v),
                  chip('底部', prefs.bottom, (v) => prefs.bottom = v),
                  chip('彩色', prefs.colorful, (v) => prefs.colorful = v),
                  chip('描边', prefs.stroke, (v) => prefs.stroke = v),
                  chip('允许重叠', prefs.overlap, (v) => prefs.overlap = v),
                  chip('防挡字幕', prefs.shield, (v) => prefs.shield = v),
                ],
              ),
            ),
          ),
        ),
        SettingsItem(
          '弹幕 恢复默认',
          SettingRow(
            title: '恢复默认显示',
            subtitle: '屏蔽规则和来源开关不受影响',
            trailing: TextButton(
              onPressed: prefs.resetDisplay,
              child: const Text('恢复默认'),
            ),
          ),
        ),
      ], title: '显示'),
      SettingsGroup([
        SettingsItem('弹幕 屏蔽 关键词 正则 过滤', _DanmakuFilters(preferences: prefs)),
      ], title: '屏蔽'),
    ],
  );
}

class _DanmakuFilters extends StatefulWidget {
  const _DanmakuFilters({required this.preferences});
  final DanmakuPreferences preferences;
  @override
  State<_DanmakuFilters> createState() => _DanmakuFiltersState();
}

class _DanmakuFiltersState extends State<_DanmakuFilters> {
  final input = TextEditingController();

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void add() {
    widget.preferences.addFilter(input.text);
    input.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.preferences,
    builder: (context, _) {
      final prefs = widget.preferences;
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    decoration: const InputDecoration(
                      hintText: '关键词，或用 /…/ 包住的正则表达式',
                    ),
                    onSubmitted: (_) => add(),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                TextButton(onPressed: add, child: const Text('添加')),
              ],
            ),
            if (prefs.filters.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Gap.md),
                child: Text(
                  '还没有屏蔽规则',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            for (final (index, rule) in prefs.filters.indexed)
              Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        rule.isRegex ? '/${rule.pattern}/' : rule.pattern,
                        style: TextStyle(
                          color: rule.invalid
                              ? scheme.error
                              : rule.enabled
                              ? null
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (rule.invalid)
                      Padding(
                        padding: const EdgeInsets.only(right: Gap.sm),
                        child: Text(
                          '正则无效',
                          style: TextStyle(color: scheme.error, fontSize: 12),
                        ),
                      ),
                    Switch(
                      value: rule.enabled,
                      onChanged: (value) => prefs.update(
                        () => prefs.filters[index] = DanmakuFilter(
                          rule.pattern,
                          isRegex: rule.isRegex,
                          enabled: value,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '删除屏蔽规则',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () =>
                          prefs.update(() => prefs.filters.removeAt(index)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

SettingsSection shortcutsSection() => SettingsSection(
  id: 'shortcuts',
  title: '快捷键',
  icon: Icons.keyboard_outlined,
  groups: [
    SettingsGroup([
      for (final (action, keys) in const [
        ('播放 / 暂停', 'Space / K / 单击画面'),
        ('后退 / 前进 5 秒', '← / →'),
        ('3 倍速快进', '按住 →'),
        ('回到开头', 'Home'),
        ('上一帧 / 下一帧', ', / .'),
        ('音量', '↑ / ↓'),
        ('静音', 'M'),
        ('弹幕开关', 'D'),
        ('全屏', 'F / F11 / 双击画面'),
        ('退出全屏', 'Esc'),
        ('搜索番剧', 'Ctrl / ⌘ + F'),
        ('返回', 'Alt + ← / ⌘ + ['),
      ])
        SettingsItem(
          '快捷键 按键 $action $keys',
          Builder(
            builder: (context) => SettingRow(
              title: action,
              trailing: Text(
                keys,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
    ]),
  ],
);
