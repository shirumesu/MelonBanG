import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/ui/core/action_feedback.dart';
import 'package:melonbang/ui/core/theme.dart';
import 'package:melonbang/ui/discovery/discovery_pages.dart';

const _subjects = <Json>[
  {
    'subjectId': 1,
    'nameCn': '第一部作品',
    'season': {'label': '2024 WINTER'},
    'platform': 'TV',
    'tags': [
      {'name': '奇幻'},
    ],
    'score': 8.2,
    'summary': '来自作品数据的简介。',
  },
  {'subjectId': 2, 'nameCn': '第二部作品', 'airDate': '2023-10-05'},
  {'subjectId': 3, 'nameCn': '第三部作品'},
];

HomePage _home({
  required ActionFeedback feedback,
  List<Json> trending = _subjects,
  List<Json> watching = const [],
  List<Json> resumable = const [],
  ValueChanged<Json>? onOpen,
  ValueChanged<Json>? onResume,
}) => HomePage(
  dark: false,
  today: const [],
  trending: trending,
  watching: watching,
  resumable: resumable,
  onResume: onResume,
  trendingLoading: false,
  error: null,
  onExplore: () {},
  feedback: feedback,
  onCalendar: () {},
  onRefresh: () {},
  onOpenSubject: onOpen ?? (_) {},
);

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1100, 1000),
  bool dark = false,
  bool reduceMotion = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('featured subjects switch manually and open the selected work', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final feedback = ActionFeedback();
    addTearDown(feedback.dispose);
    Json? opened;
    await _show(
      tester,
      _home(feedback: feedback, onOpen: (item) => opened = item),
    );
    final open = find.byKey(const ValueKey('open-featured-subject'));
    await tester.tap(open);
    expect(opened?['subjectId'], 1);
    expect(find.text('2024 WINTER').hitTestable(), findsOneWidget);
    expect(find.text('奇幻').hitTestable(), findsOneWidget);

    await tester.pump(const Duration(seconds: 15));
    await tester.tap(open);
    expect(
      opened?['subjectId'],
      1,
      reason: 'The feature must not auto-advance.',
    );

    await tester.tap(find.byTooltip('下一项精选'));
    await tester.pumpAndSettle();
    await tester.tap(open);
    expect(opened?['subjectId'], 2);
    expect(find.text('2023 秋').hitTestable(), findsOneWidget);

    await tester.tap(find.byTooltip('精选 3：第三部作品'));
    await tester.pumpAndSettle();
    await tester.tap(open);
    expect(opened?['subjectId'], 3);

    Focus.of(tester.element(find.byIcon(Icons.chevron_right_rounded)))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.tap(open);
    expect(opened?['subjectId'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('featured selection survives a return and refreshed order', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final feedback = ActionFeedback();
    addTearDown(feedback.dispose);
    final bucket = PageStorageBucket();
    final visible = ValueNotifier(true);
    final subjects = ValueNotifier<List<Json>>(_subjects);
    addTearDown(visible.dispose);
    addTearDown(subjects.dispose);
    Json? opened;
    await _show(
      tester,
      PageStorage(
        bucket: bucket,
        child: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, showHome, _) => showHome
              ? ValueListenableBuilder<List<Json>>(
                  valueListenable: subjects,
                  builder: (context, items, _) => _home(
                    feedback: feedback,
                    trending: items,
                    onOpen: (item) => opened = item,
                  ),
                )
              : const SizedBox(),
        ),
      ),
    );
    await tester.tap(find.byTooltip('精选 3：第三部作品'));
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pumpAndSettle();
    subjects.value = [_subjects[2], _subjects[0], _subjects[1]];
    visible.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-featured-subject')));
    expect(opened?['subjectId'], 3);
    subjects.value = [_subjects[1]];
    await tester.pumpAndSettle();
    expect(find.byTooltip('下一项精选'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('open-featured-subject')));
    expect(opened?['subjectId'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume cards use actual progress and keep collection separate', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final feedback = ActionFeedback();
    addTearDown(feedback.dispose);
    await _show(tester, _home(feedback: feedback, watching: _subjects));
    expect(find.text('继续播放'), findsNothing);
    expect(find.text('正在追'), findsOneWidget);

    Json? resumed;
    final resume = {
      ..._subjects.first,
      'episodeId': 16,
      'episodeSort': 6,
      'positionSeconds': 480,
      'durationSeconds': 1440,
    };
    await _show(
      tester,
      _home(
        feedback: feedback,
        resumable: [resume],
        onResume: (item) => resumed = item,
      ),
    );
    expect(find.text('继续播放'), findsOneWidget);
    expect(find.text('第 6 话 · 剩余 16 分钟'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(1 / 3, .001),
    );
    await tester.tap(find.text('继续第 6 话'));
    expect(resumed, same(resume));

    await _show(
      tester,
      _home(
        feedback: feedback,
        resumable: [
          {...resume, 'episodeSort': null},
        ],
        onResume: (_) {},
      ),
    );
    expect(find.text('继续观看'), findsOneWidget);
    expect(find.text('继续第 6 话'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow featured content handles large text and reduced motion', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final feedback = ActionFeedback();
    addTearDown(feedback.dispose);
    await _show(
      tester,
      _home(
        feedback: feedback,
        trending: [
          {
            ..._subjects.first,
            'nameCn': '这是一部有很长很长名称的番剧也仍然需要能够显示和切换',
            'summary': '这是一段有很长内容的真实简介，需要限制行数而不是让控件溢出。' * 3,
          },
          ..._subjects.skip(1),
        ],
      ),
      size: const Size(390, 900),
      dark: true,
      reduceMotion: true,
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('下一项精选'));
    await tester.pump();
    expect(find.text('第二部作品').hitTestable(), findsOneWidget);
    expect(find.text('2023 秋').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
