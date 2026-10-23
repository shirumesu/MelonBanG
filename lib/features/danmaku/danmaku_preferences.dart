import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pinyin/pinyin.dart' show ChineseHelper;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/json.dart';
import '../../domain/danmaku.dart';

class DanmakuFilter {
  DanmakuFilter(this.pattern, {this.isRegex = false, this.enabled = true}) {
    if (isRegex) {
      try {
        expression = RegExp(pattern, caseSensitive: false);
      } on FormatException catch (_) {
        invalid = true;
      }
    }
  }
  final String pattern;
  final bool isRegex, enabled;
  RegExp? expression;
  bool invalid = false;
  bool matches(String text) =>
      enabled &&
      !invalid &&
      (isRegex
          ? expression!.hasMatch(text)
          : text.toLowerCase().contains(pattern.toLowerCase()));
  Json toJson() => {'pattern': pattern, 'isRegex': isRegex, 'enabled': enabled};
}

class DanmakuPreferences extends ChangeNotifier {
  DanmakuPreferences(this.storage) {
    try {
      final saved = object(
        jsonDecode(storage.getString('danmaku-preferences') ?? '{}'),
      );
      enabled = saved['enabled'] as bool? ?? true;
      size = number(saved['size'] ?? 25).clamp(14, 36).toDouble();
      opacity = number(saved['opacity'] ?? .9).clamp(.1, 1).toDouble();
      area = number(saved['area'] ?? .6).clamp(.2, 1).toDouble();
      density = number(saved['density'] ?? 1).toInt().clamp(0, 3);
      speed = number(saved['speed'] ?? 2).toInt().clamp(0, 4);
      overlap = saved['overlap'] as bool? ?? false;
      shield = saved['shield'] as bool? ?? false;
      scroll = saved['scroll'] as bool? ?? true;
      top = saved['top'] as bool? ?? true;
      bottom = saved['bottom'] as bool? ?? true;
      colorful = saved['colorful'] as bool? ?? true;
      stroke = saved['stroke'] as bool? ?? true;
      merge = saved['merge'] as bool? ?? true;
      sendStyle.value = (
        mode:
            DanmakuMode.values.asNameMap()[saved['sendMode']] ??
            DanmakuMode.scroll,
        color: number(saved['sendColor'] ?? 0xffffff).toInt() & 0xffffff,
      );
      providers = object(saved['providers'])
          .map((key, value) => MapEntry(key, value == true));
      filters =
          objects(jsonDecode(storage.getString('danmaku-filters') ?? '[]'))
              .map(
                (rule) => DanmakuFilter(
                  '${rule['pattern'] ?? ''}',
                  isRegex: rule['isRegex'] == true,
                  enabled: rule['enabled'] != false,
                ),
              )
              .where((rule) => rule.pattern.isNotEmpty)
              .toList();
    } on FormatException catch (_) {
      /* Keep defaults if old preferences are unreadable. */
    }
    sendStyle.addListener(_save);
  }
  final SharedPreferences storage;
  bool enabled = true,
      scroll = true,
      top = true,
      bottom = true,
      colorful = true,
      stroke = true,
      merge = true,
      overlap = false,
      shield = false;
  double size = 25, opacity = .9, area = .6;
  int density = 1, speed = 2;

  /// The look of comments sent from the player. It notifies on its own:
  /// the display preferences lay out the shown comments again on change.
  final sendStyle = ValueNotifier<({DanmakuMode mode, int color})>((
    mode: DanmakuMode.scroll,
    color: 0xffffff,
  ));

  /// Scroll speed multipliers from 极慢 to 极快, spanning Bilibili's 0.4–1.6.
  static const speeds = [.4, .7, 1.0, 1.3, 1.6];
  double get speedFactor => speeds[speed];
  Map<String, bool> providers = {};
  List<DanmakuFilter> filters = [];
  bool sourceEnabled(String provider) => providers[provider] ?? true;
  void update(VoidCallback change) {
    change();
    _save();
    notifyListeners();
  }

