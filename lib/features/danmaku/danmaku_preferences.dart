import 'dart:convert';

import 'package:flutter/foundation.dart';
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
      scroll = saved['scroll'] as bool? ?? true;
      top = saved['top'] as bool? ?? true;
      bottom = saved['bottom'] as bool? ?? true;
      colorful = saved['colorful'] as bool? ?? true;
      stroke = saved['stroke'] as bool? ?? true;
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
  }
  final SharedPreferences storage;
  bool enabled = true,
      scroll = true,
      top = true,
      bottom = true,
      colorful = true,
      stroke = true;
  double size = 25, opacity = .9, area = .6;
  int density = 1;
  Map<String, bool> providers = {};
  List<DanmakuFilter> filters = [];
  bool sourceEnabled(String provider) => providers[provider] ?? true;
  void update(VoidCallback change) {
    change();
    storage.setString(
      'danmaku-preferences',
      jsonEncode({
        'enabled': enabled,
        'size': size,
        'opacity': opacity,
        'area': area,
        'density': density,
        'scroll': scroll,
        'top': top,
        'bottom': bottom,
        'colorful': colorful,
        'stroke': stroke,
        'providers': providers,
      }),
    );
    storage.setString(
      'danmaku-filters',
      jsonEncode(filters.map((rule) => rule.toJson()).toList()),
    );
    notifyListeners();
  }

  void resetDisplay() => update(() {
    enabled = scroll = top = bottom = colorful = stroke = true;
    size = 25;
    opacity = .9;
    area = .6;
    density = 1;
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

  /// Comments that pass mode/colour/filter rules, shifted by their source's
  /// offset and sorted by time.
  List<DanmakuComment> visible(
    List<DanmakuComment> comments,
    Map<String, double> offsets,
  ) {
    final result = <DanmakuComment>[];
    for (final item in comments) {
      if ((item.mode == DanmakuMode.scroll && !scroll) ||
          (item.mode == DanmakuMode.top && !top) ||
          (item.mode == DanmakuMode.bottom && !bottom)) {
        continue;
      }
      if (!colorful && item.color != 0xffffff) continue;
      if (filters.any((rule) => rule.matches(item.text))) continue;
      result.add(item.shifted(offsets[item.source] ?? 0));
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }
}
