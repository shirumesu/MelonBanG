import 'dart:math';

import 'package:pinyin/pinyin.dart';

import '../../domain/catalog.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';

/// Simplified, width-folded title without punctuation, plus its season.
(String, int) normalizeSourceTitle(String input) {
  final (title, season) = _normalize(input, ending: true);
  return (title, season ?? 1);
}

/// [normalizeSourceTitle] with the season only when the title states one:
/// 第2季, 第3期, Season 2, 2nd Season or S2. With [ending], a catalogue name
/// may also state it by a final number or Roman numeral (`边缘行者 2`,
/// `転生したら剣でしたII`); a site's titles end with episode numbers, so
/// theirs are not read that way.
(String, int?) _normalize(String input, {bool ending = false}) {
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
  final season =
      _statedSeason.firstMatch(title) ??
      (ending ? _endingSeason.firstMatch(title) : null);
  if (season != null) title = title.replaceRange(season.start, season.end, '');
  final raw = season
      ?.groups([for (var i = 1; i <= season.groupCount; i++) i])
      .nonNulls
      .first;
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
                'ii': 2,
                'ⅱ': 2,
                'iii': 3,
                'ⅲ': 3,
                'iv': 4,
                'ⅳ': 4,
              }[raw] ??
              1,
  );
}

final _statedSeason = RegExp(
  r'第\s*([一二三四五六七八九十\d]+)\s*[季期]|season\s*(\d+)'
  r'|(\d+)(?:st|nd|rd|th)\s*season|(?<![a-z0-9])s(\d{1,2})(?![a-z0-9])',
);
final _endingSeason = RegExp(
  r'(?<=\s)(\d{1,2})\s*$|(?<![a-z])(ii|iii|iv|ⅱ|ⅲ|ⅳ)\s*$',
);

/// Dice similarity of the best catalogue name, penalizing season mismatch and
/// adjusted by year and episode count. Calibrated thresholds: .84 automatic,
/// .55 possible match.
double sourceMatchScore(
  Subject subject,
  SourceSubject site,
  Iterable<String> names,
) {
  var best = 0.0;
  // An alias, often the original name alone, has the season the site's
  // title states.
  final stated = _normalize(site.title).$2;
  for (final title in [site.title, ...site.aliases]) {
    final (text, season) = _normalize(title);
    final target = (text, season ?? stated ?? 1);
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
        return 2 *
            left.intersection(right).length /
            (left.length + right.length);
      }

      final score =
          dice(expected.$1, target.$1) - (expected.$2 != target.$2 ? .4 : 0);
      if (score > best) best = score;
    }
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

