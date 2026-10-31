import 'dart:math';

import 'package:pinyin/pinyin.dart';

import '../../domain/catalog.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';

/// Simplified, width-folded title without punctuation, plus its season.
(String, int) normalizeSourceTitle(String input) {
  final (title, season) = _normalize(input);
  return (title, season ?? 1);
}

/// [normalizeSourceTitle] with the season only when the title states one.
(String, int?) _normalize(String input) {
  var title = simplifiedChinese(
    String.fromCharCodes(
      input.runes.map(
        (c) => c == 0x3000
            ? 32
            : c >= 0xff01 && c <= 0xff5e
            ? c - 0xfee0
            : c,
      ),
    ),
  ).toLowerCase();
  final season = RegExp(
    r'第\s*([一二三四五六七八九十\d]+)\s*[季期]|season\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(title);
  if (season != null) title = title.replaceRange(season.start, season.end, '');
  final raw = season?[1] ?? season?[2];
  return (
    title.replaceAll(RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff]'), ''),
    raw == null
        ? null
        : int.tryParse(raw) ??
              {
                '一': 1,
                '二': 2,
                '三': 3,
                '四': 4,
                '五': 5,
                '六': 6,
                '七': 7,
                '八': 8,
                '九': 9,
                '十': 10,
              }[raw] ??
              1,
  );
}

/// Dice similarity of the best catalogue name, penalizing season mismatch and
/// adjusted by year and episode count. Calibrated thresholds: .84 automatic,
/// .55 possible match.
double sourceMatchScore(
  Subject subject,
  SourceSubject site,
  Iterable<String> names,
) {
  final target = normalizeSourceTitle(site.title);
  var best = 0.0;
  for (final name in names) {
    final expected = normalizeSourceTitle(name);
    double dice(String a, String b) {
      if (a == b) return 1;
      if (a.length < 2 || b.length < 2) return 0;
      final left = <String>{
        for (var i = 0; i < a.length - 1; i++) a.substring(i, i + 2),
      };
      final right = <String>{
        for (var i = 0; i < b.length - 1; i++) b.substring(i, i + 2),
      };
      return 2 * left.intersection(right).length / (left.length + right.length);
    }

    final score =
        dice(expected.$1, target.$1) - (expected.$2 != target.$2 ? .4 : 0);
    if (score > best) best = score;
  }
  final year = int.tryParse((subject.airDate ?? '').split('-').first);
  if (year != null && site.year != null) {
    best += year == site.year ? .03 : -.12;
  }
  final count = site.episodeTotal;
  if (count != null && (count - (subject.episodeTotal ?? 0)).abs() <= 2) {
    best += .02;
  }
  return best.clamp(0, 1);
}

bool sourceEpisodeMatches(String label, Episode episode) {
  final normalized = simplifiedChinese(label).toUpperCase();
  final special = RegExp(r'SP|OVA|OAD|特别').hasMatch(normalized);
  // A special is named as one, though an interlude may be named by its
  // number (11.5).
  if (special ? episode.main : episode.numberedApart) return false;
  final match = RegExp(r'(?:第|EP\s*|SP\s*|OVA\s*|OAD\s*)?(\d+(?:\.\d+)?)')
      .firstMatch(normalized);
  return match != null && double.tryParse(match[1]!) == episode.sort;
}

/// The season the subject's titles state, if any.
int? _subjectSeason(Subject subject) => [
  subject.title,
  ?subject.name,
  ?subject.nameCn,
].map(resourceSeason).nonNulls.firstOrNull;

/// The episode of [subject] a single-episode release holds. Releases of a
/// sequel number it within the season (`第三季 - 03`) or across seasons
/// (`[51]`, `03(51)`); a release without a season counts across seasons
/// there, since it is more likely an earlier season's. A release naming
/// another season holds none.
Episode? releaseEpisode(Subject subject, ResourceTitleInfo info) {
  final number = info.episode;
  if (number == null) return null;
  final episodes = subject.episodes.where((e) => !e.numberedApart);
  final sequel = episodes.any(
    (e) => e.absolute != null && e.absolute != e.sort,
  );
  final season = _subjectSeason(subject) ?? (sequel ? null : 1);
  if (info.season != null && season != null && info.season != season) {
    return null;
  }
  final across = info.absoluteEpisode ?? number;
  if (sequel) {
    final match = episodes.where((e) => e.absolute == across).firstOrNull;
    if (match != null || info.season == null) return match;
  }
  return episodes.where((e) => e.sort == number).firstOrNull;
}

/// The videos of [task], a download of [subject], by the episode each
/// holds: its own episode for a single video cached for one, otherwise the
/// number a video's name gives (`S02E03`, `[03]`, ` - 03(51)`), within the
/// season or across seasons. The task already belongs to the subject, so the
/// season a name states is checked only against one the subject's title
/// states. Episodes that several videos claim are left out.
Map<int, DownloadFile> episodeFiles(Subject subject, DownloadTask task) {
  final videos = task.videos;
  if (task.episodeId case final id? when videos.length == 1) {
    return {id: videos.single};
  }
  final episodes = subject.episodes.where((e) => !e.numberedApart);
  final season = _subjectSeason(subject);
  final found = <int, DownloadFile>{}, claimed = <int>{};
  for (final file in videos) {
    final info = describeResource(file.name);
    final number = info.episode;
    if (number == null ||
        (info.season != null && season != null && info.season != season)) {
      continue;
    }
    final across = info.absoluteEpisode ?? number;
    final episode =
        episodes
            .where(
              (e) =>
                  e.absolute != null &&
                  e.absolute != e.sort &&
                  e.absolute == across,
            )
            .firstOrNull ??
        episodes.where((e) => e.sort == number).firstOrNull;
    if (episode == null) continue;
    if (!claimed.add(episode.id)) {
      found.remove(episode.id);
    } else {
      found[episode.id] = file;
    }
  }
  return found;
}

/// Whether a release may hold [episode]: a single-episode release must be
/// it, a batch must span it within or across seasons, and a special needs a
/// special. Titles stating no episode may hold any.
bool releaseMayHold(Subject subject, Episode episode, ResourceTitleInfo info) {
  if (info.episode != null) {
    return releaseEpisode(subject, info)?.id == episode.id;
  }
  final label = info.episodeLabel;
  if (label == null || label == '剧场版') return true;
  if (label.startsWith('特别篇')) return !episode.main;
  final range = RegExp(r'^(\d+)–(\d+)').firstMatch(label)!;
  bool within(double? number) =>
      number != null &&
      number >= int.parse(range[1]!) &&
      number <= int.parse(range[2]!);
  return within(episode.sort) || within(episode.absolute);
}

/// Whether a site subject a search found may hold [subject]'s episodes: one
/// looked up by an identifier the user entered, an upload passing
/// [uploadMatches], or a season scoring at least a possible match.
bool siteMatches(
  Subject subject,
  Episode? episode,
  SourceSubject site,
  Iterable<String> names,
) =>
    site.direct ||
    (site.choosePart
        ? uploadMatches(subject, episode, site, names)
        : sourceMatchScore(subject, site, names) >= .55);

/// Openings/endings, soundtracks and songs, audio tracks, recaps, tutorials and
/// merchandise reuse a title without holding an episode.
final _notEpisode = RegExp(
  r'NCOP|NCED|OST|原声|主题曲|片头曲|片尾曲|歌曲|音乐集|音轨|看完|解说|盘点|混剪|预告|教程|攻略|手办',
  caseSensitive: false,
);

/// Whether an upload can hold the subject's episodes. Its title or tags must
/// name the subject, tolerating the variant spellings uploaders use against
/// takedowns: inserted punctuation, homophones and, for longer names, a wrong
/// character. It must not state another season, must be about as long as an
/// episode, and must not predate the subject's broadcast.
bool uploadMatches(
  Subject subject,
  Episode? episode,
  SourceSubject upload,
  Iterable<String> names,
) {
  if (_notEpisode.hasMatch(upload.title)) return false;
  final aired = DateTime.tryParse(subject.airDate ?? '');
  final published = upload.publishedAt;
  if (aired != null &&
      published != null &&
      published.isBefore(aired.subtract(const Duration(days: 1)))) {
    return false;
  }
  final length = episodeLength(subject, episode);
  final duration = upload.durationSeconds;
  if (duration != null && duration < (length ?? 240) * 3 ~/ 4) return false;
  final stated = _normalize(upload.title).$2;
  final text = _sounds(_normalize([upload.title, ...upload.tags].join(' ')).$1);
  return names.any((name) {
    final (expected, season) = normalizeSourceTitle(name);
    if (expected.isEmpty || (stated != null && stated != season)) {
      return false;
    }
    final allowed = expected.length >= 10
        ? 2
        : expected.length >= 5
        ? 1
        : 0;
    return _closestDistance(_sounds(expected), text) <= allowed;
  });
}

/// [episode]'s length in seconds, else the subject's first known one.
int? episodeLength(Subject subject, Episode? episode) =>
    episode?.durationSeconds ??
    subject.episodes.map((e) => e.durationSeconds).nonNulls.firstOrNull;

/// How an upload's title places [episode]: 0 when it names the episode or a
/// range holding it (`第3集`, `EP03`, `1-12`, `全12集`), 2 when it names only
/// other episodes, 1 when it names none, as fan works seldom do.
int uploadNamesEpisode(String title, Episode episode) {
  final text = simplifiedChinese(title).toUpperCase();
  final number = episode.sort;
  var other = false;
  for (final match in RegExp(
    r'(\d{1,3})\s*[-–~～至到]\s*(\d{1,3})\s*(?:[集话\]】)）])',
  ).allMatches(text)) {
    if (number >= int.parse(match[1]!) && number <= int.parse(match[2]!)) {
      return 0;
    }
    other = true;
  }
  for (final match in RegExp(r'全\s*(\d{1,3})\s*[集话]').allMatches(text)) {
    if (number <= int.parse(match[1]!)) return 0;
    other = true;
  }
  for (final match in RegExp(
    r'第\s*(\d{1,3})\s*[集话]|(?<![A-Z])EP\s*(\d{1,3})(?!\d)',
  ).allMatches(text)) {
    if (double.parse(match[1] ?? match[2]!) == number) return 0;
    other = true;
  }
  return other ? 2 : 1;
}

/// Each character with its toneless readings, so homophones compare equal.
List<Set<String>> _sounds(String normalized) => [
  for (final c in normalized.runes.map(String.fromCharCode))
    {c, ...PinyinHelper.convertToPinyinArray(c, PinyinFormat.WITHOUT_TONE)},
];

/// Fewest edits turning [pattern] into some part of [text].
int _closestDistance(List<Set<String>> pattern, List<Set<String>> text) {
  var previous = List.filled(text.length + 1, 0);
  for (var i = 1; i <= pattern.length; i++) {
    final current = List.filled(text.length + 1, i);
    for (var j = 1; j <= text.length; j++) {
      final same = pattern[i - 1].intersection(text[j - 1]).isNotEmpty;
      current[j] = min(
        previous[j - 1] + (same ? 0 : 1),
        min(previous[j], current[j - 1]) + 1,
      );
    }
    previous = current;
  }
  return previous.reduce(min);
}
