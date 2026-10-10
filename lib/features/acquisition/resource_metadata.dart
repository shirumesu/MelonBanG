import 'package:pinyin/pinyin.dart';

import '../../domain/catalog.dart';

String resourceEpisodeKeyword(Episode? episode) {
  if (episode == null) return '';
  final sort = episode.sort;
  return sort == sort.roundToDouble()
      ? sort.toInt().toString().padLeft(2, '0')
      : sort.toString();
}

/// Resource names are catalogue aliases, never guessed from a release title.
List<String> resourceNames(Subject subject) {
  final values = <String>[
    subject.title,
    ?subject.name,
    ?subject.nameCn,
    ?subject.displayName,
    ...subject.aliases,
  ];
  final seen = <String>{};
  return values
      .where((value) {
        final key = ChineseHelper.convertToSimplifiedChinese(value.trim())
            .toLowerCase();
        return key.isNotEmpty && value != '未命名' && seen.add(key);
      })
      .map((value) => value.trim())
      .toList();
}

/// What a resource search sends to the sources: the main keyword, catalogue
/// aliases searched with it and the free-text episode term for torrents.
class ResourceTerms {
  const ResourceTerms({
    required this.keyword,
    this.names = const [],
    this.episodeKeyword = '',
  });

  /// The catalogue title with every alias and the chapter's padded number.
  ResourceTerms.of(Subject subject, Episode? episode)
    : keyword = subject.title,
      names = resourceNames(subject),
      episodeKeyword = resourceEpisodeKeyword(episode);

  final String keyword, episodeKeyword;
  final List<String> names;

  /// Distinct non-empty names, keyword first.
  List<String> get searchNames => {
    keyword.trim(),
    ...names.map((e) => e.trim()),
  }.where((e) => e.isNotEmpty).toList();
}
