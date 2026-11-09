import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pinyin/pinyin.dart' show ChineseHelper;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/json.dart';
import '../../domain/danmaku.dart';

class DanmakuFilter {
  DanmakuFilter(this.pattern, {this.isRegex = false, this.enabled = true})
    : _lowered = pattern.toLowerCase() {
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
  final String _lowered;
  RegExp? expression;
  bool invalid = false;
  bool matches(String text) => _matches(text, text.toLowerCase());

  /// [matches] with [lowered], the text in lower case, worked out once for
  /// every rule.
  bool _matches(String text, String lowered) =>
      enabled &&
      !invalid &&
      (isRegex ? expression!.hasMatch(text) : lowered.contains(_lowered));
  Json toJson() => {'pattern': pattern, 'isRegex': isRegex, 'enabled': enabled};
}

class DanmakuPreferences extends ChangeNotifier {
  DanmakuPreferences(this.storage) {
    final saved = object(
      jsonDecode(storage.getString('danmaku-preferences') ?? '{}'),
    );
    _readDisplay(saved);
    sendStyle.value = (
      mode:
          DanmakuMode.values.asNameMap()[saved['sendMode']] ??
          DanmakuMode.scroll,
      color: number(saved['sendColor'] ?? 0xffffff).toInt() & 0xffffff,
    );
    providers = object(saved['providers'])
        .map((key, value) => MapEntry(key, value == true));
    filters = objects(jsonDecode(storage.getString('danmaku-filters') ?? '[]'))
        .map(
          (rule) => DanmakuFilter(
            '${rule['pattern'] ?? ''}',
            isRegex: rule['isRegex'] == true,
            enabled: rule['enabled'] != false,
          ),
        )
        .where((rule) => rule.pattern.isNotEmpty)
        .toList();
    sendStyle.addListener(_save);
  }
  final SharedPreferences storage;
  late bool enabled, scroll, top, bottom, colorful, stroke, merge;
  late bool overlap, shield;
  late double size, opacity, area;
  late int density, speed;

  /// Comments shown per episode at most, 0 for all: thousands crowding the
  /// screen and the layout add little.
  late int limit;

  /// The limits offered, the last showing all.
  static const limits = [
    1000,
    2000,
    3000,
    4000,
    5000,
    6000,
    8000,
    10000,
    15000,
    20000,
    0,
  ];

  /// Reads the display preferences from [saved], the defaults where missing.
  void _readDisplay(Json saved) {
    enabled = saved['enabled'] as bool? ?? true;
    size = number(saved['size'] ?? 25).clamp(14, 36).toDouble();
    opacity = number(saved['opacity'] ?? .35).clamp(.1, 1).toDouble();
    area = number(saved['area'] ?? 1).clamp(.2, 1).toDouble();
    density = number(saved['density'] ?? 3).toInt().clamp(0, 3);
    speed = number(saved['speed'] ?? 2).toInt().clamp(0, 4);
    limit = switch (saved['limit']) {
      final int value when limits.contains(value) => value,
      _ => 6000,
    };
    overlap = saved['overlap'] as bool? ?? false;
    shield = saved['shield'] as bool? ?? false;
    scroll = saved['scroll'] as bool? ?? true;
    top = saved['top'] as bool? ?? true;
    bottom = saved['bottom'] as bool? ?? true;
    colorful = saved['colorful'] as bool? ?? true;
    stroke = saved['stroke'] as bool? ?? true;
    merge = saved['merge'] as bool? ?? true;
  }

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

  /// Everything [visible] and the shown switch depend on; equal while only
  /// the look of comments changes.
  Object get shownBy => (
    enabled,
    scroll,
    top,
    bottom,
    colorful,
    merge,
    limit,
    [
      for (final rule in filters)
        '${rule.enabled ? 1 : 0}${rule.isRegex ? 1 : 0}${rule.pattern}',
    ].join('\u0000'),
  );
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
        'limit': limit,
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

  void setProvider(String provider, bool value) =>
      update(() => providers[provider] = value);
  void addFilter(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    final regex = text.length > 2 && text.startsWith('/') && text.endsWith('/');
    final pattern = regex ? text.substring(1, text.length - 1) : text;
    // Adding a rule again switches it back on rather than listing it twice.
    final index = filters.indexWhere(
      (rule) => rule.pattern == pattern && rule.isRegex == regex,
    );
    update(() {
      if (index < 0) {
        filters.add(DanmakuFilter(pattern, isRegex: regex));
      } else {
        filters[index] = DanmakuFilter(pattern, isRegex: regex);
      }
    });
  }

  /// Comments that pass mode/colour/filter rules, in time order, and how
  /// many [limit] left out. With [merge], a comment repeating one shown in
  /// the last [mergeWindow] seconds, from any source, is folded into it and
  /// counted as `×N`.
  ({List<DanmakuComment> shown, int thinned}) visible(
    List<DanmakuComment> comments,
  ) {
    final result = <DanmakuComment>[];
    // Normalized text → index in result of its latest shown comment.
    final shown = <String, int>{};
    final counts = <int, int>{};
    // Index in result → the text its merged group shows instead.
    final texts = <int, String>{};
    final rules = [
      for (final rule in filters)
        if (rule.enabled && !rule.invalid) rule,
    ];
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
      if (rules.isNotEmpty) {
        final lowered = item.text.toLowerCase();
        if (rules.any((rule) => rule._matches(item.text, lowered))) continue;
      }
      if (merge) {
        final key = _mergeKeys[item] ??= _mergeKey(item.text);
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
    return _thin(result);
  }

  /// [comments] down to [limit], taken evenly through the episode so busy
  /// scenes stay busier than quiet ones; the viewer's own are always kept.
  ({List<DanmakuComment> shown, int thinned}) _thin(
    List<DanmakuComment> comments,
  ) {
    final others = comments.where((item) => !item.own).length;
    if (limit == 0 || others <= limit) return (shown: comments, thinned: 0);
    final shown = <DanmakuComment>[];
    var seen = 0;
    for (final item in comments) {
      if (item.own) {
        shown.add(item);
        continue;
      }
      // Keeps the comment that starts each of [limit] equal shares.
      if (seen * limit ~/ others != (seen + 1) * limit ~/ others) {
        shown.add(item);
      }
      seen++;
    }
    return (shown: shown, thinned: others - limit);
  }

  static const mergeWindow = 10.0;

  /// Each comment's [_mergeKey], kept while the comment lives: the shown
  /// comments are worked out again on every source loaded and rule changed.
  static final _mergeKeys = Expando<String>();
  static final _trailingPunctuation = RegExp(r'[!?.,~。！？，、…～]+$');

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
    final trimmed = key.replaceFirst(_trailingPunctuation, '');
    return trimmed.isEmpty ? key : trimmed;
  }

  static bool _traditional(String text) => text.runes.any((rune) {
    final char = String.fromCharCode(rune);
    return ChineseHelper.convertCharToSimplifiedChinese(char) != char;
  });
}

/// A per-episode limit as shown: `6000`, or `不限`.
String danmakuLimitLabel(int limit) => limit == 0 ? '不限' : '$limit';
