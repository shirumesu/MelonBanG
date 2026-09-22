import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/ui/acquisition/downloads_page.dart';
import 'package:melonbang/ui/core/theme.dart';
import 'package:melonbang/ui/core/subject_posters.dart';
import 'package:melonbang/ui/core/action_feedback.dart';
import 'package:melonbang/ui/discovery/discovery_pages.dart';
import 'package:melonbang/ui/tracking/subject_page.dart';
import 'package:melonbang/ui/tracking/tracking_page.dart';

Future<void> showPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1360, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(false),
      home: Scaffold(body: page),
    ),
  );
}

void main() {
  testWidgets(
    'horizontal posters page both ways and update their boundaries',
    (tester) async {
      for (final ranked in [false, true]) {
        Json? opened;
        Widget posters(int count) => Center(
          child: SizedBox(
            width: 430,
            child: SubjectPosters(
              items: List.generate(
                count,
                (i) => {'subjectId': i, 'name': 'Poster $i'},
              ),
              horizontal: true,
              ranked: ranked,
              onOpen: (item) => opened = item,
            ),
          ),
        );
        await showPage(tester, posters(10));
        await tester.pumpAndSettle();
        Finder arrow(String tooltip) => find.byTooltip(tooltip);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        expect(arrow('向左翻页'), findsNothing);
        expect(arrow('向右翻页').hitTestable(), findsNothing);
        final right = tester.getCenter(arrow('向右翻页'));
        await mouse.moveTo(right - const Offset(40, 0));
        await tester.pumpAndSettle();
        expect(arrow('向右翻页').hitTestable(), findsOneWidget);
        await mouse.moveTo(tester.getCenter(find.byType(SubjectPosters)));
        await tester.pumpAndSettle();
        expect(arrow('向右翻页').hitTestable(), findsNothing);
        await mouse.moveTo(right);
        await tester.pumpAndSettle();
        await tester.tap(arrow('向右翻页'));
        await tester.pumpAndSettle();
        expect(arrow('向左翻页').hitTestable(), findsNothing);
        expect(opened, isNull);
        for (var i = 0; i < 8 && arrow('向右翻页').evaluate().isNotEmpty; i++) {
          await tester.tap(arrow('向右翻页'));
          await tester.pumpAndSettle();
        }
        expect(arrow('向右翻页'), findsNothing);
        expect(find.text('Poster 9').hitTestable(), findsOneWidget);
        await mouse.moveTo(tester.getCenter(arrow('向左翻页')));
        await tester.pumpAndSettle();
        await tester.tap(arrow('向左翻页'));
        await tester.pumpAndSettle();
        expect(arrow('向右翻页').hitTestable(), findsNothing);
        await mouse.removePointer();
        await showPage(tester, posters(1));
        await tester.pumpAndSettle();
        expect(find.byTooltip('向左翻页'), findsNothing);
        expect(find.byTooltip('向右翻页'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'calendar days support keyboard selection and opening a result',
    (tester) async {
      Json? opened;
      await showPage(
        tester,
        CalendarPage(
          calendar: [
            {
              'weekday': {'id': 1},
              'items': [
                {'subjectId': 1, 'name': 'Monday title'},
              ],
            },
            {
              'weekday': {'id': 2},
              'items': [
                {'subjectId': 2, 'name': 'Tuesday title'},
              ],
            },
          ],
          onRetry: () {},
          onOpenSubject: (item) => opened = item,
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, '周一'));
      await tester.pumpAndSettle();
      expect(find.text('Monday title'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Monday title'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Monday title'), findsNothing);
      expect(find.text('Tuesday title'), findsOneWidget);
      await tester.tap(find.text('Tuesday title'));
      expect(opened?['subjectId'], 2);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  testWidgets('collection filters and selections retain subject identity', (
    tester,
  ) async {
    Json? selected;
    String? filter;
    var syncs = 0;
    await showPage(
      tester,
      TrackingPage(
        collection: [
          {'subjectId': 7, 'name': 'Watching title', 'status': 'watching'},
          {'subjectId': 8, 'name': 'Finished title', 'status': 'completed'},
        ],
        collectionFilter: 'watching',
        sync: {'pendingMutationCount': 2},
        onFilterChanged: (value) => filter = value,
        onSync: () => syncs++,
        feedback: ActionFeedback(),
        signedIn: true,
        onSignIn: () {},
        onOpenSubject: (value) => selected = value,
      ),
    );
    expect(find.text('Finished title'), findsNothing);
    expect(find.text('2 项修改等待同步'), findsOneWidget);
    await tester.tap(find.text('Watching title'));
    expect(selected?['subjectId'], 7);
    await tester.tap(find.text('看过 1'));
    expect(filter, 'completed');
    await tester.tap(find.text('同步收藏'));
    expect(syncs, 1);
  });

  testWidgets(
    'download actions keep task and explicit file selection distinct',
    (tester) async {
      final plays = <(String, String?)>[];
      Json? paused;
      await showPage(
        tester,
        DownloadsPage(
          downloads: {
            'tasks': [
              {
                'id': 'pending',
                'title': 'Incomplete',
                'status': 'paused',
                'progress': .3,
              },
              {
                'id': 'done',
                'title': 'Complete',
                'status': 'completed',
                'progress': 1,
              },
            ],
            'files': [
              {
                'id': 'a',
                'downloadId': 'done',
                'name': 'Episode A',
                'mediaKind': 'video',
                'progress': 1,
              },
              {
                'id': 'b',
                'downloadId': 'done',
                'name': 'Episode B',
                'mediaKind': 'video',
                'progress': 1,
              },
            ],
          },
          onAddMagnet: () {},
          onAddTorrent: () {},
          onOpenVideo: () {},
          onExplore: () {},
          onTogglePause: (value) => paused = value,
          onRemove: (_) {},
          onStopSeeding: (_) {},
          onPlay: (id, fileId) => plays.add((id, fileId)),
        ),
      );
      expect(find.text('播放'), findsNothing);
      await tester.tap(find.byTooltip('暂停 / 继续下载').first);
      expect(paused?['id'], 'pending');
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('播放此文件').last);
      expect(plays, [('done', 'b')]);
    },
  );

  testWidgets(
    'subject chapter actions pass the selected episode and mutation',
    (tester) async {
      Json? mutation, local, resources, play;
      await showPage(
        tester,
        SubjectPage(
          subject: {
            'subjectId': 12,
            'name': 'Subject',
            'episodes': [
              {
                'episodeId': 120,
                'name': 'Episode',
                'sort': 1,
                'status': 'watched',
              },
            ],
          },
          onUpdateTracking: (value) => mutation = value,
          onFindResources: (value) => resources = value,
          onOpenEpisode: (value) => local = value,
          onPlayEpisode: (value) => play = value,
          onOpenSubject: (_) {},
        ),
      );
      Future<void> openEpisodes() async {
        await tester.tap(find.text('选集'));
        await tester.pumpAndSettle();
      }

      await openEpisodes();
      await tester.tap(find.byTooltip('标记已看 / 未看'));
      expect(mutation, {
        'kind': 'episodeCollection',
        'subjectId': 12,
        'episodeId': 120,
        'status': 'unwatched',
      });
      await tester.tap(find.byTooltip('打开本地文件并关联此话'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await openEpisodes();
      await tester.tap(find.byTooltip('搜索此话资源'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await openEpisodes();
      await tester.tap(find.byTooltip('播放已缓存视频'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(local?['episodeId'], 120);
      expect(resources?['episodeId'], 120);
      expect(play?['episodeId'], 120);
    },
  );
}
