import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/ui/acquisition/downloads_page.dart';
import 'package:melonbang/ui/core/page_widgets.dart';
import 'package:melonbang/ui/core/selection_controls.dart';
import 'package:melonbang/ui/core/theme.dart';

Json _task(String id, String title, String status, double progress) => {
  'id': id,
  'title': title,
  'status': status,
  'progress': progress,
};
Json _file(
  String downloadId,
  String id, {
  double progress = 1,
  String kind = 'video',
}) => {
  'downloadId': downloadId,
  'id': id,
  'name': '$id.${kind == 'video' ? 'mkv' : 'txt'}',
  'mediaKind': kind,
  'progress': progress,
  'size': 1048576,
};

Future<void> _show(
  WidgetTester tester,
  ValueNotifier<Json> data, {
  List<String>? actions,
  List<(String, String?)>? played,
  double textScale = 1,
  double height = 1500,
}) async {
  tester.view.physicalSize = Size(960, height);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(false),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: 720,
            child: ValueListenableBuilder<Json>(
              valueListenable: data,
              builder: (context, downloads, _) => DownloadsPage(
                downloads: downloads,
                onAddMagnet: () {},
                onAddTorrent: () {},
                onOpenVideo: () {},
                onExplore: () {},
                onTogglePause: (task) => actions?.add('toggle:${task['id']}'),
                onRemove: (task) => actions?.add('remove:${task['id']}'),
                onStopSeeding: (task) => actions?.add('stop:${task['id']}'),
                onPlay: (task, file) => played?.add((task, file)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(MelonPanel));
Finder _inCard(String title, Finder child) =>
    find.descendant(of: _card(title), matching: child);
Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(MelonSegmentedControl<String>),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _status(WidgetTester tester, String current, String next) async {
  await tester.tap(find.widgetWithText(OutlinedButton, current));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, next));
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester, String title) async {
  await tester.tap(_inCard(title, find.byTooltip('任务详情')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('discovery explains idle transfers and low rates stay visible', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final task = <String, dynamic>{
      ..._task('search', '节点发现测试', 'downloading', 0),
      'peerCount': 0,
      'knownPeerCount': 0,
      'trackerCount': 3,
      'workingTrackers': 0,
      'failedTrackers': 2,
      'dhtNodes': 0,
      'downloadSpeedBytesPerSecond': 0,
    };
    final data = ValueNotifier<Json>({
      'tasks': [task],
    });
    addTearDown(data.dispose);
    await _show(tester, data);
    expect(find.text('寻找下载节点'), findsOneWidget);
    await _expand(tester, '节点发现测试');
    expect(find.textContaining('Tracker 0/3 可用'), findsOneWidget);
    expect(find.textContaining('检查网络是否允许 BT / UDP'), findsOneWidget);
    data.value = {
      'tasks': [
        {
          ...task,
          'peerCount': 1,
          'knownPeerCount': 4,
          'workingTrackers': 1,
          'failedTrackers': 1,
          'dhtNodes': 24,
          'downloadSpeedBytesPerSecond': 8192,
        },
      ],
    };
    await tester.pumpAndSettle();
    expect(find.text('寻找下载节点'), findsNothing);
    expect(find.textContaining('8.0 KiB/s'), findsNWidgets(2));
    expect(find.textContaining('检查网络是否允许 BT / UDP'), findsNothing);
    expect(find.textContaining('DHT 24 个节点'), findsOneWidget);
    data.value = {
      'tasks': [
        {...task, 'status': 'paused', 'dhtNodes': -1},
      ],
    };
    await tester.pumpAndSettle();
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.textContaining('DHT 已关闭'), findsOneWidget);
    expect(find.textContaining('检查网络是否允许 BT / UDP'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'category and status filters intersect without including failed as paused',
    (tester) async {
      addTearDown(tester.view.reset);
      final data = ValueNotifier<Json>({
        'tasks': [
          _task('a', '正在下载', 'downloading', .2),
          _task('b', '暂停下载', 'paused', .3),
          _task('c', '下载失败', 'failed', .4),
          _task('d', '缓存暂停', 'paused', 1),
          _task('e', '缓存做种', 'seeding', 1),
        ],
      });
      addTearDown(data.dispose);
      await _show(tester, data);
      await _tab(tester, '进行中');
      await _status(tester, '所有状态', '已暂停');
      expect(find.text('暂停下载'), findsOneWidget);
      expect(find.text('下载失败'), findsNothing);
      expect(find.text('正在下载'), findsNothing);
      expect(find.text('缓存暂停'), findsNothing);
      await _tab(tester, '已缓存');
      expect(find.text('缓存暂停'), findsOneWidget);
      expect(find.text('暂停下载'), findsNothing);
      expect(find.text('缓存做种'), findsNothing);
      await _status(tester, '已暂停', '做种中');
      expect(find.text('缓存做种'), findsOneWidget);
      expect(find.text('缓存暂停'), findsNothing);
      await _tab(tester, '进行中');
      expect(find.text('当前分类没有任务'), findsOneWidget);
      expect(find.text('缓存做种'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('multi-video tasks require a specific file selection', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final data = ValueNotifier<Json>({
      'tasks': [_task('multi', '多集合集', 'seeding', 1)],
      'files': [
        _file('multi', 'episode-1'),
        _file('multi', 'episode-2'),
        _file('multi', 'readme', kind: 'other'),
        _file('unrelated', 'different-task'),
      ],
    });
    addTearDown(data.dispose);
    final played = <(String, String?)>[];
    await _show(tester, data, played: played);
    await tester.tap(
      _inCard('多集合集', find.widgetWithText(FilledButton, '选择文件')),
    );
    await tester.pumpAndSettle();
    expect(played, isEmpty);
    expect(find.text('任务文件'), findsOneWidget);
    expect(find.text('different-task.mkv'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '播放此文件',
      ),
      findsNWidgets(2),
    );
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'episode-2.mkv'),
        matching: find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '播放此文件',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(played, [('multi', 'episode-2')]);
    expect(find.text('任务文件'), findsNothing);
  });

  testWidgets('checking tasks cannot play from the card or file dialog', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final data = ValueNotifier<Json>({
      'tasks': [_task('check', '正在校验', 'checking', 1)],
      'files': [_file('check', 'episode')],
    });
    addTearDown(data.dispose);
    final played = <(String, String?)>[];
    await _show(tester, data, played: played);
    expect(
      tester
          .widget<FilledButton>(_inCard('正在校验', find.byType(FilledButton)))
          .onPressed,
      isNull,
    );
    await _expand(tester, '正在校验');
    await tester.tap(_inCard('正在校验', find.text('查看文件')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '播放此文件',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(played, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an open file dialog follows tasks that enter checking or are removed',
    (tester) async {
      addTearDown(tester.view.reset);
      final task = _task('changing', '状态会变化', 'seeding', 1);
      final files = [
        _file('changing', 'episode-1'),
        _file('changing', 'episode-2'),
      ];
      final data = ValueNotifier<Json>({
        'tasks': [task],
        'files': files,
      });
      addTearDown(data.dispose);
      final played = <(String, String?)>[];
      await _show(tester, data, played: played);
      await tester.tap(find.widgetWithText(FilledButton, '选择文件'));
      await tester.pumpAndSettle();
      data.value = {
        'tasks': [
          {...task, 'status': 'checking'},
        ],
        'files': files,
      };
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '播放此文件',
              ),
            )
            .every((button) => button.onPressed == null),
        isTrue,
      );
      data.value = {
        'tasks': [
          {...task, 'status': 'removed'},
        ],
        'files': files,
      };
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '播放此文件',
              ),
            )
            .every((button) => button.onPressed == null),
        isTrue,
      );
      expect(played, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completed tasks still need a complete video before enabling play',
    (tester) async {
      addTearDown(tester.view.reset);
      final data = ValueNotifier<Json>({
        'tasks': [
          _task('none', '没有视频', 'completed', 1),
          _task('partial', '视频还未完成', 'seeding', 1),
        ],
        'files': [
          _file('none', 'readme', kind: 'other'),
          _file('partial', 'episode', progress: .9),
        ],
      });
      addTearDown(data.dispose);
      await _show(tester, data);
      for (final title in ['没有视频', '视频还未完成']) {
        expect(
          tester
              .widget<FilledButton>(_inCard(title, find.byType(FilledButton)))
              .onPressed,
          isNull,
        );
      }
    },
  );

  testWidgets(
    'expanded controls keep task identity through stop resume and remove',
    (tester) async {
      addTearDown(tester.view.reset);
      final first = _task('first', '第一项缓存', 'seeding', 1);
      final second = _task('second', '第二项缓存', 'paused', 1);
      final data = ValueNotifier<Json>({
        'tasks': [first, second],
      });
      addTearDown(data.dispose);
      final actions = <String>[];
      await _show(tester, data, actions: actions);
      await _expand(tester, '第一项缓存');
      await tester.tap(_inCard('第一项缓存', find.text('停止做种')));
      expect(actions, ['stop:first']);
      data.value = {
        'tasks': [
          {...first, 'status': 'completed', 'seedingStopped': true},
          second,
        ],
      };
      await tester.pumpAndSettle();
      await tester.tap(_inCard('第一项缓存', find.text('继续做种')));
      await _expand(tester, '第二项缓存');
      await tester.tap(_inCard('第二项缓存', find.text('移除任务与缓存')));
      expect(actions, ['stop:first', 'toggle:first', 'remove:second']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '720px content width supports large type task details and file names',
    (tester) async {
      addTearDown(tester.view.reset);
      final title = '这是很长的真实下载标题，包含作品名称、分集信息、字幕组与视频格式';
      final data = ValueNotifier<Json>({
        'tasks': [_task('long', title, 'seeding', 1)],
        'files': [
          {..._file('long', 'episode-1'), 'name': '$title.mkv'},
          {..._file('long', 'episode-2'), 'name': '$title - episode 02.mkv'},
        ],
      });
      addTearDown(data.dispose);
      await _show(tester, data, textScale: 1.8, height: 960);
      expect(tester.takeException(), isNull);
      await _expand(tester, title);
      expect(tester.takeException(), isNull);
      await tester.tap(
        _inCard(title, find.widgetWithText(FilledButton, '选择文件')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
