import 'dart:convert';
import 'dart:io';

import '../../core/json.dart';
import '../../domain/danmaku.dart';

/// A JSON array of `{timeSeconds, text, mode?, color?}` objects; the locator
/// is the file path.
class LocalDanmaku implements DanmakuProvider {
  const LocalDanmaku();

  @override
  String get id => 'local';
  @override
  String get label => '本地 JSON';

  @override
  Future<List<DanmakuComment>> load(String locator) async {
    final decoded = jsonDecode(await File(locator).readAsString());
    if (decoded is! List) {
      throw const FormatException('弹幕文件应为数组，包含 timeSeconds、text 和 mode。');
    }
    return sortedComments(
      objects(decoded)
          .where((item) => item['text'] is String)
          .map(
            (item) => DanmakuComment.parse(
              source: id,
              time: item['timeSeconds'],
              text: item['text'],
              mode: switch (item['mode'] ?? 'scroll') {
                'scroll' => DanmakuMode.scroll,
                'top' => DanmakuMode.top,
                'bottom' => DanmakuMode.bottom,
                _ => null,
              },
              color: hexColor(item['color']),
            ),
          ),
    );
  }
}
