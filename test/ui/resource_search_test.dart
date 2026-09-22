import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/ui/acquisition/resources_page.dart';
import 'package:melonbang/ui/core/theme.dart';

void main() {
  testWidgets(
    'incremental rows stay downloadable; title/group filters and episode keyword reach search',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final query = TextEditingController(text: '中文名');
      addTearDown(query.dispose);
      final candidates = <Json>[
        {
          'candidateId': 'first',
          'title': '[A & B] Anime [01][1080p]',
          'releaseGroups': ['A & B'],
          'providerName': '动漫花园',
        },
      ];
      List<String>? names;
      String? episode, downloaded;
      var busy = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return ResourcesPage(
                  subject: const {
                    'subjectId': 42,
                    'nameCn': '中文名',
                    'name': '日本語',
                  },
                  resourceSearch: query,
                  resourceEpisode: null,
                  providers: const [
                    {
                      'providerName': '动漫花园',
                      'status': 'loading',
                      'resultCount': 1,
                      'completed': 1,
                      'total': 2,
                    },
                  ],
                  candidates: List.of(candidates),
                  busy: busy,
                  onSearch: (n, e) async {
                    names = n;
                    episode = e;
                  },
                  onDownload: (c) async => downloaded = c['candidateId'],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('下载').first);
      await tester.pump();
      expect(downloaded, 'first');
      expect(find.byTooltip('已加入下载'), findsOneWidget);
      update(
        () => candidates.add({
          'candidateId': 'second',
          'title': '[Other] Anime [01][720p]',
          'releaseGroups': ['Other'],
          'providerName': '蜜柑计划',
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('下载'), findsOneWidget);
      expect(find.byTooltip('已加入下载'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '字幕组 / 联合发布'), 'B');
      await tester.pump();
      expect(find.byTooltip('已加入下载'), findsOneWidget);
      expect(find.text('[A & B] Anime [01][1080p]'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '筛选结果标题'), '720p');
      await tester.pump();
      expect(find.byTooltip('下载'), findsNothing);
      await tester.tap(find.text('清除筛选'));
      await tester.pump();
      expect(find.byTooltip('下载'), findsOneWidget);
      expect(find.byTooltip('已加入下载'), findsOneWidget);
      update(() => busy = false);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '集数关键词'), 'S01E01');
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      expect(names, ['中文名', '日本語']);
      expect(episode, 'S01E01');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('download feedback prevents duplicate adds and allows retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final query = TextEditingController(text: 'Anime');
    addTearDown(query.dispose);
    var operation = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(
          body: ResourcesPage(
            subject: const {'subjectId': 42, 'name': 'Anime'},
            resourceSearch: query,
            resourceEpisode: null,
            providers: const [],
            candidates: const [
              {'candidateId': 'first', 'title': 'Anime 01'},
            ],
            busy: false,
            onSearch: (_, _) async {},
            onDownload: (_) {
              calls++;
              return operation.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final buttonSize = tester.getSize(find.byTooltip('下载'));
    await tester.tap(find.byTooltip('下载'));
    await tester.tap(find.byTooltip('下载'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byTooltip('正在加入下载…'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('正在加入下载…')), buttonSize);

    operation.completeError(StateError('网络暂不可用'));
    await tester.pumpAndSettle();
    final retry = find.byTooltip('添加失败，点击重试\n网络暂不可用');
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry), buttonSize);
    operation = Completer<void>();
    await tester.tap(retry);
    await tester.pump();
    expect(calls, 2);
    operation.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('已加入下载'), findsOneWidget);
    await tester.tap(find.byTooltip('已加入下载'));
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search blocks duplicate clicks and keyboard submissions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final query = TextEditingController(text: 'Anime');
    addTearDown(query.dispose);
    final operation = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(
          body: ResourcesPage(
            subject: const {'subjectId': 42, 'name': 'Anime'},
            resourceSearch: query,
            resourceEpisode: null,
            providers: const [],
            candidates: const [],
            busy: false,
            onSearch: (_, _) {
              calls++;
              return operation.future;
            },
            onDownload: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final searchButton = find.widgetWithText(FilledButton, '搜索');
    final buttonSize = tester.getSize(searchButton);
    await tester.tap(searchButton);
    await tester.tap(searchButton);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '集数关键词'), '01');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(calls, 1);
    expect(tester.getSize(searchButton), buttonSize);
    expect(find.text('正在查找资源，结果会陆续显示'), findsOneWidget);
    operation.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(searchButton).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resource filters and aliases survive leaving and returning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final query = TextEditingController(text: '中文名');
    addTearDown(query.dispose);
    final bucket = PageStorageBucket();
    var visible = true;
    var subjectId = 42;
    late StateSetter update;
    List<String>? names;
    String? episode;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                if (!visible) return const SizedBox();
                return ResourcesPage(
                  key: ValueKey(subjectId),
                  subject: {
                    'subjectId': subjectId,
                    'nameCn': '中文名',
                    'name': '日本語',
                  },
                  resourceSearch: query,
                  resourceEpisode: null,
                  providers: const [],
                  candidates: const [],
                  busy: false,
                  onSearch: (n, e) async {
                    names = n;
                    episode = e;
                  },
                  onDownload: (_) async {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '集数关键词'), 'S01E02');
    await tester.enterText(find.widgetWithText(TextField, '筛选结果标题'), '1080p');
    await tester.enterText(find.widgetWithText(TextField, '字幕组 / 联合发布'), '字幕组');
    await tester.tap(find.widgetWithText(FilterChip, '日本語'));
    update(() => visible = false);
    await tester.pump();
    update(() => visible = true);
    await tester.pumpAndSettle();
    String fieldText(String label) => tester
        .widget<TextField>(find.widgetWithText(TextField, label))
        .controller!
        .text;
    expect(fieldText('集数关键词'), 'S01E02');
    expect(fieldText('筛选结果标题'), '1080p');
    expect(fieldText('字幕组 / 联合发布'), '字幕组');
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '日本語'))
          .selected,
      isFalse,
    );
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pumpAndSettle();
    expect(names, ['中文名']);
    expect(episode, 'S01E02');
    expect(fieldText('筛选结果标题'), '1080p');

    update(() => subjectId = 43);
    await tester.pumpAndSettle();
    expect(fieldText('集数关键词'), isEmpty);
    expect(fieldText('筛选结果标题'), isEmpty);
    expect(fieldText('字幕组 / 联合发布'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
