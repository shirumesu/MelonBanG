import 'resource_title.dart';

/// A group name compared across scripts, case and spacing.
String groupKey(String name) =>
    simplifiedChinese(name).toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// The groups a release credits: the site's, then the title's leading
/// bracket, since sites without group pages leave only that.
List<String> creditedGroups(ResourceTitleInfo info) =>
    {...info.groups, ?info.credit}.toList();

/// Whether a release crediting [credited] is by one of [wanted]. Names match
/// when one holds the other, so 银色子弹 finds 银色子弹字幕组; names of a
/// single character only match whole.
bool groupsMatch(Iterable<String> credited, Iterable<String> wanted) {
  final keys = [for (final name in wanted) groupKey(name)];
  for (final name in credited) {
    final key = groupKey(name);
    if (key.isEmpty) continue;
    for (final want in keys) {
      if (want.isEmpty) continue;
      if (key == want) return true;
      final shorter = key.length < want.length ? key : want;
      if (shorter.length >= 2 && (key.contains(want) || want.contains(key))) {
        return true;
      }
    }
  }
  return false;
}

final _rebroadcast = RegExp(r'重映|重播|补档|再放送|数码重制');
final _revision = RegExp(
  r'(?:(?<![a-z0-9])|(?<=\d))v([2-9])(?![a-z0-9])',
  caseSensitive: false,
);

/// Whether [title] is a rebroadcast of an earlier episode, such as
/// 数码重映第689集, whose number is not the week's.
bool releaseRebroadcast(String title) =>
    _rebroadcast.hasMatch(simplifiedChinese(title));

/// Whether [title] is a corrected release of an episode: `v2`, `03v2`.
bool releaseRevision(String title) => _revision.hasMatch(title);
