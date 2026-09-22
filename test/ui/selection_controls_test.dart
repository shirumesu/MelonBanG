import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/ui/core/selection_controls.dart';
import 'package:melonbang/ui/core/theme.dart';

const _options = {
  'wish': '想看',
  'watching': '在看',
  'completed': '看过',
  'on_hold': '搁置',
  'dropped': '抛弃',
};

Future<void> _showControl(
  WidgetTester tester, {
  required List<String> changes,
  bool reduceMotion = false,
  bool enabled = true,
  TextDirection direction = TextDirection.ltr,
}) async {
  var selected = 'watching';
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(false),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 450,
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MelonSegmentedControl<String>(
                    options: _options,
                    value: selected,
                    allowDrag: true,
                    semanticLabel: '收藏状态',
                    onChanged: enabled
                        ? (value) {
                            changes.add(value);
                            setState(() => selected = value);
                          }
                        : null,
                  ),
                  Text('已选择：${_options[selected]}'),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('clicking selects once and preserves the current selection', (
    tester,
  ) async {
    final changes = <String>[];
    await _showControl(tester, changes: changes);
    await tester.tap(find.text('想看'));
    await tester.pumpAndSettle();
    expect(changes, ['wish']);
    expect(find.text('已选择：想看'), findsOneWidget);
    await tester.tap(find.text('想看'));
    await tester.pumpAndSettle();
    expect(changes, ['wish']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dragging previews intermediate options and commits only on release',
    (tester) async {
      final changes = <String>[];
      await _showControl(tester, changes: changes);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('在看')),
      );
      await gesture.moveTo(tester.getCenter(find.text('看过')));
      await tester.pump();
      expect(changes, isEmpty);
      await gesture.moveTo(tester.getCenter(find.text('搁置')));
      await tester.pump();
      expect(changes, isEmpty);
      expect(find.text('已选择：在看'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, ['on_hold']);
      expect(find.text('已选择：搁置'), findsOneWidget);

      final cancelled = await tester.startGesture(
        tester.getCenter(find.text('搁置')),
      );
      await cancelled.moveTo(tester.getCenter(find.text('想看')));
      await tester.pump();
      await cancelled.moveBy(const Offset(0, 100));
      await tester.pump();
      await cancelled.up();
      await tester.pumpAndSettle();
      expect(changes, ['on_hold']);
      expect(find.text('已选择：搁置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'arrow keys move focus while Enter commits the focused state',
    (tester) async {
      final changes = <String>[];
      await _showControl(tester, changes: changes);
      Focus.of(tester.element(find.text('在看'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(changes, isEmpty);
      expect(find.text('已选择：在看'), findsOneWidget);
      expect(Focus.of(tester.element(find.text('看过'))).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, ['completed']);
      expect(find.text('已选择：看过'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(changes, ['completed']);
      expect(Focus.of(tester.element(find.text('想看'))).hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'reduced motion settles immediately and disabled controls do not save',
    (tester) async {
      final changes = <String>[];
      await _showControl(tester, changes: changes, reduceMotion: true);
      await tester.tap(find.text('抛弃'));
      await tester.pump();
      expect(changes, ['dropped']);
      expect(find.text('已选择：抛弃'), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const ValueKey('selection-indicator'))).dx,
        closeTo(tester.getCenter(find.text('抛弃')).dx, .01),
      );

      await _showControl(tester, changes: changes, enabled: false);
      await tester.tap(find.text('想看'));
      await tester.dragFrom(
        tester.getCenter(find.text('在看')),
        const Offset(170, 0),
      );
      await tester.pumpAndSettle();
      expect(changes, ['dropped']);
      expect(find.text('已选择：在看'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'long choice labels fit narrow dark controls and remain complete in menus',
    (tester) async {
      tester.view.physicalSize = const Size(320, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const first = '某个字幕组与合作发布团队 · 简体繁体双字幕版本';
      const second = '另一个很长的联合发布分组名称 · 内封外挂字幕及高画质版本';
      const options = {'first-group': first, 'second-group': second};
      var selected = 'first-group';
      final changes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: StatefulBuilder(
                  builder: (context, setState) => MelonChoiceMenu<String>(
                    options: options,
                    value: selected,
                    icon: Icons.group_outlined,
                    onSelected: (value) {
                      changes.add(value);
                      setState(() => selected = value);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(first))
            .didExceedMaxLines,
        isTrue,
      );
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final option = find.widgetWithText(MenuItemButton, second);
      final label = find.descendant(of: option, matching: find.text(second));
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
      final rect = tester.getRect(label);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(changes, ['second-group']);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(find.widgetWithText(OutlinedButton, second), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