/// The main episodes of [subject] a batch holds, numbered within the season
/// or across seasons (`[25-48]`). Like [releaseEpisode], a batch of a
/// sequel naming no season counts across seasons, as `[01-24]` is more
/// likely the first season's; one naming another season holds none.
List<Episode> batchEpisodes(Subject subject, ResourceTitleInfo info) {
  if (!info.batch || info.episodeConflict) return const [];
  final episodes = subject.episodes.where((e) => !e.numberedApart);
  final sequel = episodes.any(
    (e) => e.absolute != null && e.absolute != e.sort,
  );
  final season = _subjectSeason(subject) ?? (sequel ? null : 1);
  if (info.season != null && season != null && info.season != season) {
    return const [];
  }
  final range = RegExp(r'^(\d+)–(\d+)').firstMatch(info.episodeLabel!)!;
  bool within(double? number) =>
      number != null &&
      number >= int.parse(range[1]!) &&
      number <= int.parse(range[2]!);
  return [
    for (final episode in episodes)
      if (within(episode.absolute) ||
          (!(sequel && info.season == null) && within(episode.sort)))
        episode,
  ];
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

/// Openings/endings, soundtracks and songs, audio tracks, recaps, tutorials,
/// merchandise, audiobooks, radio shows, live-action adaptations, ambience
/// and foreigners' reactions reuse a title without holding an episode.
/// Uploaders also disguise full episodes as `reaction`, so that word alone
/// says nothing.
final _notEpisode = RegExp(
  r'NCOP|NCED|OST|原声|主题曲|片头曲|片尾曲|歌曲|音乐集|音轨|看完|解说|盘点|混剪|预告|教程|攻略|手办'
  r'|有声|广播|真人版|白噪音|老外看',
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

/// The episode of [subject] each part of an upload titled [title] holds,
/// in order. A part's name states it (`第6话`, `EP06`, `06`, `(6)`,
/// `第三季1`), else a lone part's is the one the title states, else, when no
/// part's name states one, each part is the episode at its position (`P3`
/// holds the third). A name stating another season, a special or a range
/// holds none. Like [releaseEpisode], a sequel's number may count across
/// seasons.
List<Episode?> uploadPartEpisodes(
  Subject subject,
  String title,
  List<String> parts,
) {
  var stated = [for (final name in parts) _statedEpisode(name, bare: true)];
  if (parts.length == 1 && stated.single == null) {
    stated = [_statedEpisode(title, bare: false)];
  }
  if (parts.length > 1 && stated.every((e) => e == null)) {
    stated = [for (var i = 1; i <= parts.length; i++) (null, i.toDouble())];
  }
  final episodes = subject.episodes.where((e) => !e.numberedApart);
  final sequel = episodes.any(
    (e) => e.absolute != null && e.absolute != e.sort,
  );
  final season = _subjectSeason(subject) ?? (sequel ? null : 1);
  return [
    for (final found in stated)
      if (found case (final named, final number)
          when named == null || season == null || named == season)
        (sequel
                ? episodes.where((e) => e.absolute == number).firstOrNull
                : null) ??
            episodes.where((e) => e.sort == number).firstOrNull
      else
        null,
  ];
}

/// The season and episode number [text] states, or null for none, a range
/// (`第1~5话`, `全12集`) or a special. With [bare], a text that is only a
/// number (`06`, `(6)`, `6_合并`, `1 4K`) states it too; an upload's title
/// carries `4K` and `1080P`, so it must say 第6话 or EP06.
(int?, double)? _statedEpisode(String text, {required bool bare}) {
  final season = resourceSeason(text);
  final name = simplifiedChinese(text)
      .toUpperCase()
      .replaceAll(_seasonPhrase, ' ')
      .trim();
  if (_partSpecial.hasMatch(name) || _partRange.hasMatch(name)) return null;
  final match =
      _partNumber.firstMatch(name) ??
      (bare ? _bareNumber.firstMatch(name) : null);
  if (match == null) return null;
  final raw = match
      .groups([for (var i = 1; i <= match.groupCount; i++) i])
      .nonNulls
      .first;
  final number = double.tryParse(raw) ?? _chineseNumber(raw);
  return number == null || number == 0 ? null : (season, number);
}

final _seasonPhrase = RegExp(
  r'第\s*[一二三四五六七八九十\d]+\s*[季期]|(?<![A-Z0-9])S\d{1,2}(?![0-9E])',
);
final _partSpecial = RegExp(
  r'(?<![A-Z])(?:SP|OVA|OAD|PV|NCOP|NCED)(?![A-Z])|特别篇|番外|预告',
);
final _partRange = RegExp(
  r'\d{1,3}\s*[-–~～至到]\s*\d{1,3}\s*[集话]|全\s*\d{1,3}\s*[集话]',
);
final _partNumber = RegExp(
  r'第\s*(\d{1,3}(?:\.5)?|[一二三四五六七八九十]{1,3})\s*[集话回]'
  r'|(?<![A-Z])EP?\s*(\d{1,3})(?!\d)',
);
final _bareNumber = RegExp(r'^[\s(\[【「『《〖]*(\d{1,3})(?=$|[\s)\]】」』》〗_.·-])');

/// 一 to 九十九.
double? _chineseNumber(String text) {
  const digits = '一二三四五六七八九';
  final tens = text.indexOf('十');
  int? digit(String c) => c.isEmpty
      ? null
      : digits.contains(c) && c.length == 1
      ? digits.indexOf(c) + 1
      : -1;
  if (tens < 0) {
    final value = digit(text);
    return value == null || value < 0 ? null : value.toDouble();
  }
  final high = digit(text.substring(0, tens)) ?? 1;
  final low = digit(text.substring(tens + 1)) ?? 0;
  return high < 0 || low < 0 ? null : (high * 10 + low).toDouble();
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
