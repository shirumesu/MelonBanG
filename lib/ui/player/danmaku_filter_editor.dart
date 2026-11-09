import 'package:flutter/material.dart';

import '../../features/danmaku/danmaku_preferences.dart';
import '../core/theme.dart';

/// The danmaku block rules: each can be switched off or removed, and new
/// ones are keywords or /regular expressions/.
class DanmakuFilterEditor extends StatefulWidget {
  const DanmakuFilterEditor({
    super.key,
    required this.preferences,
    this.heading = true,
  });
  final DanmakuPreferences preferences;

  /// Whether it names itself; off under a group that already does.
  final bool heading;
  @override
  State<DanmakuFilterEditor> createState() => _DanmakuFilterEditorState();
}

class _DanmakuFilterEditorState extends State<DanmakuFilterEditor> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void add() {
    if (input.text.trim().isEmpty) return;
    widget.preferences.addFilter(input.text);
    input.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.preferences,
    builder: (context, _) {
      final prefs = widget.preferences;
      final scheme = Theme.of(context).colorScheme;
      final small = Theme.of(context).textTheme.bodySmall;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.heading) ...[
            Text('屏蔽', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Gap.sm),
          ],
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
              ListenableBuilder(
                listenable: input,
                builder: (context, _) => TextButton(
                  onPressed: input.text.trim().isEmpty ? null : add,
                  child: const Text('添加'),
                ),
              ),
            ],
          ),
          if (prefs.filters.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.md),
              child: Text('还没有屏蔽规则', style: small),
            ),
          for (final (index, rule) in prefs.filters.indexed)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rule.isRegex ? '/${rule.pattern}/' : rule.pattern,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
      );
    },
  );
}
