import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:melonbang/ui/core/subject_posters.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/memory_credentials.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cached pages stay usable while catalogue updates arrive', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1360, 860));
    final directory = await Directory.systemTemp.createTemp(
      'melonbang-catalog-',
    );
    final imageServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 120, 180),
      Paint()..color = const Color(0xff65cbb0),
    );
    canvas.drawCircle(
      const Offset(60, 75),
      35,
      Paint()..color = const Color(0xff236f63),
    );
    final picture = recorder.endRecording();
    final fixture = await picture.toImage(120, 180);
    final png = await fixture.toByteData(format: ui.ImageByteFormat.png);
    fixture.dispose();
    picture.dispose();
    imageServer.listen((request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(png!.buffer.asUint8List());
      await request.response.close();
    });
    final cover = 'http://127.0.0.1:${imageServer.port}/cover.png';
    final homeResponse = Completer<void>();
    final detailResponse = Completer<void>();
    final date = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 8))
        .toIso8601String()
        .substring(0, 10);
    Json title(String name) => {
      'subjectId': 42,
      'name': name,
      'nameCn': name,
      'summary': '在新的季节，与伙伴一起踏上旅程。',
      'airDate': '2026-07-01',
      'platform': 'TV',
      'score': 8.2,
      'episodeTotal': 12,
      'tags': [
        {'name': '冒险'},
        {'name': '日常'},
      ],
      'episodes': [
        {'episodeId': 7, 'ep': 1, 'name': '旅程的开始', 'type': 'main'},
      ],
    };
    var homeRequests = 0, calendarRequests = 0;
    final requests = <Uri>[];
    final service = AppServices(
      directory: directory.path,
      credentials: MemoryCredentials(),
      api: ApiClient(
        timeout: const Duration(minutes: 2),
        client: MockClient((request) async {
          requests.add(request.url);
          if (['share.dmhy.org', 'mikanani.me'].contains(request.url.host)) {
            return http.Response(
              '<rss><channel/></rss>',
              200,
              headers: {'content-type': 'application/xml; charset=utf-8'},
            );
          }
          Json body;
          if (request.url.path.endsWith('/42')) {
            await detailResponse.future;
            body = {
              'data': {...title('更新后的番剧详情'), 'coverUrl': cover},
            };
          } else if (request.url.path.endsWith('/latest')) {
            calendarRequests++;
            body = {
              'byDate': {
                date: [
                  {...title('日历作品'), 'coverUrl': '$cover?v=$calendarRequests'},
                ],
              },
            };
          } else {
            if (request.url.path.contains('/trending/')) {
              homeRequests++;
            }
            await homeResponse.future;
            body = request.url.path.endsWith('/today')
                ? {
                    'date': date,
                    'items': [title('今日放送作品')],
                  }
                : {
                    'data': [title('更新后的热门番剧')],
                    'hasMore': false,
                  };
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    final capture = GlobalKey();
    Future<void> expectArtwork() async {
      final decoded = find.descendant(
        of: find.byType(SubjectCover),
        matching: find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image != null,
        ),
      );
      for (var i = 0; i < 50 && decoded.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        decoded,
        findsWidgets,
        reason:
            'The cover must decode and render, not just create an Image widget',
      );
      await tester.pump(const Duration(milliseconds: 250));
    }

    Future<void> screenshot(String name) async {
      const prefix = String.fromEnvironment('TEST_CAPTURE');
      if (prefix.isEmpty) return;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$prefix-$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    addTearDown(() async {
      if (!homeResponse.isCompleted) homeResponse.complete();
      if (!detailResponse.isCompleted) detailResponse.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      await service.close();
      await imageServer.close(force: true);
      await directory.delete(recursive: true);
    });
    await service.start();
    for (final entry in <String, Json>{
      'trending:8:0': {
        'data': [title('本地缓存的热门番剧')],
        'hasMore': false,
      },
      'today:$date': {
        'date': date,
        'items': [title('本地缓存的今日放送')],
      },
      'detail:42': {'data': title('本地缓存的番剧详情')},
    }.entries) {
      await service.store.put('catalog', entry.key, {
        'savedAt': 0,
        'value': entry.value,
      });
    }
    await service.store.put('collection:local', '42', {
      ...title('本地追番作品'),
      'status': 'watching',
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MelonApp(
          service: service,
          preferences: await SharedPreferences.getInstance(),
        ),
      ),
    );
    for (var i = 0; i < 30 && find.text('本地缓存的热门番剧').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('本地缓存的热门番剧'), findsWidgets);
    expect(find.text('今日暂无放送数据'), findsNothing);
    expect(homeResponse.isCompleted, isFalse);
    final dynamic state = tester.state(find.byType(MelonApp));
    final Future<void> opening = state.openSubject(title('本地缓存的热门番剧'));
    for (var i = 0; i < 30 && state.busy == true; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(state.subject['name'], '本地缓存的番剧详情');
    expect(state.busy, isFalse);
    expect(detailResponse.isCompleted, isFalse);
    expect(find.text('旅程的开始'), findsOneWidget);
    await screenshot('detail');

    await tester.tap(find.byKey(const ValueKey('brand-home')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.route, 'home');
    expect(find.text('本地缓存的热门番剧'), findsWidgets);
    expect(homeRequests, 1, reason: requests.join('\n'));
    expect(
      requests
          .singleWhere((url) => url.path.contains('/trending/'))
          .queryParameters['limit'],
      '8',
    );
    expect(
      requests
          .singleWhere((url) => url.path.endsWith('/42'))
          .queryParameters['includeHtml'],
      'false',
    );
    detailResponse.complete();
    await opening;
    expect(state.route, 'home');
    state.goBack();
    for (var i = 0; i < 30 && state.subject['name'] != '更新后的番剧详情'; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(state.subject['name'], '更新后的番剧详情');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('查找资源 EP1'));
    for (var i = 0; i < 30 && state.busy == true; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(state.route, 'resources');
    final episodeField = find.widgetWithText(TextField, '集数关键词');
    expect(tester.widget<TextField>(episodeField).controller!.text, '01');
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    final providerRequests = requests.where(
      (url) => ['share.dmhy.org', 'mikanani.me'].contains(url.host),
    );
    expect(providerRequests, isNotEmpty);
    expect(
      providerRequests.every(
        (url) => url.queryParameters.values.single.endsWith(' 01'),
      ),
      isTrue,
      reason: providerRequests.join('\n'),
    );
    await screenshot('resources');
    await tester.enterText(episodeField, 'S01E01');
    await tester.tap(find.byKey(const ValueKey('brand-home')));
    await tester.pump(const Duration(milliseconds: 300));
    state.goBack();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<TextField>(episodeField).controller!.text, 'S01E01');
    state.goBack();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('查找资源 EP1'));
    for (var i = 0; i < 30 && state.busy == true; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.widget<TextField>(episodeField).controller!.text, '01');
    state.goBack();
    await tester.pump(const Duration(milliseconds: 300));
    final previousRequests = providerRequests.length;
    await tester.tap(find.widgetWithText(OutlinedButton, '查找资源'));
    for (var i = 0; i < 30 && state.busy == true; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.widget<TextField>(episodeField).controller!.text, isEmpty);
    expect(
      providerRequests
          .skip(previousRequests)
          .every((url) => url.queryParameters.values.single == '更新后的番剧详情'),
      isTrue,
    );
    state.goBack();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('brand-home')));
    await tester.pump(const Duration(milliseconds: 200));
    homeResponse.complete();
    for (var i = 0; i < 30 && state.trendingLoading == true; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('更新后的热门番剧'), findsWidgets);
    expect(homeRequests, 1);
    expect(service.catalog.coverFor(42), cover);
    expect(
      find.descendant(
        of: find.byType(SubjectCover),
        matching: find.byType(Image),
      ),
      findsWidgets,
    );
    await expectArtwork();
    await screenshot('home');
    state.navigate('tracking');
    await tester.pumpAndSettle();
    expect(find.text('本地追番作品'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(SubjectCover),
        matching: find.byType(Image),
      ),
      findsWidgets,
    );
    await expectArtwork();
    await screenshot('tracking-covers');
    state.navigate('calendar');
    for (var i = 0; i < 30 && state.calendar.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(state.calendar.single['items'].single['coverUrl'], '$cover?v=1');
    state.navigate('tracking');
    state.navigate('calendar');
    for (var i = 0; i < 30 && calendarRequests < 2; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(calendarRequests, 2);
    expect(state.calendar.single['items'].single['coverUrl'], '$cover?v=2');
    expect(
      find.descendant(
        of: find.byType(SubjectCover),
        matching: find.byType(Image),
      ),
      findsWidgets,
    );
    await expectArtwork();
    await screenshot('calendar-covers');
    state.navigate('home');
    await tester.pumpAndSettle();
    state.setDark(true);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    await screenshot('home-dark');
    state.navigate('settings');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('服务连接'), findsNothing);
    expect(find.text('Bangumi Client Secret'), findsNothing);
    expect(find.text('登录 Bangumi'), findsOneWidget);
    await screenshot('settings');
    expect(tester.takeException(), isNull);
  });
}
