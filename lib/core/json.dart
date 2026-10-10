import 'dart:convert';
import 'dart:math';

import '../domain/catalog.dart';

typedef Json = Map<String, dynamic>;
Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> objects(dynamic value) =>
    value is List ? value.map(object).toList() : [];
double number(dynamic value) => value is num ? value.toDouble() : 0;
String titleOf(Json value) =>
    [value['nameCn'], value['displayName'], value['name'], value['title']]
        .whereType<String>()
        .where((title) => title.trim().isNotEmpty)
        .firstOrNull ??
    '未命名';
String newId() => base64Url
    .encode(List.generate(18, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');

Json collectionMutationFields(Json mutation) => mutation['fields'] is Map
    ? object(mutation['fields'])
    : {
        if (mutation['status'] != null)
          'type': CollectionStatus.parse('${mutation['status']}').remoteValue,
        if (mutation['score'] != null) 'rate': mutation['score'],
      };

const collectionFieldNames = {
  'type': 'status',
  'rate': 'userScore',
  'tags': 'collectionTags',
  'comment': 'comment',
};

final _bangumiCover = RegExp(
  r'^https?://lain\.bgm\.tv/(?:r/\d+/)?pic/cover/[a-z]/(.+)$',
);

/// Bangumi covers resolve to one 400 px rendition, the size the catalogue
/// API serves, so every page shares a single cached image per subject.
String? coverAddress(Object? value) {
  if (value is! String) return null;
  final address = value.trim();
  final uri = Uri.tryParse(address);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    return null;
  }
  final cover = _bangumiCover.firstMatch(address);
  return cover == null
      ? address
      : 'https://lain.bgm.tv/r/400/pic/cover/l/${cover[1]}';
}
