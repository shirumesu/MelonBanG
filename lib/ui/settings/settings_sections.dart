import 'package:flutter/material.dart';

import '../../features/appearance/appearance.dart';
import '../../features/danmaku/danmaku_preferences.dart';
import '../../features/playback/playback_preferences.dart';
import '../../domain/transfer.dart';
import '../../features/discovery/continue_range.dart';
import '../../features/subscriptions/subscription_preferences.dart';
import '../../features/tracking/tracking_controller.dart';
import '../core/account_avatar.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import '../player/danmaku_filter_editor.dart';
import 'preferred_groups.dart';
import 'settings_page.dart';

/// Rebuilds [builder] when [listenable] changes.
Widget _watch(Listenable listenable, WidgetBuilder builder) =>
    ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => builder(context),
    );

Widget _menu<T>(Map<T, String> options, T value, ValueChanged<T> onSelected) =>
    MelonChoiceMenu<T>(options: options, value: value, onSelected: onSelected);

SettingsSection accountSection({
  required TrackingController personal,
  required VoidCallback onAccountAction,
  required VoidCallback onCancelSignIn,
  required VoidCallback onUnlock,
  required VoidCallback onSaveCredentials,
}) {
  bool signedIn() =>
      personal.profile != null &&
      !personal.needsAuthorization &&
      !personal.sessionExpired;
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
                  ? '在浏览器中授权登录 Bangumi，之后同步收藏和观看进度'
                  : personal.sessionExpired
                  ? '登录已过期，重新登录后继续同步'
                  : personal.needsAuthorization
                  ? '没有获得钥匙串授权，暂时无法同步'
                  : personal.credentialsUnsaved
                  ? '续期后的登录没能保存到钥匙串，不保存的话下次打开需要重新登录'
                  : '@${account.username ?? ''}',
              subtitleColor:
                  account != null &&
                      (!signedIn() || personal.credentialsUnsaved)
                  ? Theme.of(context).colorScheme.error
                  : null,
              trailing: Wrap(
                spacing: Gap.sm,
                children: [
                  if (personal.accountBusy && !signedIn())
                    TextButton(
                      onPressed: onCancelSignIn,
                      child: const Text('取消登录'),
                    ),
                  if (signedIn() && personal.credentialsUnsaved)
                    FilledButton(
                      onPressed: onSaveCredentials,
                      child: const Text('保存'),
                    ),
                  if (signedIn())
                    OutlinedButton.icon(
                      onPressed: personal.accountBusy
                          ? null
                          : () => _confirmSignOut(context, onAccountAction),
                      icon: const Icon(Icons.logout, size: 18),
                      label: Text(
                        !personal.accountBusy
                            ? '退出登录'
                            : personal.signingIn
                            ? '登录中…'
                            : '退出中…',
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: personal.accountBusy
                          ? null
                          : personal.needsAuthorization &&
                                !personal.sessionExpired
                          ? onUnlock
                          : onAccountAction,
                      icon: const Icon(Icons.account_circle_outlined, size: 18),
                      label: Text(
                        personal.accountBusy
                            ? '等待浏览器授权…'
                            : personal.sessionExpired
                            ? '重新登录'
                            : personal.needsAuthorization
                            ? '授权钥匙串'
                            : '登录 Bangumi',
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ]),
    ],
  );
}

Future<void> _confirmSignOut(
  BuildContext context,
  VoidCallback onSignOut,
) async {
  final confirmed = await showMelonDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('退出 Bangumi 登录？'),
      content: const SizedBox(
        width: 400,
        child: Text('退出后不再同步收藏和观看进度，需要时可以重新在浏览器中授权登录。已缓存的番剧和订阅不受影响。'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('退出登录'),
        ),
      ],
    ),
  );
  if (confirmed == true) onSignOut();
}

