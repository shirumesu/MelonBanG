import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/ui/core/action_feedback.dart';
import 'package:melonbang/ui/core/app_chrome.dart';
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
      await tester.tap(find.text('刷新'));
      await tester.pump();
      expect(find.text('刷新中…'), findsOneWidget);
      run();
      expect(calls, 1);
      request.complete(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('已更新'), findsOneWidget);
      expect(find.textContaining('刚刚'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
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
      expect(find.text('仍有 2 项修改待上传'), findsNothing);
      request.complete(null);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
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
                  onToggleSidebar: () => sidebar++,
                  onToggleTheme: () => themes++,
                ),
                AppHeader(route: 'tracking', search: search, onSearch: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('返回探索'));
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
