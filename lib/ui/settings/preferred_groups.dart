import 'package:flutter/material.dart';

import '../../features/playback/playback_preferences.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'settings_page.dart';

/// The preferred release groups as numbered tags, dragged into order, and a
/// field adding more: groups resource searches found, or any typed name.
class PreferredGroupsSetting extends StatefulWidget {
  const PreferredGroupsSetting({
    super.key,
    required this.prefs,
    required this.cachedGroups,
  });
  final PlaybackPreferences prefs;

  /// Groups credited on cache tasks.
  final Iterable<String> Function() cachedGroups;

  @override
  State<PreferredGroupsSetting> createState() => _PreferredGroupsSettingState();
}

class _PreferredGroupsSettingState extends State<PreferredGroupsSetting> {
  /// The order while a tag is dragged; saved when it is dropped.
  List<String>? dragging;

  List<String> get groups => dragging ?? widget.prefs.preferredGroups;

  void save(List<String> value) => widget.prefs.setPreferredGroups(value);

  void add(String name) {
    final value = name.trim();
    if (value.isEmpty ||
        groups.any((e) => e.toLowerCase() == value.toLowerCase())) {
      return;
    }
    save([...groups, value]);
  }

  /// Seen groups not yet preferred, with how often they were found and
  /// whether a cache task credits them, the most found first.
  List<(String, int, bool)> suggestions() {
    final seen = widget.prefs.seenGroups;
    final cached = widget.cachedGroups().toSet();
    final taken = {for (final name in groups) name.toLowerCase()};
    return [
      for (final name in {...seen.keys, ...cached})
        if (!taken.contains(name.toLowerCase()))
          (name, seen[name] ?? 0, cached.contains(name)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.prefs,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingRow(
          title: '字幕组偏好',
          subtitle: '越靠前越优先；BT 和 PikPak 资源里这些字幕组的发布排在前面并优先推荐。拖动调整顺序',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (index, name) in groups.indexed) _tag(index, name),
              _AddGroup(suggestions: suggestions, onAdd: add),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _tag(int index, String name) {
    final tag = _GroupTag(
      index: index,
      name: name,
      onRemove: () => save([...groups]..remove(name)),
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final order = [...groups];
        final from = order.indexOf(details.data);
        if (from >= 0 && from != index) {
          order.insert(index, order.removeAt(from));
          setState(() => dragging = order);
        }
        return true;
      },
      builder: (context, _, _) => Draggable<String>(
        data: name,
        onDragStarted: () => setState(() => dragging = [...groups]),
        onDragEnd: (_) {
          final order = dragging;
          setState(() => dragging = null);
          if (order != null) save(order);
        },
        feedback: Material(
          type: MaterialType.transparency,
          child: Opacity(opacity: .9, child: tag),
        ),
        childWhenDragging: Opacity(opacity: .35, child: tag),
        child: MouseRegion(cursor: SystemMouseCursors.grab, child: tag),
      ),
    );
  }
}

class _GroupTag extends StatelessWidget {
  const _GroupTag({
    required this.index,
    required this.name,
    required this.onRemove,
  });
  final int index;
  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: controlBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.drag_indicator_rounded,
            size: 16,
            color: scheme.onPrimaryContainer.withValues(alpha: .6),
          ),
          const SizedBox(width: 4),
          Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(fontSize: 13, color: scheme.onPrimaryContainer),
          ),
          IconButton(
            tooltip: '移除',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            iconSize: 14,
            color: scheme.onPrimaryContainer.withValues(alpha: .7),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
        ],
      ),
    );
  }
}

/// A field suggesting seen groups as its text is typed; a name no
/// suggestion holds is added as typed.
class _AddGroup extends StatefulWidget {
  const _AddGroup({required this.suggestions, required this.onAdd});
  final List<(String, int, bool)> Function() suggestions;
  final ValueChanged<String> onAdd;

  @override
  State<_AddGroup> createState() => _AddGroupState();
}

class _AddGroupState extends State<_AddGroup> {
  final input = TextEditingController();
  final focus = FocusNode();

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  void add(String name) {
    widget.onAdd(name);
    input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    return SizedBox(
      width: 220,
      child: RawAutocomplete<(String, int, bool)>(
        textEditingController: input,
        focusNode: focus,
        displayStringForOption: (option) => option.$1,
        optionsBuilder: (value) {
          final text = value.text.trim();
          final query = text.toLowerCase();
          final found = widget
              .suggestions()
              .where((e) => e.$1.toLowerCase().contains(query))
              .take(8)
              .toList();
          return [
            ...found,
            if (text.isNotEmpty &&
                !found.any((e) => e.$1.toLowerCase() == query))
              (text, -1, false),
          ];
        },
        onSelected: (option) => add(option.$1),
        fieldViewBuilder: (context, controller, focus, submit) => TextField(
          controller: controller,
          focusNode: focus,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            hintText: '添加字幕组',
            prefixIcon: Icon(Icons.add_rounded, size: 18),
            prefixIconConstraints: BoxConstraints(minWidth: 36),
          ),
          onSubmitted: add,
        ),
        optionsViewBuilder: (context, select, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: menuSurface(context),
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: .2),
            borderRadius: controlBorderRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300, maxHeight: 340),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(6),
                children: [
                  if (options.any((e) => e.$2 >= 0))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                      child: Text(
                        '搜到过的字幕组',
                        style: small?.copyWith(fontSize: 11),
                      ),
                    ),
                  for (final (index, option) in options.indexed)
                    Builder(
                      builder: (context) {
                        final highlighted =
                            AutocompleteHighlightedOption.of(context) == index;
                        final (name, count, cached) = option;
                        return InkWell(
                          borderRadius: badgeBorderRadius,
                          onTap: () => select(option),
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: highlighted
                                  ? scheme.primary.withValues(alpha: .08)
                                  : null,
                              borderRadius: badgeBorderRadius,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    count < 0 ? '添加“$name”' : name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: count < 0 ? scheme.primary : null,
                                    ),
                                  ),
                                ),
                                if (count >= 0)
                                  Text(
                                    [
                                      if (count > 0) '$count 条',
                                      if (cached) '缓存过',
                                    ].join(' · '),
                                    style: small?.copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
