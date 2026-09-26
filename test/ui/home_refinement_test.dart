import 'package:flutter/material.dart';
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
  testWidgets('seasonal ranking leads home and opens the selected work', (
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
    expect(find.text('本季热度'), findsOneWidget);
    expect(find.text('热门与精选'), findsNothing);
    expect(find.byTooltip('下一项精选'), findsNothing);
    expect(
      tester.getTopLeft(find.text('本季热度')).dy,
      lessThan(tester.getTopLeft(find.text('正在追')).dy),
    );
    expect(find.text('#1').hitTestable(), findsOneWidget);
    expect(find.text('#3').hitTestable(), findsOneWidget);
    expect(find.text('2024 WINTER').hitTestable(), findsOneWidget);
    await tester.tap(find.text('第二部作品'));
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

  testWidgets('narrow ranking handles large text and reduced motion', (
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
    await tester.drag(
      find.byKey(const ValueKey('trending-posters')),
      const Offset(-200, 0),
    );
    await tester.pump();
    expect(find.text('第二部作品').hitTestable(), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
