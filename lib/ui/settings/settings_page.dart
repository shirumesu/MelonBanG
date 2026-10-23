import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

/// One searchable entry of a settings group: usually a [SettingRow].
class SettingsItem {
  const SettingsItem(this.keywords, this.child);

  /// Words the search matches, including the visible labels.
  final String keywords;
  final Widget child;
}

/// Items shown together on one card, under an optional caption.
class SettingsGroup {
  const SettingsGroup(this.items, {this.title});
  final String? title;
  final List<SettingsItem> items;
}

/// A heading of the settings page and an entry of its contents column.
class SettingsSection {
  const SettingsSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.groups,
  });
  final String id, title;
  final IconData icon;
  final List<SettingsGroup> groups;
}

/// Every setting on one scrolling page: the contents column on the left
/// jumps to a section and follows the scroll position, and the search box
/// filters the rows. New settings join a section without adding pages or
/// nested navigation.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.sections});
  final List<SettingsSection> sections;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final scroll = ScrollController();
  final query = TextEditingController();
  final viewport = GlobalKey();
  final keys = <String, GlobalKey>{};
  String? current;

  /// Set while a contents click scrolls, so passing sections do not flash
  /// in the column.
  String? jumping;

  @override
  void dispose() {
    scroll.dispose();
    query.dispose();
    super.dispose();
  }

  List<SettingsSection> get visible {
    final text = query.text.trim().toLowerCase();
    if (text.isEmpty) return widget.sections;
    bool matches(String value) => value.toLowerCase().contains(text);
    return [
      for (final section in widget.sections)
        if (matches(section.title))
          section
        else if ([
              for (final group in section.groups)
                if (group.items.any((item) => matches(item.keywords)))
                  SettingsGroup(
                    group.items
                        .where((item) => matches(item.keywords))
                        .toList(),
                    title: group.title,
                  ),
            ]
            case final groups when groups.isNotEmpty)
          SettingsSection(
            id: section.id,
            title: section.title,
            icon: section.icon,
            groups: groups,
          ),
    ];
  }

  /// The last section whose heading has scrolled to the top of the page.
  void follow() {
    if (jumping != null) return;
    final box = viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final sections = visible;
    String? found = sections.firstOrNull?.id;
    for (final section in sections) {
      final heading =
          keys[section.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (heading == null || !heading.attached) continue;
      if (heading.localToGlobal(Offset.zero).dy - top <= 96) {
        found = section.id;
      }
    }
    if (scroll.hasClients &&
        scroll.position.pixels >= scroll.position.maxScrollExtent - 4) {
      found = sections.lastOrNull?.id ?? found;
    }
    if (found != current) setState(() => current = found);
  }

  Future<void> jump(String id) async {
    final target = keys[id]?.currentContext;
    if (target == null) return;
    setState(() => current = jumping = id);
    await Scrollable.ensureVisible(
      target,
      duration: motionDuration(context, 260),
      curve: Curves.easeOutCubic,
    );
    if (mounted) setState(() => jumping = null);
  }

  @override
  Widget build(BuildContext context) {
    final sections = visible;
    final selected = sections.any((s) => s.id == current)
        ? current
        : sections.firstOrNull?.id;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: constraints.maxWidth < 820 ? 172 : 212,
            child: _Contents(
              sections: sections,
              selected: selected,
              query: query,
              onQuery: () => setState(() {
                current = null;
                if (scroll.hasClients) scroll.jumpTo(0);
              }),
              onSelect: jump,
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Only the page's own scrolling. A list inside a setting can
                // report while it is laid out, when positions cannot be read
                // yet, so those wait for the frame to finish.
                if (notification.depth != 0) return false;
                if (SchedulerBinding.instance.schedulerPhase ==
                    SchedulerPhase.persistentCallbacks) {
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (mounted) follow();
                  });
                } else {
                  follow();
                }
                return false;
              },
              child: LayoutBuilder(
                key: viewport,
                builder: (context, viewportSize) => SingleChildScrollView(
                  key: const PageStorageKey('settings-scroll'),
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(
                    pageGutter,
                    Gap.sm,
                    pageGutter,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (sections.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: Gap.xl),
                              child: EmptyState(
                                text: '没有与“${query.text.trim()}”相关的设置',
                              ),
                            ),
                          for (final (index, section) in sections.indexed)
                            _SectionView(
                              key: keys.putIfAbsent(section.id, GlobalKey.new),
                              section: section,
                              first: index == 0,
                            ),
                          // The last sections can still scroll to the top.
                          SizedBox(
                            height: math.max(
                              Gap.xxl,
                              viewportSize.maxHeight * .6,
                            ),
                          ),
                        ],
                      ),
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
}

