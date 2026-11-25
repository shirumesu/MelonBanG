import 'package:flutter/material.dart';

import '../core/help_hint.dart';
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
    required List<SettingsGroup> this._groups,
  }) : _build = null,
       listenable = null;

  /// A section whose groups are built again when [listenable] changes, such
  /// as settings that show once what they set is ready.
  const SettingsSection.watching({
    required this.id,
    required this.title,
    required this.icon,
    required Listenable this.listenable,
    required List<SettingsGroup> Function() groups,
  }) : _groups = null,
       _build = groups;

  final String id, title;
  final IconData icon;
  final Listenable? listenable;
  final List<SettingsGroup>? _groups;
  final List<SettingsGroup> Function()? _build;

  List<SettingsGroup> get groups => _build?.call() ?? _groups!;
}

/// Rebuilds [builder] when [listenable] changes.
Widget watch(Listenable listenable, WidgetBuilder builder) => ListenableBuilder(
  listenable: listenable,
  builder: (context, _) => builder(context),
);

/// The search text, for rows to mark where it matches their labels.
class SettingsSearchQuery extends InheritedWidget {
  const SettingsSearchQuery({
    super.key,
    required this.text,
    required super.child,
  });
  final String text;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsSearchQuery>()?.text ??
      '';

  @override
  bool updateShouldNotify(SettingsSearchQuery oldWidget) =>
      text != oldWidget.text;
}

/// [text] with each match of the search marked; a row found by one of its
/// other keywords marks nothing.
Widget _marked(BuildContext context, String text, TextStyle? style) {
  final query = SettingsSearchQuery.of(context).toLowerCase();
  final lower = text.toLowerCase();
  if (query.isEmpty || !lower.contains(query)) return Text(text, style: style);
  final mark = BoxDecoration(
    color: Theme.of(context).colorScheme.primary.withValues(alpha: .2),
    borderRadius: tightBorderRadius,
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
/// end, or under the label when the row is narrower than 520.
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
                const TextStyle(
                  fontSize: FontSize.body,
                  fontWeight: FontWeight.w700,
                ),
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
          const SizedBox(height: Gap.xs),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: Gap.md),
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

/// A [SettingRow] that toggles [value]; tapping the row flips it too.
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
