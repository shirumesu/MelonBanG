import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/ui/core/action_feedback.dart';
import 'package:melonbang/ui/core/selection_controls.dart';
import 'package:melonbang/ui/core/theme.dart';
import 'package:melonbang/ui/tracking/subject_page.dart';
import 'package:melonbang/ui/tracking/tracking_page.dart';

Json sample({String? status = 'watching', int episodes = 5}) => {
  'subjectId': 42,
  'nameCn': '一部有观看进度的番剧',
  'name': 'Series',
  'airDate': '2023-10-01',
  'platform': 'TV',
  'score': 8.5,
  'episodeTotal': episodes,
  'collection': {'status': status},
  'summary': '一段介绍作品的简介。',
  'episodes': List.generate(
    episodes,
    (i) => {
      'episodeId': 100 + i,
      'sort': i + 1,
      'name': 'Chapter ${i + 1}',
      'status': i == 0 ? 'watched' : 'unwatched',
    },
  ),
};

Future<void> show(
  WidgetTester tester,
  Widget page, {
  double width = 1100,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(false),
      home: Scaffold(body: page),
    ),
  );
  await tester.pumpAndSettle();
}

SubjectPage detail({
  Json? subject,
  Future<void> Function(Json)? save,
  ValueChanged<Json>? play,
  ValueChanged<Json?>? resources,
  Json? resume,
  Set<int>? cached,
}) => SubjectPage(
  subject: subject ?? sample(),
  onUpdateTracking: (_) {},
  onSaveTracking: save,
  onFindResources: resources ?? (_) {},
  onOpenEpisode: (_) {},
  onPlayEpisode: play ?? (_) {},
  onOpenSubject: (_) {},
  resume: resume,
  cachedEpisodeIds: cached,
);

