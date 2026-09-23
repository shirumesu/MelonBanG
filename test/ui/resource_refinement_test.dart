import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/ui/acquisition/resource_widgets.dart';
import 'package:melonbang/ui/acquisition/resources_page.dart';
import 'package:melonbang/ui/core/selection_controls.dart';
import 'package:melonbang/ui/core/theme.dart';

void main() {
  testWidgets(
    'unknown annotations are opt-in and originals survive filtering and enrichment',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final query = TextEditingController(text: 'Anime');
      addTearDown(query.dispose);
      final candidates = <Json>[
        {
          'candidateId': 'known',
          'title': '[A & B] Anime [01][1080p]',
          'releaseGroups': ['B'],
        },
        {
          'candidateId': 'unknown',
          'title': '[Another] Anime [01][HEVC]',
          'sizeBytes': 1,
          'episodeId': 909,
        },
        {
          'candidateId': 'low',
          'title': '[B] Anime [01][720p]',
          'releaseGroups': ['B'],
        },
      ];
      late StateSetter update;
      Json? downloaded;
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
                  resourceEpisode: 909,
                  providers: const [],
                  candidates: List.of(candidates),
                  busy: false,
                  onSearch: (_, _) async {},
                  onDownload: (candidate) async => downloaded = candidate,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.byType(ResourceResultRow), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('resource-original:unknown')));
      await tester.pumpAndSettle();
      expect(find.text('[Another] Anime [01][HEVC]'), findsOneWidget);
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
      expect(find.widgetWithText(MenuItemButton, 'A'), findsNothing);
      await tester.tap(find.widgetWithText(MenuItemButton, 'B'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceResultRow), findsOneWidget);
      expect(find.text('[Another] Anime [01][HEVC]'), findsNothing);
      await tester.tap(find.text('含未确认'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceResultRow), findsNWidgets(2));
      expect(find.text('[Another] Anime [01][HEVC]'), findsOneWidget);
      update(
        () => candidates[1] = {
          ...candidates[1],
          'releaseGroups': ['B'],
          'sizeLabel': '783.5 MiB',
        },
      );
      await tester.pumpAndSettle();
      expect(find.byType(ResourceResultRow), findsNWidgets(2));
      expect(find.text('783.5 MiB'), findsOneWidget);
      expect(find.text('[Another] Anime [01][HEVC]'), findsOneWidget);
      final unknownRow = find.ancestor(
        of: find.byKey(const ValueKey('resource-original:unknown')),
        matching: find.byType(ResourceResultRow),
      );
      await tester.tap(
        find.descendant(of: unknownRow, matching: find.byTooltip('下载')),
      );
      await tester.pumpAndSettle();
      expect(downloaded, same(candidates[1]));
      expect(downloaded!['episodeId'], 909);
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.byType(ResourceResultRow), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact results fit narrow windows and long lists build only visible rows',
    (tester) async {
      tester.view.physicalSize = const Size(680, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final query = TextEditingController(text: '葬送的芙莉莲');
      addTearDown(query.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
            body: ResourcesPage(
              subject: const {'subjectId': 42, 'nameCn': '葬送的芙莉莲'},
              resourceSearch: query,
              resourceEpisode: null,
              providers: const [],
              busy: false,
              candidates: List.generate(
                150,
                (i) => {
                  'candidateId': '$i',
                  'title': '[千夏字幕组][葬送的芙莉莲_Sousou no Frieren][第39-38话][1080p_AVC][简体][合集]',
                  'releaseGroups': ['千夏字幕组'],
                  'sizeBytes': 1,
                },
              ),
              onSearch: (_, _) async {},
              onDownload: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('39–38 范围倒置，集数待确认'), findsWidgets);
      expect(find.textContaining('来源分组：千夏字幕组 · 大小未知'), findsWidgets);
      expect(find.byType(ResourceResultRow).evaluate().length, lessThan(15));
      await tester.tap(find.byKey(const ValueKey('resource-original:0')));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -1300));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceResultRow).evaluate().length, lessThan(15));
      expect(tester.takeException(), isNull);
    },
  );
}
