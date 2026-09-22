import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/ui/core/action_feedback.dart';
import 'package:melonbang/ui/core/page_widgets.dart';
import 'package:melonbang/ui/core/subject_posters.dart';
import 'package:melonbang/ui/core/theme.dart';
import 'package:melonbang/ui/discovery/discovery_pages.dart';
import 'package:melonbang/ui/tracking/subject_page.dart';
import 'package:melonbang/ui/tracking/tracking_page.dart';

void main() {
  testWidgets('search distinguishes loading, failure and no matches', (
    tester,
  ) async {
    var retries = 0;
    Future<void> show({bool busy = false, String? error}) => tester.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(
          body: SearchPage(
            results: const [],
            busy: busy,
            error: error,
            onRetry: () => retries++,
            onOpenSubject: (_) {},
          ),
        ),
      ),
    );
    await show(busy: true);
    expect(find.byType(PosterPlaceholders), findsOneWidget);
    expect(find.text('没有找到匹配的番剧'), findsNothing);
    await show(error: '搜索暂时失败，请重试。');
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    await show();
    expect(find.text('没有找到匹配的番剧'), findsOneWidget);
  });

  testWidgets('collection filters survive departure and can be cleared', (
    tester,
  ) async {
    final storage = PageStorageBucket();
    final feedback = ActionFeedback();
    addTearDown(feedback.dispose);
    Widget page() => TrackingPage(
      collection: const [
        {
          'subjectId': 1,
          'name': 'Alpha',
          'status': 'watching',
          'watchedEpisodes': 3,
        },
        {
          'subjectId': 2,
          'name': 'Beta',
          'status': 'watching',
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
    );
    Future<void> show(Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(
          body: PageStorage(bucket: storage, child: child),
        ),
      ),
    );
    await show(page());
    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.tap(find.text('有进度'));
    await tester.pumpAndSettle();
    await show(const SizedBox());
    await show(page());
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Alpha',
    );
    expect(find.text('Beta'), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '有进度'))
          .selected,
      isTrue,
    );
    await tester.enterText(find.byType(TextField), 'unknown');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('清除筛选'));
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('finished series offers replay and counts watched episodes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(
          body: SubjectPage(
            subject: const {
              'subjectId': 1,
              'name': 'A series',
              'episodeTotal': 2,
              'episodes': [
                {'episodeId': 10, 'sort': 1, 'status': 'watched'},
                {'episodeId': 11, 'sort': 2, 'status': 'watched'},
              ],
            },
            onUpdateTracking: (_) {},
            onFindResources: (_) {},
            onOpenEpisode: (_) {},
            onPlayEpisode: (_) {},
            onOpenSubject: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('重看 EP1'), findsOneWidget);
    expect(find.text('已看 2 话 / 预定全 2 话'), findsOneWidget);
    expect(find.byType(MelonPanel), findsWidgets);
  });
}