void main() {
  testWidgets(
    'collection save waits, prevents duplicate writes and can undo without editing chapters',
    (tester) async {
      final writes = <Json>[];
      final pending = Completer<void>();
      await show(
        tester,
        detail(
          save: (mutation) async {
            writes.add(mutation);
            if (writes.length == 1) await pending.future;
          },
        ),
      );
      await tester.tap(find.text('看过'));
      await tester.pump();
      expect(find.text('正在保存…'), findsOneWidget);
      await tester.tap(find.text('想看'));
      expect(writes, hasLength(1));
      expect(writes.single, {
        'kind': 'subjectCollection',
        'subjectId': 42,
        'status': 'completed',
      });
      expect(find.text('已看 1 话 / 预定全 5 话'), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('已保存 · 看过'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(writes.last['status'], 'watching');
      expect(
        writes.every((write) => write['kind'] == 'subjectCollection'),
        isTrue,
      );
      expect(find.text('已撤销'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed collection writes restore selection and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    await show(
      tester,
      detail(
        save: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('offline');
        },
      ),
    );
    await tester.tap(find.text('想看'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(
      tester
          .widget<MelonSegmentedControl<String>>(
            find.byType(MelonSegmentedControl<String>),
          )
          .value,
      'watching',
    );
    await tester.tap(find.text('想看'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('已保存 · 想看'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'first collection does not offer an unsupported null-status undo',
    (tester) async {
      await show(
        tester,
        detail(subject: sample(status: null), save: (_) async {}),
      );
      await tester.tap(find.text('在看'));
      await tester.pumpAndSettle();
      expect(find.text('已加入收藏 · 在看'), findsOneWidget);
      expect(find.text('撤销'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'resume and grid actions use actual episode identities and cache availability',
    (tester) async {
      Json? played, searched;
      await show(
        tester,
        detail(
          play: (episode) => played = episode,
          resources: (episode) => searched = episode,
          resume: {
            'subjectId': 42,
            'episodeId': 103,
            'positionSeconds': 157,
            'completed': false,
          },
          cached: {103},
        ),
      );
      await tester.tap(find.text('继续播放 EP4'));
      expect(played?['episodeId'], 103);
      expect(find.text('续播 2:37 · 已缓存'), findsOneWidget);
      await tester.tap(find.byTooltip('查找资源 EP3'));
      expect(searched?['episodeId'], 102);
      await tester.tap(find.text('选集'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '5'));
      await tester.pumpAndSettle();
      expect(find.text('EP5 · Chapter 5'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '播放已缓存视频'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('搜索此话资源'));
      await tester.pumpAndSettle();
      expect(searched?['episodeId'], 104);
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets(
    'chapter write failures remain visible in the picker and do not alter collection',
    (tester) async {
      final writes = <Json>[];
      await show(
        tester,
        detail(
          save: (mutation) async {
            writes.add(mutation);
            throw StateError('could not save chapter');
          },
        ),
      );
      await tester.tap(find.text('选集'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('标记已看 / 未看'));
      await tester.pumpAndSettle();
      expect(writes.single, {
        'kind': 'episodeCollection',
        'subjectId': 42,
        'episodeId': 101,
        'status': 'watched',
      });
      expect(find.textContaining('could not save chapter'), findsOneWidget);
      expect(find.text('未看'), findsWidgets);
      await tester.tap(find.byTooltip('关闭选集'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MelonSegmentedControl<String>>(
              find.byType(MelonSegmentedControl<String>),
            )
            .value,
        'watching',
      );
    },
  );

  testWidgets(
    'character and cast are distinct and important staff merge their roles',
    (tester) async {
      await show(
        tester,
        detail(
          subject: {
            ...sample(),
            'characters': [
              {
                'characterId': 1,
                'name': 'A character',
                'role': '主角',
                'actors': [
                  {'personId': 2, 'name': 'An actor'},
                ],
              },
            ],
            'staff': [
              for (var i = 0; i < 9; i++)
                {'personId': 10 + i, 'name': 'Illustrator $i', 'role': '插画'},
              {
                'personId': 100,
                'name': 'An author',
                'role': '原作',
                'imageUrl': '',
              },
              {'personId': 101, 'name': 'A director', 'role': '导演'},
              {'personId': 101, 'name': 'A director', 'role': '脚本'},
            ],
          },
        ),
      );
      await tester.scrollUntilVisible(
        find.text('制作团队'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('A character'), findsOneWidget);
      expect(find.text('CV An actor'), findsOneWidget);
      expect(find.text('An author'), findsOneWidget);
      expect(find.text('A director'), findsOneWidget);
      expect(find.text('导演 · 脚本'), findsOneWidget);
      expect(find.text('全部 11 位'), findsOneWidget);
      expect(find.byTooltip('暂无头像'), findsWidgets);
    },
  );

  testWidgets('detail and tracking controls remain usable at narrow width', (
    tester,
  ) async {
    await show(tester, detail(), width: 320);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('选集'));
    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭选集'));
    await tester.pumpAndSettle();
    await show(
      tester,
      TrackingPage(
        collection: const [],
        collectionFilter: 'watching',
        sync: const {},
        onFilterChanged: (_) {},
        onSync: () {},
        feedback: ActionFeedback(),
        signedIn: false,
        onSignIn: () {},
        onOpenSubject: (_) {},
      ),
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'tracking menu sorts real items and quick filters keep query state',
    (tester) async {
      final feedback = ActionFeedback();
      addTearDown(feedback.dispose);
      await show(
        tester,
        TrackingPage(
          collection: const [
            {
              'subjectId': 1,
              'name': 'Alpha',
              'status': 'watching',
              'userScore': 4,
              'watchedEpisodes': 1,
            },
            {
              'subjectId': 2,
              'name': 'Beta',
              'status': 'watching',
              'userScore': 9,
              'watchedEpisodes': 0,
            },
          ],
          collectionFilter: 'watching',
          sync: const {},
          onFilterChanged: (_) {},
          onSync: () {},
          feedback: feedback,
          signedIn: false,
          onSignIn: () {},
          onOpenSubject: (_) {},
        ),
      );
      expect(
        tester.getTopLeft(find.text('Alpha')).dx,
        lessThan(tester.getTopLeft(find.text('Beta')).dx),
      );
      await tester.tap(find.byTooltip('追番排序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按我的评分'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Beta')).dx,
        lessThan(tester.getTopLeft(find.text('Alpha')).dx),
      );
      await tester.tap(find.text('有进度'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('当前筛选下没有收藏条目'), findsOneWidget);
      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      expect(find.text('Beta'), findsOneWidget);
    },
  );
  testWidgets(
    'details disclosure keeps a separate state from the page scroll offset',
    (tester) async {
      await show(
        tester,
        detail(
          subject: {
            ...sample(),
            'summary': List.filled(25, 'A longer description.').join('\n'),
            'infoBox': [
              {'key': '播放日期', 'value': '2023-10-01'},
            ],
            'collectionStats': {'watching': 30, 'completed': 10},
          },
        ),
      );
      await tester.scrollUntilVisible(
        find.text('作品资料与收藏统计'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('作品资料与收藏统计'));
      await tester.pumpAndSettle();
      expect(find.text('播放日期：2023-10-01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