SettingsSection appearanceSection(
  Appearance appearance,
  ContinuePreference range,
) => SettingsSection(
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
          (context) => SettingSwitch(
            title: '封面取色',
            subtitle: '番剧详情和播放器使用这部番封面的颜色',
            value: appearance.coverColor,
            onChanged: appearance.setCoverColor,
          ),
        ),
      ),
    ], title: '主题'),
    SettingsGroup([
      SettingsItem(
        '继续观看 首页 显示范围 当季 近两季 全部 在看',
        _watch(
          range,
          (context) => SettingRow(
            title: '首页继续观看',
            subtitle: '列出哪些在看的番：正在播出或这段时间播出过的',
            trailing: SizedBox(
              width: 252,
              child: MelonSegmentedControl<ContinueRange>(
                options: {
                  for (final value in ContinueRange.values) value: value.label,
                },
                value: range.value,
                onChanged: range.set,
              ),
            ),
          ),
        ),
      ),
      SettingsItem(
        '容量单位 大小 速度 字节 KiB MiB KB MB',
        _watch(
          appearance,
          (context) => SettingRow(
            title: '容量单位',
            subtitle: '文件大小和下载速度的单位：KiB 按 1024 进位，KB 按 1000 进位',
            trailing: SizedBox(
              width: 200,
              child: MelonSegmentedControl<ByteUnits>(
                options: {
                  for (final units in ByteUnits.values) units: units.label,
                },
                value: appearance.byteUnits,
                onChanged: appearance.setByteUnits,
              ),
            ),
          ),
        ),
      ),
    ], title: '显示'),
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
        child: Semantics(
          button: true,
          selected: selected,
          inMutuallyExclusiveGroup: true,
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
      (context) => SettingSwitch(
        title: title,
        subtitle: subtitle,
        value: value(),
        onChanged: change,
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
          '连续播放 下一集 特别篇 sp ova 番外',
          '自动连播',
          () => prefs.autoplay,
          prefs.setAutoplay,
          subtitle: '播完 5 秒后播放下一话，SP、OVA、番外按放送顺序一起连播',
        ),
        toggle(
          '总集篇 特番 访谈 跳过 特别篇 下一集',
          '跳过总集篇和特番',
          () => prefs.skipExtras,
          prefs.setSkipExtras,
          subtitle: '自动连播、下一话和缓存下一话按标题跳过总集篇、放送特番和访谈；正片只在标题写明总集篇时跳过',
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
          subtitle: '视频内嵌章节标出 OP 时，播到片头直接跳到正片，跳过前 5 秒提示，可取消',
        ),
        toggle(
          'ed 片尾 跳过',
          '自动跳过片尾',
          () => prefs.skipEnding,
          prefs.setSkipEnding,
          subtitle: '视频内嵌章节标出 ED 时，播到片尾直接跳过，跳过前 5 秒提示，可取消',
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
  required Iterable<String> Function() cachedGroups,
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
                trailing: SizedBox(
                  width: 200,
                  child: MelonSegmentedControl<String>(
                    options: const {'bt': 'BT 优先', 'online': '在线优先'},
                    value: airing
                        ? prefs.airingPriority
                        : prefs.completedPriority,
                    onChanged: airing
                        ? prefs.setAiringPriority
                        : prefs.setCompletedPriority,
                  ),
                ),
              ),
            ),
          ),
        SettingsItem(
          '记住 记忆 上次 来源 线路 字幕组 偏好',
          _watch(
            prefs,
            (context) => SettingSwitch(
              title: '记住每部番的来源',
              subtitle: '再看这部番时优先用上次的站点线路或字幕组，优先于上面的全局顺序',
              value: prefs.rememberSource,
              onChanged: prefs.setRememberSource,
            ),
          ),
        ),
      ], title: '来源优先级'),
      SettingsGroup([
        SettingsItem(
          '字幕组 偏好 优先 喜欢 bt 发布组 订阅',
          PreferredGroupsSetting(prefs: prefs, cachedGroups: cachedGroups),
        ),
        SettingsItem(
          '只显示 偏好 字幕组 隐藏 其他 默认 勾选',
          _watch(
            prefs,
            (context) => SettingSwitch(
              title: '查找资源时只显示偏好字幕组',
              subtitle: '打开查找资源时先勾选偏好字幕组，可以在字幕组菜单里取消',
              value: prefs.onlyPreferredGroups,
              onChanged: prefs.setOnlyPreferredGroups,
            ),
          ),
        ),
      ], title: '字幕组'),
    ],
  );
}

