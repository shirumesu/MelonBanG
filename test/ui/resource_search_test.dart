import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/ui/acquisition/resource_widgets.dart';
import 'package:melonbang/ui/acquisition/resources_page.dart';
import 'package:melonbang/ui/core/selection_controls.dart';
import 'package:melonbang/ui/core/theme.dart';

void main() {
  testWidgets('episode context seeds search without overwriting saved drafts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final query = TextEditingController(text: 'Anime');
    addTearDown(query.dispose);
    final bucket = PageStorageBucket();
    int? episodeId = 901;
    var visible = true;
    late StateSetter update;
    String? searchedEpisode;
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
                  subject: const {
                    'subjectId': 42,
                    'name': 'Anime',
                    'episodes': [
                      {'episodeId': 901, 'sort': 1},
                      {'episodeId': 902, 'sort': 12.5},
                    ],
                  },
                  resourceSearch: query,
                  resourceEpisode: episodeId,
                  providers: const [],
                  candidates: const [],
                  busy: false,
                  onSearch: (_, episode) async => searchedEpisode = episode,
                  onDownload: (_) async {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, '集数关键词');
    String text() => tester.widget<TextField>(field).controller!.text;
    expect(text(), '01');
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pumpAndSettle();
    expect(searchedEpisode, '01');

    await tester.enterText(field, 'S01E01');
    update(() => visible = false);
    await tester.pump();
    update(() => visible = true);
    await tester.pumpAndSettle();
    expect(text(), 'S01E01');
    update(() => episodeId = 902);
    await tester.pumpAndSettle();
    expect(text(), '12.5');
    update(() => episodeId = null);
    await tester.pumpAndSettle();
    expect(text(), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pumpAndSettle();
    expect(searchedEpisode, isEmpty);
    update(() => episodeId = 901);
    await tester.pumpAndSettle();
    expect(text(), 'S01E01');
    await tester.enterText(field, '');
    update(() => visible = false);
    await tester.pump();
    update(() => visible = true);
    await tester.pumpAndSettle();
    expect(text(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider chips filter locally and preserve other selections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final query = TextEditingController(text: 'Anime');
    addTearDown(query.dispose);
    var searches = 0;
    final candidates = <Json>[
      {
        'candidateId': 'garden',
        'providerId': 'dmhy',
        'providerName': '动漫花园',
        'title': 'Garden [1080p]',
        'releaseGroups': ['A'],
      },
      {
        'candidateId': 'garden-low',
        'providerId': 'dmhy',
        'providerName': '动漫花园',
        'title': 'Garden [720p]',
        'releaseGroups': ['A'],
      },
      {
        'candidateId': 'mikan',
        'providerId': 'mikan',
        'providerName': '蜜柑计划',
        'title': 'Mikan [1080p]',
        'releaseGroups': ['A'],
      },
    ];
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return ResourcesPage(
                subject: const {'subjectId': 42, 'name': 'Anime'},
                resourceSearch: query,
                resourceEpisode: null,
                providers: [
                  {
                    'providerId': 'dmhy',
                    'providerName': '动漫花园',
                    'status': 'ready',
                    'resultCount': candidates.length - 1,
                  },
                  {
                    'providerId': 'mikan',
                    'providerName': '蜜柑计划',
                    'status': 'ready',
                    'resultCount': 1,
                  },
                ],
                candidates: List.of(candidates),
                busy: false,
                onSearch: (_, _) async => searches++,
                onDownload: (_) async {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dmhy = find.byKey(const ValueKey('resource-provider:dmhy'));
    final mikan = find.byKey(const ValueKey('resource-provider:mikan'));
    expect(tester.widget<FilterChip>(dmhy).selected, isTrue);
    expect(tester.widget<FilterChip>(mikan).selected, isTrue);
    await tester.tap(
      find.descendant(
        of: find.byType(MelonSegmentedControl<String>),
        matching: find.text('1080p'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(dmhy);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(dmhy).selected, isFalse);
    expect(
      find.byKey(const ValueKey('resource-original:garden')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('resource-original:mikan')),
      findsOneWidget,
    );
    expect(find.text('动漫花园 · 2 条'), findsOneWidget);
    expect(find.text('1 / 3 条'), findsOneWidget);

    update(
      () => candidates.add({...candidates.first, 'candidateId': 'garden-late'}),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ResourceResultRow), findsOneWidget);
    expect(find.text('动漫花园 · 3 条'), findsOneWidget);
    await tester.tap(mikan);
    await tester.pumpAndSettle();
    expect(find.text('已取消选择全部资源站'), findsOneWidget);
    expect(find.byType(ResourceResultRow), findsNothing);
    await tester.tap(find.text('显示全部来源'));
    await tester.pumpAndSettle();
    expect(find.byType(ResourceResultRow), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('resource-original:garden-low')),
      findsNothing,
    );

    Focus.of(tester.element(find.text('动漫花园 · 3 条'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(dmhy).selected, isFalse);
    expect(find.byType(ResourceResultRow), findsOneWidget);
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(dmhy).selected, isTrue);
    expect(find.byType(ResourceResultRow), findsNWidgets(4));
    expect(searches, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'incremental rows preserve focus; quality/group filters and episode keyword reach search',
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
      await tester.enterText(find.widgetWithText(TextField, '集数关键词'), 'S01E01');
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
      final episodeField = tester.widget<TextField>(
        find.widgetWithText(TextField, '集数关键词'),
      );
      expect(episodeField.controller!.text, 'S01E01');
      expect(episodeField.focusNode!.hasFocus, isTrue);
      await tester.tap(
        find.descendant(
          of: find.byType(MelonChoiceMenu<String>),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(MenuItemButton, 'A & B'));
      await tester.pump();
      expect(find.byTooltip('已加入下载'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('resource-original:first')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('[A & B] Anime [01][1080p]'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(MelonSegmentedControl<String>),
          matching: find.text('720p'),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('下载'), findsNothing);
      await tester.tap(find.text('清除筛选'));
      await tester.pump();
      expect(find.byTooltip('下载'), findsOneWidget);
      expect(find.byTooltip('已加入下载'), findsOneWidget);
      update(() => busy = false);
      await tester.pump();
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
                  providers: const [
                    {
                      'providerId': 'dmhy',
                      'providerName': '动漫花园',
                      'status': 'ready',
                      'resultCount': 1,
                    },
                    {
                      'providerId': 'mikan',
                      'providerName': '蜜柑计划',
                      'status': 'ready',
                      'resultCount': 0,
                    },
                  ],
                  candidates: const [
                    {
                      'candidateId': 'saved',
                      'providerId': 'dmhy',
                      'title': '[字幕组] Anime [01][1080p]',
                      'releaseGroups': ['字幕组'],
                    },
                  ],
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
    await tester.enterText(find.widgetWithText(TextField, '资源关键词'), '搜索草稿');
    await tester.tap(
      find.descendant(
        of: find.byType(MelonSegmentedControl<String>),
        matching: find.text('1080p'),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(MelonChoiceMenu<String>),
        matching: find.byType(OutlinedButton),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '字幕组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('含未确认'));
    await tester.tap(find.byKey(const ValueKey('resource-aliases-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '日本語'));
    await tester.tap(find.byKey(const ValueKey('resource-provider:mikan')));
    await tester.tap(find.byKey(const ValueKey('resource-original:saved')));
    await tester.pumpAndSettle();
    update(() => visible = false);
    await tester.pump();
    update(() => visible = true);
    await tester.pumpAndSettle();
    String fieldText(String label) => tester
        .widget<TextField>(find.widgetWithText(TextField, label))
        .controller!
        .text;
    expect(fieldText('集数关键词'), 'S01E02');
    expect(fieldText('资源关键词'), '搜索草稿');
    expect(
      tester
          .widget<MelonSegmentedControl<String>>(
            find.byType(MelonSegmentedControl<String>),
          )
          .value,
      '1080p',
    );
    expect(
      tester
          .widget<MelonChoiceMenu<String>>(find.byType(MelonChoiceMenu<String>))
          .value,
      '字幕组',
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('resource-provider:mikan')),
          )
          .selected,
      isFalse,
    );
    expect(find.text('[字幕组] Anime [01][1080p]'), findsOneWidget);
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
    expect(
      tester
          .widget<MelonSegmentedControl<String>>(
            find.byType(MelonSegmentedControl<String>),
          )
          .value,
      '1080p',
    );

    update(() => subjectId = 43);
    await tester.pumpAndSettle();
    expect(fieldText('集数关键词'), isEmpty);
    expect(
      tester
          .widget<MelonSegmentedControl<String>>(
            find.byType(MelonSegmentedControl<String>),
          )
          .value,
      'all',
    );
    expect(
      tester
          .widget<MelonChoiceMenu<String>>(find.byType(MelonChoiceMenu<String>))
          .value,
      isEmpty,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('resource-provider:mikan')),
          )
          .selected,
      isTrue,
    );
    expect(find.byType(SelectableText), findsNothing);
    expect(find.widgetWithText(FilterChip, '日本語'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
