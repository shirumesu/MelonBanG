import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/danmaku_repository.dart';
import 'package:melonbang/ui/player/playback.dart';
import 'package:melonbang/ui/player/player_page.dart';
import 'package:melonbang/ui/player/player_settings.dart';
import 'package:melonbang/ui/player/player_theme.dart';

class MemoryPlayer extends PlatformPlayer {
  MemoryPlayer() : super(configuration: const PlayerConfiguration()) {
    state = state.copyWith(duration: const Duration(minutes: 24));
  }

  @override
  Future<void> play() async {
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    state = state.copyWith(position: position);
    positionController.add(position);
  }
}

class MemoryVideoController implements VideoController {
  MemoryVideoController(this.player);
  @override
  final Player player;
  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryPlayback extends ChangeNotifier implements Playback {
  MemoryPlayback() {
    player = Player(platformPlayer: MemoryPlayer());
    video = MemoryVideoController(player);
  }
  @override
  late final Player player;
  @override
  late final VideoController video;
  @override
  String? uri = 'memory:video';
  @override
  Json? session;
  @override
  String? error;
  @override
  bool opening = false;
  @override
  bool danmakuEnabled = false;
  @override
  double danmakuSize = 23, danmakuOpacity = .9, danmakuArea = .6;
  @override
  List<Json> comments = [];
  @override
  double subtitleDelay = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ControlledDanmaku extends DanmakuRepository {
  ControlledDanmaku(super.api);
  final requests = <Completer<List<Json>>>[];
  @override
  Future<List<Json>> search(String title) {
    final request = Completer<List<Json>>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  testWidgets('modified player keys reach the application shortcuts', (
    tester,
  ) async {
    final playback = MemoryPlayback();
    final services = AppServices();
    var searches = 0, backs = 0, fullscreenChanges = 0;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await playback.player.dispose();
      playback.dispose();
      await services.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.keyF,
                control: true,
              ): () =>
                  searches++,
              const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
                  searches++,
              const SingleActivator(
                LogicalKeyboardKey.arrowLeft,
                alt: true,
              ): () =>
                  backs++,
              const SingleActivator(
                LogicalKeyboardKey.bracketLeft,
                meta: true,
              ): () =>
                  backs++,
            },
            child: PlayerPage(
              playback: playback,
              service: services,
              onBack: () {},
              onError: (_) {},
              fullScreen: false,
              onFullScreenChanged: (_) async => fullscreenChanges++,
              onEpisode: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await playback.player.seek(const Duration(seconds: 30));
    for (final keys in [
      (LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyF),
      (LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyF),
      (LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowLeft),
      (LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.bracketLeft),
    ]) {
      await tester.sendKeyDownEvent(keys.$1);
      await tester.sendKeyEvent(keys.$2);
      await tester.sendKeyUpEvent(keys.$1);
    }
    await tester.pump();
    expect(searches, 2);
    expect(backs, 2);
    expect(fullscreenChanges, 0);
    expect(playback.player.state.position, const Duration(seconds: 30));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(fullscreenChanges, 1);
    expect(playback.player.state.position, const Duration(seconds: 25));
    expect(tester.takeException(), isNull);
  });

  testWidgets('menus restore focus and controls stay available while in use', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final playback = MemoryPlayback()
      ..session = {'id': 'session', 'subjectId': 7};
    final services = AppServices();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await playback.player.dispose();
      playback.dispose();
      await services.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerPage(
            playback: playback,
            service: services,
            onBack: () {},
            onError: (_) {},
            fullScreen: false,
            onFullScreenChanged: (_) async {},
            onEpisode: (_) {},
            subject: const {'subjectId': 7, 'name': 'Example', 'episodes': []},
          ),
        ),
      ),
    );
    await tester.pump();
    final audio = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '音轨',
    );
    await tester.tap(audio);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byTooltip('关闭播放菜单'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byTooltip('关闭播放菜单'), findsNothing);
    expect(tester.widget<IconButton>(audio).focusNode!.hasFocus, isTrue);

    await playback.player.play();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(audio.hitTestable(), findsOneWidget);
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 220));
    expect(audio.hitTestable(), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    await mouse.moveTo(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 220));
    await mouse.moveTo(tester.getCenter(audio));
    await tester.pump(const Duration(seconds: 4));
    expect(audio.hitTestable(), findsOneWidget);

    await tester.tap(find.text('找资源'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, '资源关键词'),
      'Preserved query',
    );
    final togglePosition = tester.getCenter(find.byTooltip('收起选集与资源'));
    await mouse.moveTo(togglePosition);
    await tester.pump();
    await tester.tap(find.byTooltip('收起选集与资源'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byTooltip('展开选集与资源'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('Preserved query'), findsOneWidget);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual danmaku search reports pending, empty and retry states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final playback = MemoryPlayback();
    final services = AppServices();
    final repository = ControlledDanmaku(services.api);
    services.danmaku = repository;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await playback.player.dispose();
      playback.dispose();
      await services.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: playerTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: PlayerSettings(
                playback: playback,
                service: services,
                menu: PlayerMenu.danmaku,
                onClose: () {},
                onError: (_) {},
                onPresentationChanged: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Bilibili'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('弹弹play').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Example');
    await tester.tap(find.text('搜索剧集'));
    await tester.pump();
    expect(find.text('正在搜索…'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(repository.requests, hasLength(1));
    repository.requests.first.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的剧集，试试原名或其他关键词。'), findsOneWidget);

    await tester.tap(find.text('搜索剧集'));
    await tester.pump();
    repository.requests.last.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('搜索失败，请重试'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('搜索剧集'));
    await tester.pump();
    repository.requests.last.complete([
      {'animeTitle': 'Example', 'episodeTitle': 'Episode 1', 'episodeId': 1},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Episode 1'), findsOneWidget);
    expect(find.textContaining('搜索失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
