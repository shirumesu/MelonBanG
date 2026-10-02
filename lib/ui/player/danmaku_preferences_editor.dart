import 'package:flutter/material.dart';

import '../core/selection_controls.dart';
import 'playback_preferences.dart';

class DanmakuPreferencesEditor extends StatefulWidget {
  const DanmakuPreferencesEditor({
    super.key,
    required this.preferences,
    this.display = true,
    this.filters = true,
    this.restore = true,
  });
  final DanmakuPreferences preferences;
  final bool display, filters, restore;
  @override
  State<DanmakuPreferencesEditor> createState() =>
      _DanmakuPreferencesEditorState();
}

class _DanmakuPreferencesEditorState extends State<DanmakuPreferencesEditor> {
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
      Widget toggle(String title, bool value, void Function(bool) change) =>
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(title),
            value: value,
            onChanged: (value) => prefs.update(() => change(value)),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.display) ...[
            Text('显示', style: Theme.of(context).textTheme.titleSmall),
            toggle('显示弹幕', prefs.enabled, (value) => prefs.enabled = value),
            Text('字号 ${prefs.size.round()}'),
            Slider(
              value: prefs.size,
              min: 14,
              max: 36,
              onChanged: (value) => prefs.update(() => prefs.size = value),
            ),
            Text('不透明度 ${(prefs.opacity * 100).round()}%'),
            Slider(
              value: prefs.opacity,
              min: .1,
              max: 1,
              onChanged: (value) => prefs.update(() => prefs.opacity = value),
            ),
            Text('显示区域 ${(prefs.area * 100).round()}%'),
            Slider(
              value: prefs.area,
              min: .2,
              max: 1,
              onChanged: (value) => prefs.update(() => prefs.area = value),
            ),
            const SizedBox(height: 8),
            MelonSegmentedControl<int>(
              value: prefs.density,
              options: const {0: '稀疏', 1: '正常', 2: '密集', 3: '全部'},
              onChanged: (value) => prefs.update(() => prefs.density = value),
            ),
            toggle('滚动弹幕', prefs.scroll, (value) => prefs.scroll = value),
            toggle('顶部弹幕', prefs.top, (value) => prefs.top = value),
            toggle('底部弹幕', prefs.bottom, (value) => prefs.bottom = value),
            toggle('彩色弹幕', prefs.colorful, (value) => prefs.colorful = value),
            toggle('描边', prefs.stroke, (value) => prefs.stroke = value),
          ],
          if (widget.filters) ...[
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
                      '${rule.isRegex ? '/${rule.pattern}/' : rule.pattern}${rule.invalid ? ' · 正则无效' : ''}',
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
              child: TextButton(
                onPressed: addRule,
                child: const Text('添加屏蔽规则'),
              ),
            ),
          ],
          if (widget.display && widget.restore)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: prefs.resetDisplay,
                child: const Text('恢复默认'),
              ),
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
