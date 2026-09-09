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

    for (final width in [1360.0, 960.0]) {
      await windowManager.setSize(Size(width, width == 960 ? 640 : 1000));
      await tester.pump(const Duration(milliseconds: 500));
      state.navigate('home');
      await snapshot('home-${width.toInt()}');
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
      expect(find.text('打开视频'), findsNothing);
      await tester.tap(find.byTooltip('收起侧栏'));
      await snapshot('collapsed-${width.toInt()}');
      await tester.tap(find.byTooltip('展开侧栏'));
      await tester.pump();
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
      expect(sections.take(2), ['本季热度', '继续播放']);
      await tester.tap(find.text('追番').first);
      await snapshot('tracking-${width.toInt()}');
      await tester.tap(find.text('同步收藏'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('登录 Bangumi 后可同步收藏。'), findsOneWidget);
      await snapshot('sync-sign-in-${width.toInt()}');
      await hoverSnapshot(
        find.text('看到 EP5').first,
        'tracking-hover-${width.toInt()}',
      );
      await tester.tap(find.text('看到 EP5').first);
      await tester.pump(const Duration(milliseconds: 500));
      await snapshot('subject-${width.toInt()}');
      await tester.ensureVisible(find.text('选集'));
      await tester.pump();
      await tester.tap(find.text('选集'));
      await snapshot('episodes-${width.toInt()}');
      final wasWatched = state.subject['episodes'][0]['status'] == 'watched';
      await tester.tap(find.byTooltip('标记已看 / 未看').first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        state.subject['episodes'][0]['status'],
        wasWatched ? 'unwatched' : 'watched',
      );
      expect(find.text(wasWatched ? '未看' : '已看'), findsWidgets);
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
      await tester.tap(find.byTooltip('返回探索'));
      await tester.pump();
      expect(find.text('本季热度'), findsOneWidget);
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
      await tester.tap(find.widgetWithText(ChoiceChip, '已暂停'));
      await tester.pump();
      expect(find.text('完整缓存'), findsNothing);
      state.navigate('settings');
      await snapshot('settings-${width.toInt()}');
      await tester.tap(find.text('服务连接'));
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
      await tester.tap(find.byTooltip('收起侧栏'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('draft-client'), findsOneWidget);
      await tester.tap(find.byTooltip('展开侧栏'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('draft-client'), findsOneWidget);
      await snapshot('connections-dark-${width.toInt()}');
      state.navigate('home');
      await snapshot('home-dark-${width.toInt()}');
      state.setDark(false);
    }
  });
}
