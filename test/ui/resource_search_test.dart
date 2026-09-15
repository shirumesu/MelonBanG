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
                  busy: true,
                  onSearch: (n, e) {
                    names = n;
                    episode = e;
                  },
                  onDownload: (c) => downloaded = c['candidateId'],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('下载').first);
      expect(downloaded, 'first');
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
      expect(find.byTooltip('下载'), findsNWidgets(2));
      await tester.enterText(find.widgetWithText(TextField, '字幕组 / 联合发布'), 'B');
      await tester.pump();
      expect(find.byTooltip('下载'), findsOneWidget);
      expect(find.text('[A & B] Anime [01][1080p]'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '筛选结果标题'), '720p');
      await tester.pump();
      expect(find.byTooltip('下载'), findsNothing);
      await tester.tap(find.text('清除'));
      await tester.pump();
      expect(find.byTooltip('下载'), findsNWidgets(2));
      await tester.enterText(find.widgetWithText(TextField, '集数关键词'), 'S01E01');
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      expect(names, ['中文名', '日本語']);
      expect(episode, 'S01E01');
      expect(tester.takeException(), isNull);
    },
  );
}
