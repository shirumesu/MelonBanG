import 'dart:convert';
import 'dart:math';

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

enum CollectionStatus {
  wish(1),
  completed(2),
  watching(3),
  onHold(4),
  dropped(5);

  const CollectionStatus(this.remoteValue);
  final int remoteValue;
  String get key => this == onHold ? 'on_hold' : name;
  static CollectionStatus parse(String key) =>
      values.firstWhere((v) => v.key == key);
  static CollectionStatus fromRemote(int value) =>
      values.firstWhere((v) => v.remoteValue == value);
}

enum EpisodeStatus {
  unwatched(0),
  wish(1),
  watched(2),
  dropped(3);

  const EpisodeStatus(this.remoteValue);
  final int remoteValue;
  String get key => this == wish ? 'queue' : name;
  static EpisodeStatus parse(String key) =>
      values.firstWhere((v) => v.key == key);
}
