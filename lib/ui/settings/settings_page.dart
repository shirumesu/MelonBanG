import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/app_chrome.dart';
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
  const SettingsPage({super.key, required this.sections, this.initial});
  final List<SettingsSection> sections;

  /// The section shown first, by id.
  final String? initial;
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

  /// The section a contents click landed on, washed briefly; [flashes]
  /// replays it on another click.
  String? flashing;
  int flashes = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initial case final id?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(jump(id));
      });
    }
  }

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

  Future<void> jump(String id, {bool flash = false}) async {
    final target = keys[id]?.currentContext;
    if (target == null) return;
    setState(() => current = jumping = id);
    await Scrollable.ensureVisible(
      target,
      duration: motionDuration(context, 260),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    setState(() {
      jumping = null;
      if (flash) {
        flashing = id;
        flashes++;
      }
    });
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
              onSelect: (id) => jump(id, flash: true),
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
                      child: _SearchQuery(
                        text: query.text.trim(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (sections.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: Gap.xl),
                                child: EmptyState(
                                  text: '没有与“${query.text.trim()}”相关的设置',
                                  detail: '换个说法试试，比如“代理”“字幕组”“缓存”',
                                  actionLabel: '清除搜索',
                                  action: () => setState(() {
                                    query.clear();
                                    current = null;
                                  }),
                                ),
                              ),
                            for (final (index, section) in sections.indexed)
                              _SectionView(
                                key: keys.putIfAbsent(
                                  section.id,
                                  GlobalKey.new,
                                ),
                                section: section,
                                first: index == 0,
                                flash: section.id == flashing ? flashes : null,
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
        CallbackShortcuts(
          // Esc clears the search before it leaves the field.
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (query.text.isEmpty) {
                FocusScope.of(context).unfocus();
              } else {
                query.clear();
                onQuery();
              }
            },
          },
          child: TextField(
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
        ),
        const SizedBox(height: Gap.md),
        Expanded(
          child: ListView(
            children: [
              // The highlight follows the page as it scrolls through the
              // sections.
              MotionSelection<String>(
                selected: selected,
                highlight: sidebarHighlight(context),
                builder: (context, keyOf) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final section in sections)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.xs),
                        child: SidebarTile(
                          key: keyOf(section.id),
                          label: section.title,
                          icon: section.icon,
                          selected: section.id == selected,
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
  const _SectionView({
    super.key,
    required this.section,
    required this.first,
    this.flash,
  });
  final SettingsSection section;
  final bool first;

  /// Changes each time a contents click lands here, washing the first card.
  final int? flash;

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
              Icon(
                section.icon,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
          _JumpFlash(
            flash: index == 0 ? flash : null,
            child: MelonPanel(
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
          ),
        ],
      ],
    );
  }
}

/// Washes its card in the primary colour, fading out, each time [flash]
/// changes to a new value.
class _JumpFlash extends StatefulWidget {
  const _JumpFlash({required this.flash, required this.child});
  final int? flash;
  final Widget child;

  @override
  State<_JumpFlash> createState() => _JumpFlashState();
}

class _JumpFlashState extends State<_JumpFlash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);

  @override
  void didUpdateWidget(_JumpFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flash == null || widget.flash == oldWidget.flash) return;
    _controller.duration = motionDuration(context, 700);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          color: primary.withValues(
            alpha: .16 * (1 - Curves.easeOut.transform(_controller.value)),
          ),
          borderRadius: panelBorderRadius,
        ),
        child: child,
      ),
    );
  }
}

/// The search text, for rows to mark where it matches their labels.
class _SearchQuery extends InheritedWidget {
  const _SearchQuery({required this.text, required super.child});
  final String text;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SearchQuery>()?.text ?? '';

  @override
  bool updateShouldNotify(_SearchQuery oldWidget) => text != oldWidget.text;
}

/// [text] with each match of the search marked; a row found by one of its
/// other keywords marks nothing.
Widget _marked(BuildContext context, String text, TextStyle? style) {
  final query = _SearchQuery.of(context).toLowerCase();
  final lower = text.toLowerCase();
  if (query.isEmpty || !lower.contains(query)) return Text(text, style: style);
  final mark = BoxDecoration(
    color: Theme.of(context).colorScheme.primary.withValues(alpha: .2),
    borderRadius: const BorderRadius.all(Radius.circular(3)),
  );
  final spans = <InlineSpan>[];
  var start = 0;
  for (
    var at = lower.indexOf(query);
    at >= 0;
    at = lower.indexOf(query, start)
  ) {
    if (at > start) spans.add(TextSpan(text: text.substring(start, at)));
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: DecoratedBox(
          decoration: mark,
          child: Text(text.substring(at, at + query.length), style: style),
        ),
      ),
    );
    start = at + query.length;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return Text.rich(TextSpan(children: spans), style: style);
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
    this.toggled,
  });
  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  final Color? subtitleColor;

  /// A longer explanation behind a ? mark beside the title.
  final String? help;

  /// Set when the row is a switch: the row takes the keyboard focus and
  /// reads as one switch in this state, [trailing] only shows it and [help]
  /// is read as the hint.
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final switches = toggled != null;
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: _marked(
                context,
                title,
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            if (help != null) ...[
              const SizedBox(width: Gap.xs),
              ExcludeSemantics(
                excluding: switches,
                child: HelpHint(message: help!),
              ),
            ],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          _marked(
            context,
            subtitle!,
            Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: subtitleColor),
          ),
        ],
      ],
    );
    final trailing = switch (this.trailing) {
      final control? when switches => ExcludeSemantics(
        child: ExcludeFocus(child: control),
      ),
      final control => control,
    };
    final row = InkWell(
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
                  trailing,
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
                  trailing,
                ],
              ],
            );
          },
        ),
      ),
    );
    return switches
        ? MergeSemantics(
            child: Semantics(toggled: toggled, hint: help, child: row),
          )
        : row;
  }
}

/// A [SettingRow] that toggles [value]; tapping the row flips it too. The
/// row is the one keyboard stop and reads as one switch.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.help,
  });
  final String title;
  final String? subtitle, help;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    title: title,
    subtitle: subtitle,
    help: help,
    toggled: value,
    onTap: () => onChanged(!value),
    trailing: Switch(value: value, onChanged: onChanged),
  );
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
