import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:melonbang/app.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/network.dart';
import 'package:melonbang/ui/core/page_widgets.dart';
import 'package:melonbang/ui/core/selection_controls.dart';
import 'package:melonbang/ui/core/subject_posters.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/memory_credentials.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('desktop layouts preserve navigation and drafts across sizes', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    final directory = await Directory.systemTemp.createTemp(
      'melonbang-design-',
    );
    const names = ['葬送的芙莉莲', '孤独摇滚！', '迷宫饭', '跃动青春', '夏目友人帐', '紫罗兰永恒花园'];
    final subjects = [
      for (var i = 0; i < names.length; i++)
        <String, dynamic>{
          'subjectId': i + 1,
          'nameCn': names[i],
          'name': 'Animation ${i + 1}',
          'score': 8.6 - i / 10,
          'episodeTotal': 12,
          'platform': 'TV',
          'season': {'label': '2026 SUMMER'},
          'airDate': '2026-07-01',
          'airingAtShanghai': '2026-09-08T19:30:00+08:00',
          'summary': '一段旅程的终点，也是另一段故事的开始。与伙伴一同出发，发现日常中的温柔与新的风景。',
          'rank': 35 + i,
          'tags': [
            {'name': '冒险'},
            {'name': '日常'},
          ],
          'episodes': [
            for (var ep = 1; ep <= 12; ep++)
              {
                'episodeId': (i + 1) * 100 + ep,
                'sort': ep,
                'name': '第 $ep 话 · 旅途的风景',
              },
          ],
        },
    ];
    Completer<void>? refreshGate;
    var failToday = false;
    final services = AppServices(
      directory: directory.path,
      credentials: MemoryCredentials(),
      api: ApiClient(
        client: MockClient((request) async {
          if (refreshGate != null) await refreshGate.future;
          if (failToday && request.url.path.endsWith('/today')) {
            return http.Response('', 503);
          }
          final id = int.tryParse(request.url.pathSegments.last);
          final value = id != null
              ? {'data': subjects[id - 1]}
              : request.url.path.endsWith('/today')
              ? {'items': subjects.take(3).toList()}
              : {'data': subjects, 'hasMore': false};
          return http.Response(
            jsonEncode(value),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    await services.start();
    for (final subject in subjects.take(4)) {
      await services.store.put(
        'collection:${services.account.userId}',
        '${subject['subjectId']}',
        {...subject, 'status': 'watching', 'watchedEpisodes': 5},
      );
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
      await services.close();
      await directory.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MelonApp(
          service: services,
          preferences: await SharedPreferences.getInstance(),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final dynamic state = tester.state(find.byType(MelonApp));
    Future<void> snapshot(String name) async {
      debugPrint('Snapshot: $name');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: name);
      const output = String.fromEnvironment('TEST_CAPTURE_DIR');
      if (output.isEmpty) return;
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    Future<void> hoverSnapshot(Finder target, String name) async {
      await tester.ensureVisible(target);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 200));
      await snapshot(name);
      await mouse.removePointer();
      await tester.pump(const Duration(milliseconds: 200));
    }

    Finder arrow(String tooltip) => find.descendant(
      of: find.byType(SubjectPosters).first,
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      ),
    );

    Future<void> homeTop() async {
      await tester.scrollUntilVisible(
        find.text('热门与精选'),
        -450,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('page-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    debugPrint('Checking delayed search navigation');
    refreshGate = Completer<void>();
    state.search.text = 'delayed';
    final Future<void> delayedSearch = state.searchSubjects();
    state.navigate('tracking');
    state.goBack();
    expect(state.route, 'search');
    expect(state.busy, isTrue);
    refreshGate.complete();
    await delayedSearch;
    for (var i = 0; i < 20 && state.busy == true; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    refreshGate = null;
    expect(state.results.length, names.length);

    debugPrint('Checking delayed detail navigation');
    refreshGate = Completer<void>();
    final Future<void> delayedDetail = state.openSubject(<String, dynamic>{
      'subjectId': 2,
      'name': names[1],
    });
    state.navigate('tracking');
    state.goBack();
    expect(state.route, 'subject');
    expect(state.busy, isTrue);
    refreshGate.complete();
    await delayedDetail;
    for (var i = 0; i < 20 && state.busy == true; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    refreshGate = null;
    expect((state.subject['episodes'] as List).length, 12);

    debugPrint('Checking desktop viewports');
    for (final width in [1360.0, 960.0]) {
      await windowManager.setSize(Size(width, width == 960 ? 640 : 1000));
      await tester.pump(const Duration(milliseconds: 500));
      state.navigate('home');
      await tester.pump(const Duration(milliseconds: 300));
      await homeTop();
      await snapshot('home-${width.toInt()}');
      await tester.ensureVisible(find.byType(SubjectPosters).first);
      await tester.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 4 && arrow('向右翻页').evaluate().isNotEmpty; i++) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(arrow('向右翻页')));
        await tester.pump(const Duration(milliseconds: 200));
        await snapshot('paging-hover-${width.toInt()}');
        await tester.tap(arrow('向右翻页'));
        await mouse.removePointer();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await snapshot('home-scroll-right-${width.toInt()}');
      expect(arrow('向右翻页'), findsNothing);
      for (var i = 0; i < 4 && arrow('向左翻页').evaluate().isNotEmpty; i++) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(arrow('向左翻页')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(arrow('向左翻页'));
        await mouse.removePointer();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(arrow('向左翻页'), findsNothing);
      await homeTop();
      expect(find.text('打开视频'), findsNothing);
      await tester.tap(find.byTooltip('收起侧栏'));
      await snapshot('collapsed-${width.toInt()}');
      await tester.tap(find.byTooltip('展开侧栏'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (width == 1360) {
        refreshGate = Completer<void>();
        await tester.tap(find.text('刷新'));
        await tester.pump();
        expect(find.text('刷新中…'), findsOneWidget);
        await snapshot('refresh-running');
        failToday = true;
        refreshGate.complete();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        refreshGate = null;
        expect(find.text('本季热度已更新，今日放送刷新失败。'), findsOneWidget);
        expect(find.text(names.first), findsWidgets);
        await snapshot('refresh-partial');
        failToday = false;
        await tester.tap(find.text('重试'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('已更新'), findsOneWidget);
        expect(find.textContaining('刚刚'), findsNothing);
        await snapshot('refresh-success');
      }
      final sections = tester
          .widgetList<SectionTitle>(find.byType(SectionTitle))
          .map((w) => w.title)
          .toList();
      expect(sections.take(2), ['热门与精选', '正在追']);
      await tester.scrollUntilVisible(
        find.text('本季热度'),
        450,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('page-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await snapshot('home-popularity-${width.toInt()}');
      await tester.tap(find.text('追番').first);
      await snapshot('tracking-${width.toInt()}');
      await tester.tap(find.text('同步收藏'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('登录 Bangumi 后可同步收藏。'), findsOneWidget);
      await snapshot('sync-sign-in-${width.toInt()}');
      await hoverSnapshot(
        find.text('已看 5 话').first,
        'tracking-hover-${width.toInt()}',
      );
      final collectionSearch = find.widgetWithText(TextField, '在追番列表中搜索…');
      Future<void> showCollectionSearch() async {
        await tester.scrollUntilVisible(
          collectionSearch,
          -300,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey('page-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pump(const Duration(milliseconds: 300));
      }

      await showCollectionSearch();
      await tester.enterText(collectionSearch, names.first);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.ensureVisible(find.text('已看 5 话').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('已看 5 话').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.selectedSection, 'tracking');
      await tester.tap(find.byTooltip('返回'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.route, 'tracking');
      await showCollectionSearch();
      expect(
        tester.widget<TextField>(collectionSearch).controller!.text,
        names.first,
      );
      await tester.enterText(collectionSearch, '');
      await tester.pump();
      await tester.ensureVisible(find.text('已看 5 话').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('已看 5 话').first);
      await tester.pump(const Duration(milliseconds: 500));
      await snapshot('subject-${width.toInt()}');
      await tester.ensureVisible(find.text('选集'));
      await tester.pump();
      await tester.tap(find.text('选集'));
      await snapshot('episodes-${width.toInt()}');
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('1')),
      );
      await tester.pumpAndSettle();
      final wasWatched = state.subject['episodes'][0]['status'] == 'watched';
      await tester.tap(find.byTooltip('标记已看 / 未看').first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        state.subject['episodes'][0]['status'],
        wasWatched ? 'unwatched' : 'watched',
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.textContaining(wasWatched ? '未看 ·' : '已看 ·'),
        ),
        findsWidgets,
      );
      await tester.tap(find.byTooltip('关闭选集'));
      await tester.pump(const Duration(milliseconds: 300));
      state.calendar = <Map<String, dynamic>>[
        {
          'weekday': {'id': 1},
          'items': [subjects[0]],
        },
        {
          'weekday': {'id': 2},
          'items': [subjects[1]],
        },
      ];
      state.navigate('calendar');
      await tester.pump();
      await tester.tap(find.text('周一').first);
      await tester.pump();
      expect(find.text(names.first), findsOneWidget);
      await tester.tap(find.text('周二').first);
      await tester.pump();
      expect(find.text(names.first), findsNothing);
      expect(find.text(names[1]), findsOneWidget);
      await snapshot('calendar-${width.toInt()}');
      await hoverSnapshot(
        find.text(names[1]),
        'calendar-hover-${width.toInt()}',
      );
      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      expect(state.route, 'subject');
      state.resourceEpisode = 101;
      state.resourceSearch.text = names.first;
      state.candidates = <Map<String, dynamic>>[
        {
          'candidateId': 'dimensions',
          'title': '[Shiniori-Raws] 葬送的芙莉莲 第二季/Sousou no Frieren S2 (BD 1920x1080 x265 10bit FLAC)',
          'sizeBytes': 19005231104,
          'providerName': '蜜柑计划',
          'publishedAt': '2026-08-15T23:20:00',
          'detailUrl': 'https://mikanani.me/Home/Episode/4ca78745e6d0c84dc8b46cd69dd605bbdbe72881',
        },
        {
          'candidateId': 'unknown-quality',
          'title': '[北宇治字幕组] 葬送的芙莉莲 / 葬送的芙莉莲 / Sousou no Frieren [38][WebRip][HEVC_AAC][简繁日内封]',
          'releaseGroups': ['北宇治字幕组'],
          'providerName': '蜜柑计划',
          // Exercise the RSS missing-size sentinel independently of the title.
          'sizeBytes': 1,
          'detailUrl': 'https://mikanani.me/Home/Episode/1188285f8b296e1e7e2f622955f214b71e93d2dc',
        },
        {
          'candidateId': 'reversed-range',
          'title':
              '[千夏字幕组][葬送的芙莉莲_Sousou no Frieren][第39-38话][1080p_AVC][简体][合集]',
          'releaseGroups': ['千夏字幕组'],
          'publishedAt': '2026-05-11T17:34:00',
          'providerName': '蜜柑计划',
          'sizeBytes': 4509715456,
          'detailUrl': 'https://mikanani.me/Home/Episode/e4a7d9d92377e158f4524439936d70a50c3d9d0f',
        },
        {
          'candidateId': 'joint-release',
          'title': '[豌豆字幕组&风之圣殿字幕组&LoliHouse] 新石纪 龙水 特别篇 / Dr.STONE Ryuusui - SPv2 [WebRip 1080p HEVC-10bit AAC][简繁内封字幕]',
          'releaseGroups': ['LoliHouse'],
          'publishedAt': '2022-07-20T22:50:06.519',
          'providerName': '蜜柑计划',
          'sizeBytes': 1048397760,
          'detailUrl': 'https://mikanani.me/Home/Episode/8452ad7595b65c157a81dc771238b70bca941237',
        },
        {
          'candidateId': 'source-scan',
          'title': '[银色子弹字幕组][名侦探柯南][剧场版1 计时引爆摩天楼][REMAKE重制版][简日双语MP4/繁日双语MP4/简繁日多语MKV(PGS)][BDRIP(4K重扫版)][1080P]',
          'providerName': '蜜柑计划',
          'publishedAt': '2026-04-12T16:16:00',
          'sizeBytes': 15891379200,
          'detailUrl': 'https://mikanani.me/Home/Episode/cbaea0dff12e097e15f76e48b3bca7a660cb9e01',
        },
      ];
      state.providers = <Map<String, dynamic>>[
        {'providerName': '蜜柑计划', 'status': 'complete', 'resultCount': 5},
      ];
      state.navigate('resources');
      await tester.pumpAndSettle();
      final resourceScroll = find
          .descendant(
            of: find.byKey(const PageStorageKey('page-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> resourcesTop() async {
        await tester.scrollUntilVisible(
          find.widgetWithText(TextField, '资源关键词'),
          -350,
          scrollable: resourceScroll,
        );
        await tester.pumpAndSettle();
      }

      await resourcesTop();
      await snapshot('resources-${width.toInt()}');
      final original = find.byKey(
        const ValueKey('resource-original:dimensions'),
      );
      await tester.scrollUntilVisible(
        original,
        250,
        scrollable: resourceScroll,
      );
      await tester.tap(original);
      await tester.pumpAndSettle();
      await snapshot('resources-original-${width.toInt()}');
      await resourcesTop();
      await tester.tap(
        find.descendant(
          of: find.byType(MelonSegmentedControl<String>),
          matching: find.text('1080p'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(MelonChoiceMenu<String>),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pumpAndSettle();
      await snapshot('resources-menu-${width.toInt()}');
      await tester.tap(find.widgetWithText(MenuItemButton, '北宇治字幕组'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('含未确认'));
      await tester.pumpAndSettle();
      expect(find.text('没有符合筛选条件的资源'), findsOneWidget);
      await snapshot('resources-filtered-${width.toInt()}');
      await tester.ensureVisible(find.text('清除筛选'));
      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      final unknown = find.byKey(
        const ValueKey('resource-original:unknown-quality'),
      );
      await tester.scrollUntilVisible(unknown, 300, scrollable: resourceScroll);
      await tester.pumpAndSettle();
      expect(find.text('画质未标明'), findsWidgets);
      await snapshot('resources-unknown-${width.toInt()}');
      await resourcesTop();
      await tester.scrollUntilVisible(
        original,
        250,
        scrollable: resourceScroll,
      );
      await tester.tap(original);
      await tester.pumpAndSettle();
      await resourcesTop();
      state.downloads = <String, dynamic>{
        'tasks': <Map<String, dynamic>>[
          {
            'id': 'pending',
            'title': '第 01 话 · 1080p HEVC 多字幕视频版本',
            'status': 'paused',
            'progress': .42,
          },
          {'id': 'done', 'title': '完整缓存', 'status': 'completed', 'progress': 1},
        ],
        'files': <Map<String, dynamic>>[
          {
            'id': 'video',
            'downloadId': 'done',
            'name': '第 01 话.mkv',
            'mediaKind': 'video',
            'progress': 1,
          },
        ],
      };
      state.navigate('downloads');
      await snapshot('downloads-${width.toInt()}');
      await tester.tap(find.byTooltip('更多缓存操作'));
      await snapshot('downloads-menu-${width.toInt()}');
      expect(find.text('打开本地视频…'), findsOneWidget);
      await tester.tapAt(const Offset(500, 80));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('所有状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '已暂停'));
      await tester.pumpAndSettle();
      expect(find.text('完整缓存'), findsNothing);
      state.navigate('settings');
      await snapshot('settings-${width.toInt()}');
      await tester.tap(find.text('服务连接'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('编辑 Bangumi'));
      await tester.pump(const Duration(milliseconds: 300));
      final input = find.widgetWithText(TextField, 'Bangumi Client ID');
      await tester.enterText(input, 'draft-client');
      await snapshot('connections-${width.toInt()}');
      await tester.tap(find.text('界面与外观'));
      await tester.pump();
      await snapshot('appearance-${width.toInt()}');
      await hoverSnapshot(
        find.text('深色主题'),
        'appearance-hover-${width.toInt()}',
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await snapshot('appearance-dark-${width.toInt()}');
      await tester.tap(find.text('服务连接'));
      await tester.pump();
      expect(find.text('draft-client'), findsOneWidget);
      final sidebarToggle = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.view_sidebar_outlined),
      );
      expect(sidebarToggle.onPressed, isNull);
      expect(find.text('服务连接'), findsNWidgets(2));
      expect(find.text('draft-client'), findsOneWidget);
      await snapshot('connections-dark-${width.toInt()}');
      state.navigate('home');
      await tester.pump(const Duration(milliseconds: 300));
      await homeTop();
      await snapshot('home-dark-${width.toInt()}');
      state.setDark(false);
    }
  });
}