class _Contents extends StatelessWidget {
  const _Contents({
    required this.sections,
    required this.selected,
    required this.query,
    required this.onQuery,
    required this.onSelect,
  });
  final List<SettingsSection> sections;
  final String? selected;
  final TextEditingController query;
  final VoidCallback onQuery;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(pageGutter, Gap.lg, 0, Gap.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, 0, Gap.md),
          child: Text('设置', style: Theme.of(context).textTheme.titleLarge),
        ),
        TextField(
          controller: query,
          onChanged: (_) => onQuery(),
          decoration: InputDecoration(
            hintText: '搜索设置',
            prefixIcon: const Icon(Icons.search, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            suffixIcon: ListenableBuilder(
              listenable: query,
              builder: (context, _) => query.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: '清除',
                      iconSize: 16,
                      onPressed: () {
                        query.clear();
                        onQuery();
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        Expanded(
          child: ListView(
            children: [
              // The highlight follows the page as it scrolls through the
              // sections.
              MotionSelection<String>(
                selected: selected,
                highlight: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).listTileTheme.selectedTileColor,
                    borderRadius: controlBorderRadius,
                  ),
                ),
                builder: (context, keyOf) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final section in sections)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.xs),
                        child: ListTile(
                          key: keyOf(section.id),
                          dense: true,
                          selected: section.id == selected,
                          selectedTileColor: Colors.transparent,
                          leading: Icon(section.icon, size: 20),
                          titleTextStyle: Theme.of(context)
                              .textTheme
                              .titleSmall,
                          title: Text(section.title),
                          onTap: () => onSelect(section.id),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionView extends StatelessWidget {
  const _SectionView({super.key, required this.section, required this.first});
  final SettingsSection section;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: first ? Gap.lg : 40, bottom: Gap.md),
          child: Row(
            children: [
              Icon(section.icon, size: 20, color: accentOf(context).accent),
              const SizedBox(width: Gap.sm),
              Text(section.title, style: text.titleMedium),
            ],
          ),
        ),
        for (final (index, group) in section.groups.indexed) ...[
          if (group.title case final title?)
            Padding(
              padding: EdgeInsets.fromLTRB(
                Gap.xs,
                index == 0 ? 0 : Gap.lg,
                Gap.xs,
                Gap.sm,
              ),
              child: Text(
                title,
                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            )
          else if (index > 0)
            const SizedBox(height: Gap.md),
          MelonPanel(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (row, item) in group.items.indexed) ...[
                  if (row > 0)
                    const Divider(height: 1, indent: 20, endIndent: 20),
                  item.child,
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A settings line: label and explanation on the left, its control at the
/// end. Narrow rows put a wide [trailing] control under the label.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.subtitleColor,
    this.help,
  });
  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  final Color? subtitleColor;

  /// A longer explanation behind a ? mark beside the title.
  final String? help;

  @override
  Widget build(BuildContext context) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (help != null) ...[
              const SizedBox(width: Gap.xs),
              HelpHint(message: help!),
            ],
          ],
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
    );
    return InkWell(
      onTap: onTap,
      customBorder: CardTheme.of(context).shape,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (trailing != null && constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (leading != null) ...[
                        leading!,
                        const SizedBox(width: Gap.lg),
                      ],
                      Expanded(child: label),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  trailing!,
                ],
              );
            }
            return Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: Gap.lg),
                ],
                Expanded(child: label),
                if (trailing != null) ...[
                  const SizedBox(width: Gap.xl),
                  trailing!,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A row whose control is a slider with its value beside it.
class SettingSlider extends StatelessWidget {
  const SettingSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    this.divisions,
    this.onChangeEnd,
  });
  final String title, label;
  final double value, min, max;
  final int? divisions;
  final ValueChanged<double>? onChanged, onChangeEnd;

  @override
  Widget build(BuildContext context) => SettingRow(
    title: title,
    trailing: SizedBox(
      width: 300,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A ? mark whose tooltip also opens on click. The note shows to its right,
/// so it never covers the subtitle under the title; write it as short lines.
class HelpHint extends StatefulWidget {
  const HelpHint({super.key, required this.message});
  final String message;
  @override
  State<HelpHint> createState() => _HelpHintState();
}

class _HelpHintState extends State<HelpHint> {
  final tooltip = GlobalKey<TooltipState>();
  @override
  Widget build(BuildContext context) => Tooltip(
    key: tooltip,
    message: widget.message,
    constraints: const BoxConstraints(maxWidth: 320),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    textAlign: TextAlign.start,
    positionDelegate: _beside,
    child: IconButton(
      onPressed: () => tooltip.currentState?.ensureTooltipVisible(),
      icon: const Icon(Icons.help_outline_rounded),
      iconSize: 14,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
      visualDensity: VisualDensity.compact,
    ),
  );

  /// Right of the mark and vertically centred on it; left when the window
  /// is too narrow.
  static Offset _beside(TooltipPositionContext context) {
    const gap = 6.0, margin = 8.0;
    final overlay = context.overlaySize, size = context.tooltipSize;
    final half = context.targetSize.width / 2;
    final right = context.target.dx + half + gap;
    final x = right + size.width <= overlay.width - margin
        ? right
        : math.max(margin, context.target.dx - half - gap - size.width);
    final y = (context.target.dy - size.height / 2)
        .clamp(margin, math.max(margin, overlay.height - size.height - margin))
        .toDouble();
    return Offset(x, y);
  }
}