SettingsSection subscriptionSection(
  SubscriptionPreferences prefs,
  PlaybackPreferences playback,
) => SettingsSection(
  id: 'subscriptions',
  title: '订阅与缓存',
  icon: Icons.notifications_none_rounded,
  groups: [
    SettingsGroup([
      SettingsItem(
        '缓存到 订阅 BT PikPak 自动缓存',
        _watch(
          prefs,
          (context) => SettingRow(
            title: '缓存到',
            subtitle: '订阅的番剧新一话播出后缓存到哪里',
            trailing: SizedBox(
              width: 180,
              child: MelonSegmentedControl<CacheMethod>(
                options: {
                  for (final method in const [
                    CacheMethod.bt,
                    CacheMethod.pikpak,
                  ])
                    method: method.label,
                },
                value: prefs.method,
                onChanged: prefs.setMethod,
              ),
            ),
          ),
        ),
      ),
      SettingsItem(
        '修正版 v2 订阅 替换',
        _watch(
          prefs,
          (context) => SettingRow(
            title: '修正版',
            subtitle: '已缓存的集又出了 v2 时',
            trailing: SizedBox(
              width: 200,
              child: MelonSegmentedControl<RevisionPolicy>(
                options: {
                  for (final policy in RevisionPolicy.values)
                    policy: policy.label,
                },
                value: prefs.revisions,
                onChanged: prefs.setRevisions,
              ),
            ),
          ),
        ),
      ),
      SettingsItem(
        '自动取消订阅 订阅自动删除 完结 没看',
        _watch(
          prefs,
          (context) => SettingRow(
            title: '自动取消订阅',
            subtitle: '取消订阅不会删除已缓存的文件',
            trailing: SizedBox(
              width: 300,
              child: MelonSegmentedControl<AutoUnsubscribe>(
                options: {
                  for (final value in AutoUnsubscribe.values)
                    value: value.label,
                },
                value: prefs.autoUnsubscribe,
                onChanged: prefs.setAutoUnsubscribe,
              ),
            ),
          ),
        ),
      ),
      SettingsItem(
        '关闭窗口时 后台运行 留在后台 退出 托盘 菜单栏 订阅 自动缓存',
        _watch(
          prefs,
          (context) => SettingRow(
            title: '关闭窗口时',
            subtitle: prefs.closeAction == null
                ? '有订阅时，第一次关闭窗口会问一次'
                : '留在后台时，新一话播出后会检查并缓存；从托盘（Mac 的菜单栏或程序坞）回到窗口或退出。'
                      '没有订阅时关闭窗口就退出',
            trailing: SizedBox(
              width: 200,
              child: MelonSegmentedControl<CloseAction>(
                options: {
                  for (final action in CloseAction.values) action: action.label,
                },
                value: prefs.closeAction,
                onChanged: prefs.setCloseAction,
              ),
            ),
          ),
        ),
      ),
    ], title: '订阅'),
    SettingsGroup([
      SettingsItem(
        '自动 缓存 下一集 下一话 预下载 播放时',
        _watch(
          playback,
          (context) => SettingSwitch(
            title: '播放时缓存下一话',
            subtitle: '一话看了两分钟后，用同一字幕组或线路缓存已播出的下一话',
            value: playback.cacheNext,
            onChanged: playback.setCacheNext,
          ),
        ),
      ),
    ], title: '看番时'),
  ],
);

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
            (context) => SettingSwitch(
              title: '显示弹幕',
              value: prefs.enabled,
              onChanged: (value) => prefs.update(() => prefs.enabled = value),
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
          '弹幕 数量 上限 每集 性能 太多',
          _watch(prefs, (context) {
            const limits = DanmakuPreferences.limits;
            return SettingSlider(
              title: '每集最多显示',
              value: limits.indexOf(prefs.limit).toDouble(),
              min: 0,
              max: limits.length - 1,
              divisions: limits.length - 1,
              label: danmakuLimitLabel(prefs.limit),
              onChanged: (value) =>
                  prefs.update(() => prefs.limit = limits[value.round()]),
            );
          }),
        ),
        SettingsItem(
          '弹幕 去重 合并 重复',
          _watch(
            prefs,
            (context) => SettingSwitch(
              title: '合并重复弹幕',
              subtitle: '10 秒内内容相同的弹幕只显示一条，并标出次数',
              value: prefs.merge,
              onChanged: (value) => prefs.update(() => prefs.merge = value),
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
      ], title: '显示'),
      SettingsGroup([
        SettingsItem(
          '弹幕 屏蔽 关键词 正则 过滤',
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
            child: DanmakuFilterEditor(preferences: prefs, heading: false),
          ),
        ),
      ], title: '屏蔽'),
    ],
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
        ('发弹幕', 'Enter'),
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
