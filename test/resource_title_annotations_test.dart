import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/resource_title.dart';
import 'package:melonbang/ui/acquisition/resource_widgets.dart';

void main() {
  test(
    'dimensions identify output resolution while 4K scans remain source notes',
    () {
      final dimensions = describeResource({
        'title': '[SAIO-Raws] 你好世界 Hello World [BD 1920x1080 HEVC-10bit OPUS][简繁日内封字幕]',
      });
      expect(dimensions.quality, '1080p');
      expect(
        dimensions.labels,
        containsAll(['BD', 'HEVC', '10bit', '简繁日内封字幕']),
      );
      expect(dimensions.displayTitle, '你好世界 Hello World');
      expect(dimensions.sourceGroups, isEmpty);

      final scan = describeResource({
        'title': '[银色子弹字幕组][名侦探柯南][剧场版1 计时引爆摩天楼][REMAKE重制版][简日双语MP4/繁日双语MP4/简繁日多语MKV(PGS)][BDRIP(4K重扫版)][1080P]',
      });
      expect(scan.quality, '1080p');
      expect(scan.labels, containsAll(['1080p', 'BDRip', '4K重扫版（片源）']));
      expect(scan.notes, contains('4K片源说明不代表输出画质'));
      expect(matchesResourceSelection(scan, quality: '4K'), isFalse);
      expect(scan.displayTitle, contains('剧场版1 计时引爆摩天楼'));
    },
  );

  test('joint title credits stay separate from source grouping and episode identity', () {
    final candidate = <String, dynamic>{
      'title': '[喵萌奶茶屋&VCB-Studio] HELLO WORLD / 你好世界 10-bit 1080p HEVC BDRip [MOVIE]',
      'releaseGroups': ['VCB-Studio'],
      'episodeId': 909,
    };
    final before = Map<String, dynamic>.of(candidate);
    final info = describeResource(candidate);
    expect(info.titleCredits, ['喵萌奶茶屋', 'VCB-Studio']);
    expect(info.sourceGroups, ['VCB-Studio']);
    expect(info.episodeLabel, '剧场版');
    expect(info.displayTitle, 'HELLO WORLD / 你好世界');
    expect(matchesResourceSelection(info, group: '喵萌奶茶屋'), isFalse);
    expect(matchesResourceSelection(info, group: 'VCB-Studio'), isTrue);
    expect(candidate, before);
    expect(candidate['episodeId'], 909);
  });

  test(
    'ranges and revisions are labelled without guessing an episode association',
    () {
      final reversed = describeResource({
        'title':
            '[千夏字幕组][葬送的芙莉莲_Sousou no Frieren][第39-38话][1080p_AVC][简体][合集]',
        'releaseGroups': ['千夏字幕组'],
      });
      expect(reversed.episodeConflict, isTrue);
      expect(reversed.episodeLabel, '39–38');
      expect(reversed.notes.join(' '), contains('39–38 范围倒置，集数待确认'));
      expect(reversed.displayTitle, contains('葬送的芙莉莲_Sousou no Frieren'));
      final batch = describeResource({
        'title': '[7³ACG] 葬送的芙莉莲/Sousou no Frieren S01 | 01-28+SPx11 [简繁字幕] BDrip 1080p x265 OPUS 2.0',
        'releaseGroups': ['7³ACG'],
      });
      expect(batch.episodeLabel, '01–28 + SP×11');
      expect(batch.episodeConflict, isFalse);
      final special = describeResource({
        'title': '[豌豆字幕组&风之圣殿字幕组&LoliHouse] 新石纪 龙水 特别篇 / Dr.STONE Ryuusui - SPv2 [WebRip 1080p HEVC-10bit AAC][简繁内封字幕]',
        'releaseGroups': ['LoliHouse'],
      });
      expect(special.episodeLabel, '特别篇 SPv2');
      expect(special.labels, contains('简繁内封字幕'));
      final absolute = describeResource({
        'title': '[豌豆字幕组&LoliHouse] 关于我转生变成史莱姆这档事 第四季 / Tensei Shitara Slime Datta Ken 4th Season - 23(95) [WebRip 1080p HEVC-10bit AAC][简繁外挂字幕]',
      });
      expect(absolute.episodeLabel, '23(95)');
      expect(absolute.labels, contains('简繁外挂字幕'));
    },
  );

  test(
    'HEVC and years do not manufacture resolution or episode information',
    () {
      final unknown = describeResource({
        'title': '[北宇治字幕组] 葬送的芙莉莲 / 葬送的芙莉莲 / Sousou no Frieren [38][WebRip][HEVC_AAC][简繁日内封]',
        'releaseGroups': ['北宇治字幕组'],
      });
      expect(unknown.quality, isNull);
      expect(unknown.episodeLabel, '第 38 话');
      expect(unknown.notes, contains('画质未标明'));
      expect(matchesResourceSelection(unknown, quality: '1080p'), isTrue);
      expect(
        matchesResourceSelection(
          unknown,
          quality: '1080p',
          includeUnknown: false,
        ),
        isFalse,
      );
      final fourK = describeResource({
        'title': '[GM-Team][国漫][斗破苍穹 第5季][Fights Break Sphere Ⅴ][2022][208-211][HEVC][GB][4K]',
      });
      expect(fourK.quality, '4K');
      expect(fourK.episodeLabel, '208–211');
      expect(fourK.sourceGroups, isEmpty);
      expect(
        describeResource({'title': '[86] Eighty Six [WebRip]'}).displayTitle,
        contains('86'),
      );
      expect(
        describeResource({'title': '[86] Eighty Six [WebRip]'}).episodeLabel,
        isNull,
      );
    },
  );

  test('conflicting resolutions stay unknown and absent sizes do not become zero MiB', () {
    final conflict = describeResource({'title': 'Anime [1080P 2160P]'});
    expect(conflict.quality, isNull);
    expect(conflict.notes, contains('标题含多种画质，输出待确认'));
    for (final candidate in <Json>[
      {},
      {'sizeBytes': 0},
      {'sizeBytes': 1},
    ]) {
      expect(resourceSizeLabel(candidate), '大小未知');
    }
    expect(
      resourceSizeLabel({'sizeBytes': 1, 'sizeLabel': '783.5 MiB'}),
      '783.5 MiB',
    );
    expect(resourceSizeLabel({'sizeBytes': 1073741824}), '1.0 GiB');
    expect(resourceDateLabel({'publishedAt': 'invalid'}), '未提供');
    expect(
      resourceDateLabel({'publishedAt': 'Wed, 16 Sep 2026 14:02:00 GMT'}),
      '2026-09-16',
    );
  });

  test(
    'mixed script titles retain their names and explicit subtitle wording',
    () {
      final info = describeResource({
        'title': '【MCE汉化组&U3-Web】[电影《HELLO WORLD》衍生外传动画《ANOTHER WORLD》][映画『HELLO WORLD』オリジナルスピンオフアニメ『ANOTHER WORLD』][OVA/ONA][03 - Record 2036][HikariTV WebRip][GB][1080p][x264 AAC][v1]',
      });
      expect(info.displayTitle, contains('映画『HELLO WORLD』'));
      expect(info.displayTitle, contains('电影《HELLO WORLD》'));
      expect(info.episodeLabel, '第 03 话');
      expect(info.quality, '1080p');
      expect(info.titleCredits, ['MCE汉化组', 'U3-Web']);
      expect(info.sourceGroups, isEmpty);
      final multilingual = describeResource({
        'title': '[jibaketa合成][代理商粤语]葬送的芙莉莲 第二季 / Sousou no Frieren 2nd Season - 10 END [粤日双语+内封繁体中文字幕] (WEB 1920x1080 AVC AACx2 SRT MUSE CHT)',
      });
      expect(multilingual.quality, '1080p');
      expect(multilingual.episodeLabel, '第 10 话');
      expect(multilingual.labels, containsAll(['粤日双语', '内封繁体中文字幕']));
      expect(multilingual.sourceGroups, isEmpty);
    },
  );
}
