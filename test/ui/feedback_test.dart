import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/ui/core/action_feedback.dart';
import 'package:melonbang/ui/core/app_chrome.dart';
import 'package:melonbang/ui/core/motion.dart';
import 'package:melonbang/ui/core/page_widgets.dart';
import 'package:melonbang/ui/core/subject_posters.dart';
import 'package:melonbang/ui/core/theme.dart';

void main() {
  testWidgets(
    'feedback blocks duplicate requests and leaves no success caption',
    (tester) async {
      final feedback = ActionFeedback();
      addTearDown(feedback.dispose);
      var request = Completer<String?>();
      var calls = 0;
      void run() => feedback.run(() {
        calls++;
        return request.future;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
            body: Column(
              children: [
                FeedbackButton(
                  feedback: feedback,
                  label: '刷新',
                  runningLabel: '刷新中…',
                  successLabel: '已更新',
                  icon: Icons.refresh,
                  onPressed: run,
                ),
                FeedbackIssue(feedback: feedback, onRetry: run),
              ],
            ),
          ),
        ),
      );
      final button = find.descendant(
        of: find.byType(FeedbackButton),
        matching: find.byType(TextButton),
      );
      final initialSize = tester.getSize(button);
      await tester.tap(find.text('刷新'));
      await tester.pump();
      expect(find.text('刷新中…'), findsOneWidget);
      expect(tester.getSize(button), initialSize);
      run();
      expect(calls, 1);
      request.complete(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('已更新'), findsOneWidget);
      expect(tester.getSize(button), initialSize);
      expect(find.textContaining('刚刚'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('刷新'), findsOneWidget);
      expect(find.text('已更新'), findsNothing);

      request = Completer<String?>();
      await tester.tap(find.text('刷新'));
      request.complete('仍有 2 项修改待上传');
      await tester.pumpAndSettle();
      expect(find.text('仍有 2 项修改待上传'), findsOneWidget);
      expect(find.text('已更新'), findsNothing);
      request = Completer<String?>();
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(find.text('仍有 2 项修改待上传').hitTestable(), findsNothing);
      request.complete(null);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('reveal reverses in place and preserves hidden control state', (
    tester,
  ) async {
    var visible = false;
    late StateSetter update;
    final focus = FocusNode();
    final controller = TextEditingController();
    addTearDown(focus.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MotionReveal(
                      visible: visible,
                      axis: Axis.horizontal,
                      child: SizedBox(
                        width: 200,
                        child: TextField(
                          focusNode: focus,
                          controller: controller,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    final reveal = find.byType(MotionReveal);
    expect(tester.getSize(reveal).width, 0);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);

    update(() => visible = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final intermediateWidth = tester.getSize(reveal).width;
    expect(intermediateWidth, inExclusiveRange(0, 200));
    update(() => visible = false);
    await tester.pump();
    expect(tester.getSize(reveal).width, intermediateWidth);
    await tester.pumpAndSettle();
    expect(tester.getSize(reveal).width, 0);

    update(() => visible = true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留搜索');
    update(() => visible = false);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(find.byType(TextField).hitTestable(), findsNothing);
    update(() => visible = true);
    await tester.pumpAndSettle();
    expect(find.text('保留搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion reveals immediately and uses static busy feedback',
    (tester) async {
      final feedback = ActionFeedback();
      addTearDown(feedback.dispose);
      final request = Completer<String?>();
      var visible = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Scaffold(
                  body: Column(
                    children: [
                      MotionReveal(
                        visible: visible,
                        child: const SizedBox(height: 80, child: Text('展开内容')),
                      ),
                      FeedbackButton(
                        feedback: feedback,
                        label: '刷新',
                        runningLabel: '刷新中…',
                        successLabel: '已更新',
                        icon: Icons.refresh,
                        onPressed: () => feedback.run(() => request.future),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      update(() => visible = true);
      await tester.pump();
      expect(tester.getSize(find.byType(MotionReveal)).height, 80);
      await tester.tap(find.text('刷新'));
      await tester.pump();
      expect(find.text('刷新中…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      request.complete(null);
      await tester.pump();
      expect(find.text('已更新'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'poster rails restore their own scroll positions after returning',
    (tester) async {
      final storage = PageStorageBucket();
      var showingPosters = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: PageStorage(
                  bucket: storage,
                  child: showingPosters
                      ? Center(
                          child: SizedBox(
                            width: 430,
                            child: Column(
                              children: [
                                for (final group in ['trending', 'watching'])
                                  SubjectPosters(
                                    key: ValueKey(group),
                                    horizontal: true,
                                    items: List.generate(
                                      8,
                                      (i) => {
                                        'subjectId': i,
                                        'name': '$group $i',
                                      },
                                    ),
                                    onOpen: (_) {},
                                  ),
                              ],
                            ),
                          ),
                        )
                      : const Text('详情'),
                ),
              );
            },
          ),
        ),
      );
      Finder scrollable(String group) => find.descendant(
        of: find.byKey(ValueKey(group)),
        matching: find.byType(Scrollable),
      );
      double offset(String group) =>
          tester.state<ScrollableState>(scrollable(group)).position.pixels;
      await tester.drag(scrollable('trending'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      final previous = offset('trending');
      expect(previous, greaterThan(0));
      expect(offset('watching'), 0);
      update(() => showingPosters = false);
      await tester.pump();
      update(() => showingPosters = true);
      await tester.pumpAndSettle();
      expect(offset('trending'), previous);
      expect(offset('watching'), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'horizontal input scrolling does not replace the page scroll position',
    (tester) async {
      final storage = PageStorageBucket();
      final search = TextEditingController();
      addTearDown(search.dispose);
      var showingPage = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: PageStorage(
                  bucket: storage,
                  child: showingPage
                      ? PageScroll(
                          key: const PageStorageKey('search-form'),
                          children: [
                            const SizedBox(height: 400),
                            AppHeader(
                              route: 'home',
                              search: search,
                              onSearch: () {},
                            ),
                            const SizedBox(height: 1200),
                          ],
                        )
                      : const Text('另一页'),
                ),
              );
            },
          ),
        ),
      );
      Finder pageScroll() => find
          .descendant(
            of: find.byType(PageScroll),
            matching: find.byType(Scrollable),
          )
          .first;
      ScrollPosition pagePosition() =>
          tester.state<ScrollableState>(pageScroll()).position;
      pagePosition().jumpTo(220);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '长搜索文字' * 60);
      await tester.pumpAndSettle();
      final input = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(TextField),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(input.maxScrollExtent, greaterThan(500));
      final verticalOffset = pagePosition().pixels;
      input.jumpTo(input.maxScrollExtent / 2);
      await tester.pumpAndSettle();
      update(() => showingPage = false);
      await tester.pump();
      update(() => showingPage = true);
      await tester.pumpAndSettle();
      expect(pagePosition().pixels, verticalOffset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop toolbar retains platform controls and centers search text',
    (tester) async {
      tester.view.physicalSize = const Size(960, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final search = TextEditingController();
      addTearDown(search.dispose);
      var backs = 0, sidebar = 0, themes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
            body: Column(
              children: [
                AppTitleBar(
                  route: 'tracking',
                  dark: false,
                  sidebarVisible: true,
                  onBack: () => backs++,
                  backLabel: '返回追番',
                  onToggleSidebar: () => sidebar++,
                  onToggleTheme: () => themes++,
                ),
                AppHeader(route: 'tracking', search: search, onSearch: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('返回追番'));
      await tester.tap(find.byTooltip('收起侧栏'));
      await tester.tap(find.byTooltip('切换主题'));
      expect([backs, sidebar, themes], [1, 1, 1]);
      final platform = Theme.of(tester.element(find.byType(AppTitleBar)))
          .platform;
      expect(
        find.byTooltip('关闭窗口'),
        platform == TargetPlatform.windows ? findsOneWidget : findsNothing,
      );
      expect(
        find.byTooltip('最小化'),
        platform == TargetPlatform.windows ? findsOneWidget : findsNothing,
      );
      expect(
        find.byTooltip('最大化 / 还原'),
        platform == TargetPlatform.windows ? findsOneWidget : findsNothing,
      );
      final field = tester.getRect(find.byType(TextField));
      final hint = tester.getRect(find.text('搜索番剧名称…'));
      expect(field.height, 40);
      expect((field.center.dy - hint.center.dy).abs(), lessThan(2));
      await tester.enterText(find.byType(TextField), '搜索测试');
      await tester.pump();
      final editable = tester.getRect(find.byType(EditableText));
      expect((field.center.dy - editable.center.dy).abs(), lessThan(2));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
}