  void _save() {
    storage.setString(
      'danmaku-preferences',
      jsonEncode({
        'enabled': enabled,
        'size': size,
        'opacity': opacity,
        'area': area,
        'density': density,
        'speed': speed,
        'overlap': overlap,
        'shield': shield,
        'scroll': scroll,
        'top': top,
        'bottom': bottom,
        'colorful': colorful,
        'stroke': stroke,
        'merge': merge,
        'sendMode': sendStyle.value.mode.name,
        'sendColor': sendStyle.value.color,
        'providers': providers,
      }),
    );
    storage.setString(
      'danmaku-filters',
      jsonEncode(filters.map((rule) => rule.toJson()).toList()),
    );
  }

  void resetDisplay() => update(() {
    enabled = scroll = top = bottom = colorful = stroke = merge = true;
    overlap = shield = false;
    size = 25;
    opacity = .9;
    area = .6;
    density = 1;
    speed = 2;
  });
  void setProvider(String provider, bool value) =>
      update(() => providers[provider] = value);
  void addFilter(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    final regex = text.length > 2 && text.startsWith('/') && text.endsWith('/');
    update(
      () => filters.add(
        DanmakuFilter(
          regex ? text.substring(1, text.length - 1) : text,
          isRegex: regex,
        ),
      ),
    );
  }

  /// Comments that pass mode/colour/filter rules, in time order. With
  /// [merge], a comment repeating one shown in the last [mergeWindow]
  /// seconds, from any source, is folded into it and counted as `×N`.
  List<DanmakuComment> visible(List<DanmakuComment> comments) {
    final result = <DanmakuComment>[];
    // Normalized text → index in result of its latest shown comment.
    final shown = <String, int>{};
    final counts = <int, int>{};
    // Index in result → the text its merged group shows instead.
    final texts = <int, String>{};
    for (final item in comments) {
      if ((item.mode == DanmakuMode.scroll && !scroll) ||
          (item.mode == DanmakuMode.top && !top) ||
          (item.mode == DanmakuMode.bottom && !bottom)) {
        continue;
      }
      if (item.own) {
        result.add(item);
        continue;
      }
      if (!colorful && item.color != 0xffffff) continue;
      if (filters.any((rule) => rule.matches(item.text))) continue;
      if (merge) {
        final key = _mergeKey(item.text);
        final index = shown[key];
        if (index != null && item.time - result[index].time <= mergeWindow) {
          counts[index] = (counts[index] ?? 1) + 1;
          // Simplified and traditional spellings together show simplified.
          if (_traditional(texts[index] ?? result[index].text) &&
              !_traditional(item.text)) {
            texts[index] = item.text;
          }
          continue;
        }
        shown[key] = result.length;
      }
      result.add(item);
    }
    for (final MapEntry(key: index, value: count) in counts.entries) {
      final item = result[index];
      result[index] = DanmakuComment(
        item.time,
        '${texts[index] ?? item.text} ×$count',
        source: item.source,
        mode: item.mode,
        color: item.color,
      );
    }
    return result;
  }

  static const mergeWindow = 10.0;

  /// Text compared for merging: case, width, spacing, trailing punctuation
  /// and simplified/traditional spelling ignored.
  static String _mergeKey(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      // Full-width ASCII forms and the ideographic space.
      final folded = rune >= 0xff01 && rune <= 0xff5e
          ? rune - 0xfee0
          : rune == 0x3000
          ? 0x20
          : rune;
      if (folded == 0x20 || folded == 0x09) continue;
      buffer.write(
        ChineseHelper.convertCharToSimplifiedChinese(
          String.fromCharCode(folded),
        ),
      );
    }
    final key = buffer.toString().toLowerCase();
    final trimmed = key.replaceFirst(RegExp(r'[!?.,~。！？，、…～]+$'), '');
    return trimmed.isEmpty ? key : trimmed;
  }

  static bool _traditional(String text) => text.runes.any((rune) {
    final char = String.fromCharCode(rune);
    return ChineseHelper.convertCharToSimplifiedChinese(char) != char;
  });
}
