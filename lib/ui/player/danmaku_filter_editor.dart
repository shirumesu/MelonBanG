import 'package:flutter/material.dart';

import '../../features/danmaku/danmaku_preferences.dart';

/// The danmaku block rules: each can be switched off or removed, and new
/// ones are keywords or /regular expressions/.
class DanmakuFilterEditor extends StatefulWidget {
  const DanmakuFilterEditor({super.key, required this.preferences});
  final DanmakuPreferences preferences;
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.preferences,
    builder: (context, _) {
      final prefs = widget.preferences;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text('屏蔽', style: Theme.of(context).textTheme.titleSmall),
          for (final (index, rule) in prefs.filters.indexed)
            Row(
              children: [
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
                Expanded(
                  child: Text(
                    '${rule.isRegex ? '/${rule.pattern}/' : rule.pattern}${rule.invalid ? '（正则无效）' : ''}',
                    style: TextStyle(
                      color: rule.invalid
                          ? Theme.of(context).colorScheme.error
                          : null,
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
          TextField(
            controller: input,
            decoration: const InputDecoration(hintText: '关键词，或 /正则表达式/'),
            onSubmitted: (_) => addRule(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: addRule, child: const Text('添加屏蔽规则')),
          ),
        ],
      );
    },
  );

  void addRule() {
    widget.preferences.addFilter(input.text);
    input.clear();
  }
}
