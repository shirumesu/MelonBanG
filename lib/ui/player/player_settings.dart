import 'package:flutter/material.dart';

import '../../features/danmaku/danmaku_preferences.dart';
import '../../features/playback/playback.dart';
import '../core/theme.dart';
import 'player_controls.dart';
import 'player_popovers.dart';
import 'player_theme.dart';

/// The playback options worth changing mid-episode, behind the gear left of
/// super-resolution; the rest stay in settings.
class PlaybackMenu extends StatelessWidget {
  const PlaybackMenu({
    super.key,
    required this.playback,
    required this.onPopupChanged,
  });
  final Playback playback;
  final ValueChanged<bool> onPopupChanged;

  static const aspects = {
    'auto': '默认',
    '16:9': '16:9',
    '4:3': '4:3',
    '21:9': '21:9',
    'fill': '铺满',
  };

  @override
  Widget build(BuildContext context) {
    final settings = playback.settings;
    Widget toggle(String label, bool value, Future<void> Function(bool) set) =>
        _Row(
          label: label,
          labelWidth: 120,
          child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: .75,
              child: Switch(value: value, onChanged: set),
            ),
          ),
        );
    return HoverPopover(
      onPopupChanged: onPopupChanged,
      anchor: (popover) => IconButton(
        tooltip: '播放设置',
        isSelected: popover.open,
        onPressed: popover.toggle,
        icon: const PlayerGlyph(PlayerGlyphKind.settings),
      ),
      popover: (popover) => SizedBox(
        width: 264,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.md, Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              toggle('自动跳过片头', settings.skipOpening, settings.setSkipOpening),
              toggle('自动跳过片尾', settings.skipEnding, settings.setSkipEnding),
              toggle('自动连播', settings.autoplay, settings.setAutoplay),
              _Row(
                label: '画面比例',
                child: _Choice(
                  value: aspects.keys.toList().indexOf(playback.aspect),
                  options: aspects.values.toList(),
                  onChanged: (index) =>
                      playback.setAspect(aspects.keys.elementAt(index)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The danmaku options changed while watching, over the video. Sources,
/// matching and blocking live in the side panel's 弹幕 tab.
class DanmakuQuickSettings extends StatelessWidget {
  const DanmakuQuickSettings({
    super.key,
    required this.preferences,
    required this.onClose,
    this.onOpenSources,
    this.closeFocusNode,
    this.visibility = 1,
  });
  final DanmakuPreferences preferences;

  /// How far it has faded in.
  final double visibility;
  final VoidCallback onClose;

  /// Shows the panel's danmaku tab; null while the panel cannot show.
  final VoidCallback? onOpenSources;
  final FocusNode? closeFocusNode;

  @override
  Widget build(BuildContext context) => Theme(
    data: overlayTheme(),
    child: OverlayGlass(
      borderRadius: panelBorderRadius,
      visibility: visibility,
      child: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => _content(context),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    final prefs = preferences;
    Widget slider(
      String label,
      double value,
      double min,
      double max,
      String shown,
      void Function(double) change,
    ) => _Row(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              value: value,
              min: min,
              max: max,
              onChanged: (value) => prefs.update(() => change(value)),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              shown,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    Widget toggle(String label, bool value, void Function(bool) change) =>
        _Toggle(
          label: label,
          selected: value,
          onPressed: () => prefs.update(() => change(!value)),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.sm, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '弹幕设置',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                focusNode: closeFocusNode,
                tooltip: '关闭',
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18, color: Colors.white70),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: Gap.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                slider(
                  '不透明度',
                  prefs.opacity,
                  .1,
                  1,
                  '${(prefs.opacity * 100).round()}%',
                  (value) => prefs.opacity = value,
                ),
                slider(
                  '字号',
                  prefs.size,
                  14,
                  36,
                  '${prefs.size.round()}',
                  (value) => prefs.size = value,
                ),
                slider(
                  '显示区域',
                  prefs.area,
                  .2,
                  1,
                  '${(prefs.area * 100).round()}%',
                  (value) => prefs.area = value,
                ),
                _Row(
                  label: '速度',
                  child: _Choice(
                    value: prefs.speed,
                    options: const ['极慢', '较慢', '适中', '较快', '极快'],
                    onChanged: (value) =>
                        prefs.update(() => prefs.speed = value),
                  ),
                ),
                _Row(
                  label: '密度',
                  child: _Choice(
                    value: prefs.density,
                    options: const ['稀疏', '正常', '密集', '全部'],
                    onChanged: (value) =>
                        prefs.update(() => prefs.density = value),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    toggle('滚动', prefs.scroll, (v) => prefs.scroll = v),
                    toggle('顶部', prefs.top, (v) => prefs.top = v),
                    toggle('底部', prefs.bottom, (v) => prefs.bottom = v),
                    toggle('彩色', prefs.colorful, (v) => prefs.colorful = v),
                    toggle('描边', prefs.stroke, (v) => prefs.stroke = v),
                    toggle('允许重叠', prefs.overlap, (v) => prefs.overlap = v),
                    toggle('防挡字幕', prefs.shield, (v) => prefs.shield = v),
                    toggle('合并重复', prefs.merge, (v) => prefs.merge = v),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      onPressed: prefs.resetDisplay,
                      child: const Text('恢复默认'),
                    ),
                    const Spacer(),
                    if (onOpenSources != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        onPressed: onOpenSources,
                        child: const Text('来源与屏蔽 ›'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child, this.labelWidth = 56});
  final String label;
  final Widget child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// A compact segmented choice for the dark popover.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final int value;
  final List<String> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: badgeBorderRadius,
    ),
    child: Row(
      children: [
        for (final (index, option) in options.indexed)
          Expanded(
            child: Material(
              color: index == value ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onChanged(index),
                child: Center(
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: 12,
                      color: index == value
                          ? const Color(0xff15181d)
                          : Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// An on/off chip: brighter when on.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: selected,
    child: Material(
      color: Colors.white.withValues(alpha: selected ? .18 : .06),
      borderRadius: badgeBorderRadius,
      child: InkWell(
        borderRadius: badgeBorderRadius,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? Colors.white : Colors.white54,
              decoration: selected ? null : TextDecoration.lineThrough,
              decorationColor: Colors.white38,
            ),
          ),
        ),
      ),
    ),
  );
}
