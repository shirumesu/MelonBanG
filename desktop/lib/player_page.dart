import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'danmaku.dart';
import 'playback.dart';
import 'service.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.playback,
    required this.service,
    required this.onOpen,
    required this.onBack,
    required this.onError,
    required this.fullScreen,
    this.subject,
    required this.onEpisode,
  });
  final Playback playback;
  final Service service;
  final VoidCallback onOpen, onBack;
  final void Function(Object) onError;
  final bool fullScreen;
  final Json? subject;
  final void Function(Json) onEpisode;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final focus = FocusNode();
  final query = TextEditingController();
  String tab = 'tracks';
  String provider = 'bilibili';
  bool panel = true, controls = true, loading = false;
  double? dragging;
  Timer? hideTimer;
  List<Json> matches = [];
  Playback get playback => widget.playback;
  Player get player => playback.player;
  @override
  void initState() {
    super.initState();
    playback.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    playback.removeListener(refresh);
    focus.dispose();
    query.dispose();
    hideTimer?.cancel();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      widget.onError(e);
    }
  }

  void reveal() {
    if (!controls) setState(() => controls = true);
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && player.state.playing && dragging == null) {
        setState(() => controls = false);
      }
    });
  }

  Future<void> seekRelative(int seconds) async {
    final maximum = player.state.duration.inMilliseconds;
    final target = (player.state.position.inMilliseconds + seconds * 1000)
        .clamp(0, maximum > 0 ? maximum : 1 << 40);
    await player.seek(Duration(milliseconds: target));
    reveal();
  }

  Future<void> fullscreen() async {
    await windowManager.setFullScreen(!await windowManager.isFullScreen());
  }

  @override
  Widget build(BuildContext context) {
    if (playback.uri == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline,
              size: 72,
              color: Color(0xff22b388),
            ),
            const SizedBox(height: 18),
            const Text(
              '选一部作品，开始观看',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('本地视频 · 内嵌字幕 · 音轨切换'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: widget.onOpen,
              icon: const Icon(Icons.folder_open),
              label: const Text('打开视频'),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              if (!widget.fullScreen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 12, 12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '返回探索',
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Text(
                          '${playback.session?['title'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: '播放设置',
                        onPressed: () => setState(() => panel = !panel),
                        icon: Icon(panel ? Icons.chevron_right : Icons.tune),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Focus(
                  focusNode: focus,
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.space) {
                      unawaited(player.playOrPause());
                    } else if (event.logicalKey ==
                        LogicalKeyboardKey.arrowRight) {
                      unawaited(seekRelative(5));
                    } else if (event.logicalKey ==
                        LogicalKeyboardKey.arrowLeft) {
                      unawaited(seekRelative(-5));
                    } else if (event.logicalKey == LogicalKeyboardKey.keyF ||
                        event.logicalKey == LogicalKeyboardKey.f11) {
                      unawaited(fullscreen());
                    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                      unawaited(windowManager.setFullScreen(false));
                    } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
                      unawaited(
                        player.setVolume(player.state.volume == 0 ? 80 : 0),
                      );
                    } else {
                      return KeyEventResult.ignored;
                    }
                    reveal();
                    return KeyEventResult.handled;
                  },
                  child: MouseRegion(
                    onHover: (_) => reveal(),
                    cursor: controls
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.none,
                    child: GestureDetector(
                      onTap: () {
                        focus.requestFocus();
                        reveal();
                      },
                      onDoubleTap: fullscreen,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Video(
                            controller: playback.video,
                            controls: NoVideoControls,
                            subtitleViewConfiguration:
                                const SubtitleViewConfiguration(visible: false),
                          ),
                          DanmakuLayer(playback: playback),
                          if (playback.opening)
                            const Center(child: CircularProgressIndicator()),
                          StreamBuilder<bool>(
                            stream: player.stream.buffering,
                            initialData: player.state.buffering,
                            builder: (_, snapshot) => snapshot.data == true
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          if (playback.error != null)
                            Center(
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 440,
                                ),
                                padding: const EdgeInsets.all(24),
                                color: Colors.black87,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.orange,
                                      size: 38,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      playback.error!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: widget.onOpen,
                                      child: const Text('选择其他视频'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (controls)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: videoControls(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (panel && !widget.fullScreen)
          SizedBox(width: 290, child: sidePanel()),
      ],
    );
  }

  Widget videoControls() => Theme(
    data: ThemeData.dark(useMaterial3: true),
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 35, 12, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: StreamBuilder<Duration>(
        stream: player.stream.position,
        initialData: player.state.position,
        builder: (context, position) {
          final duration = player.state.duration.inMilliseconds / 1000;
          final current = position.data!.inMilliseconds / 1000;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: (dragging ?? current).clamp(
                  0,
                  duration > 0 ? duration : 1,
                ),
                max: duration > 0 ? duration : 1,
                onChangeStart: (value) {
                  setState(() => dragging = value);
                  hideTimer?.cancel();
                },
                onChanged: duration > 0
                    ? (value) => setState(() => dragging = value)
                    : null,
                onChangeEnd: (value) async {
                  await player.seek(
                    Duration(milliseconds: (value * 1000).round()),
                  );
                  if (mounted) setState(() => dragging = null);
                  reveal();
                },
              ),
              Row(
                children: [
                  StreamBuilder<bool>(
                    stream: player.stream.playing,
                    initialData: player.state.playing,
                    builder: (_, playing) => IconButton(
                      tooltip: '播放 / 暂停（空格）',
                      onPressed: () {
                        unawaited(player.playOrPause());
                        focus.requestFocus();
                        reveal();
                      },
                      icon: Icon(
                        playing.data == true
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '后退 5 秒',
                    onPressed: () => seekRelative(-5),
                    icon: const Icon(Icons.replay_5),
                  ),
                  IconButton(
                    tooltip: '前进 5 秒',
                    onPressed: () => seekRelative(5),
                    icon: const Icon(Icons.forward_5),
                  ),
                  Text(
                    '${formatTime(dragging ?? current)} / ${formatTime(duration)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '弹幕开关',
                    onPressed: () => setState(
                      () => playback.danmakuEnabled = !playback.danmakuEnabled,
                    ),
                    icon: Icon(
                      playback.danmakuEnabled
                          ? Icons.subtitles
                          : Icons.subtitles_off,
                    ),
                  ),
                  StreamBuilder<double>(
                    stream: player.stream.volume,
                    initialData: player.state.volume,
                    builder: (_, snapshot) => Row(
                      children: [
                        IconButton(
                          tooltip: '静音（M）',
                          onPressed: () =>
                              player.setVolume(snapshot.data! == 0 ? 80 : 0),
                          icon: Icon(
                            snapshot.data == 0
                                ? Icons.volume_off
                                : Icons.volume_up,
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Slider(
                            value: snapshot.data!.clamp(0, 100),
                            max: 100,
                            onChanged: (value) => player.setVolume(value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<double>(
                    tooltip: '播放速度',
                    onSelected: (value) => player.setRate(value),
                    itemBuilder: (_) => [.5, .75, 1.0, 1.25, 1.5, 2.0]
                        .map(
                          (rate) => PopupMenuItem(
                            value: rate,
                            child: Text('${rate}x'),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text('${player.state.rate}x'),
                    ),
                  ),
                  IconButton(
                    tooltip: '全屏（F）',
                    onPressed: fullscreen,
                    icon: Icon(
                      widget.fullScreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
  Widget sidePanel() => Container(
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: .15),
        ),
      ),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'tracks', label: Text('播放')),
              ButtonSegment(value: 'danmaku', label: Text('弹幕')),
              ButtonSegment(value: 'episodes', label: Text('选集')),
            ],
            selected: {tab},
            onSelectionChanged: (value) => setState(() => tab = value.first),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: tab == 'tracks'
                ? trackSettings()
                : tab == 'danmaku'
                ? danmakuSettings()
                : episodeSettings(),
          ),
        ),
      ],
    ),
  );
  List<Widget> trackSettings() => [
    const Text(
      '字幕',
      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
    ),
    const SizedBox(height: 12),
    StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (_, snapshot) => Column(
        children: snapshot.data!.subtitle
            .map(
              (track) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  track.id == 'no'
                      ? '关闭字幕'
                      : track.id == 'auto'
                      ? '自动选择'
                      : track.title ?? track.language ?? '字幕 ${track.id}',
                ),
                trailing: player.state.track.subtitle == track
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => perform(() async {
                  await player.setSubtitleTrack(track);
                  refresh();
                }),
              ),
            )
            .toList(),
      ),
    ),
    TextButton.icon(
      onPressed: loadSubtitle,
      icon: const Icon(Icons.add),
      label: const Text('载入外部字幕'),
    ),
    const Divider(height: 30),
    const Text(
      '音轨',
      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
    ),
    StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (_, snapshot) => Column(
        children: snapshot.data!.audio
            .map(
              (track) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  track.id == 'no'
                      ? '关闭音频'
                      : track.id == 'auto'
                      ? '自动选择'
                      : track.title ?? track.language ?? '音轨 ${track.id}',
                ),
                trailing: player.state.track.audio == track
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => perform(() async {
                  await player.setAudioTrack(track);
                  refresh();
                }),
              ),
            )
            .toList(),
      ),
    ),
    const Divider(height: 30),
    const Text('字幕时间偏移'),
    Row(
      children: [
        TextButton(
          onPressed: () => offsetSubtitle(-.5),
          child: const Text('提前 0.5 秒'),
        ),
        TextButton(
          onPressed: () => offsetSubtitle(.5),
          child: const Text('延后 0.5 秒'),
        ),
      ],
    ),
    const Divider(height: 30),
    const Text('快捷键', style: TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    const Text(
      '空格  播放 / 暂停\n← / →  跳转 5 秒\nF / F11  全屏\nEsc  退出全屏\nM  静音\n双击画面  全屏',
      style: TextStyle(height: 1.8, color: Colors.grey),
    ),
  ];
  double subtitleDelay = 0;
  Future<void> offsetSubtitle(double delta) => perform(() async {
    subtitleDelay += delta;
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('sub-delay', '$subtitleDelay');
    }
  });
  Future<void> loadSubtitle() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Subtitle',
          extensions: ['ass', 'ssa', 'srt', 'vtt', 'sub', 'sup'],
        ),
      ],
    );
    if (file != null) {
      await perform(() async {
        await player.setSubtitleTrack(
          SubtitleTrack.uri(file.path, title: file.name),
        );
        refresh();
      });
    }
  }

  List<Widget> episodeSettings() {
    final episodes = objects(widget.subject?['episodes']);
    return [
      if (episodes.isEmpty) const Text('此视频没有关联章节。可以在番剧详情中为某一话打开本地文件。'),
      for (final episode in episodes)
        Card(
          child: ListTile(
            dense: true,
            title: Text('第 ${episode['sort']} 话'),
            subtitle: Text(titleOf(episode)),
            selected: episode['episodeId'] == playback.session?['episodeId'],
            onTap: () => widget.onEpisode(episode),
          ),
        ),
    ];
  }

  List<Widget> danmakuSettings() => [
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('显示弹幕'),
      value: playback.danmakuEnabled,
      onChanged: (value) => setState(() => playback.danmakuEnabled = value),
    ),
    Text('字号 ${playback.danmakuSize.round()}'),
    Slider(
      value: playback.danmakuSize,
      min: 14,
      max: 36,
      onChanged: (value) => setState(() => playback.danmakuSize = value),
    ),
    const Text('不透明度'),
    Slider(
      value: playback.danmakuOpacity,
      min: .2,
      max: 1,
      onChanged: (value) => setState(() => playback.danmakuOpacity = value),
    ),
    const Text('显示区域'),
    Slider(
      value: playback.danmakuArea,
      min: .2,
      max: 1,
      onChanged: (value) => setState(() => playback.danmakuArea = value),
    ),
    const Divider(),
    FilledButton.icon(
      onPressed: loading
          ? null
          : () => loadDanmaku('playback.loadDanmaku', playback.session!['id']),
      icon: const Icon(Icons.auto_awesome_outlined),
      label: const Text('自动匹配弹幕'),
    ),
    if (loading) const LinearProgressIndicator(),
    for (final source in objects(playback.session?['danmakuSources']))
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${source['label']}'),
            subtitle: Text('${source['count']} 条 · ${source['status']}'),
            value: source['enabled'] == true,
            onChanged: (value) =>
                loadDanmaku('playback.setDanmakuSourceEnabled', {
                  'sessionId': playback.session!['id'],
                  'providerId': source['id'],
                  'enabled': value,
                }),
          ),
          if (source['errorMessage'] != null)
            Text(
              '${source['errorMessage']}',
              style: const TextStyle(fontSize: 11, color: Colors.orange),
            ),
        ],
      ),
    const Divider(height: 30),
    const Text('手动匹配'),
    const SizedBox(height: 12),
    DropdownButtonFormField<String>(
      initialValue: provider,
      items: const [
        DropdownMenuItem(value: 'bilibili', child: Text('Bilibili')),
        DropdownMenuItem(value: 'bahamut', child: Text('巴哈姆特动画疯')),
        DropdownMenuItem(value: 'dandanplay', child: Text('弹弹play')),
      ],
      onChanged: (value) => setState(() {
        provider = value!;
        matches = [];
      }),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: query,
      decoration: InputDecoration(
        hintText: provider == 'dandanplay' ? '番剧名称' : '剧集网址或编号',
      ),
      onSubmitted: (_) => manualDanmaku(),
    ),
    const SizedBox(height: 10),
    OutlinedButton(
      onPressed: manualDanmaku,
      child: Text(provider == 'dandanplay' ? '搜索剧集' : '加载弹幕'),
    ),
    for (final match in matches)
      ListTile(
        dense: true,
        title: Text('${match['animeTitle']}'),
        subtitle: Text('${match['episodeTitle']}'),
        onTap: () => loadDanmaku('playback.selectDanmakuEpisode', {
          'sessionId': playback.session!['id'],
          'episodeId': match['episodeId'],
        }),
      ),
    const SizedBox(height: 12),
    Text('已加载 ${playback.comments.length} 条弹幕'),
    TextButton(onPressed: loadLocalComments, child: const Text('导入弹幕 JSON')),
  ];
  Future<void> loadDanmaku(String method, dynamic arg) async {
    setState(() => loading = true);
    await perform(() async {
      final next = object(await widget.service.call(method, [arg]));
      playback.accept(next);
    });
    if (mounted) setState(() => loading = false);
  }

  Future<void> manualDanmaku() async {
    if (query.text.trim().isEmpty) return;
    if (provider == 'dandanplay') {
      await perform(() async {
        final result = await widget.service.call(
          'playback.searchDanmakuEpisodes',
          [
            {'sessionId': playback.session!['id'], 'anime': query.text.trim()},
          ],
        );
        if (mounted) setState(() => matches = objects(result));
      });
    } else {
      await loadDanmaku('playback.loadDanmakuSource', {
        'sessionId': playback.session!['id'],
        'providerId': provider,
        'locator': query.text.trim(),
      });
    }
  }

  Future<void> loadLocalComments() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Danmaku JSON', extensions: ['json']),
      ],
    );
    if (file != null) {
      await perform(() async {
        final decoded = jsonDecode(await File(file.path).readAsString());
        if (decoded is! List) {
          throw const FormatException('弹幕文件应为数组，包含 timeSeconds、text 和 mode。');
        }
        final comments =
            objects(decoded)
                .where(
                  (item) =>
                      item['timeSeconds'] is num && item['text'] is String,
                )
                .toList()
              ..sort(
                (a, b) =>
                    number(a['timeSeconds'])
                        .compareTo(number(b['timeSeconds'])),
              );
        if (mounted) setState(() => playback.comments = comments);
      });
    }
  }
}

String formatTime(double seconds) {
  final total = seconds.isFinite ? seconds.floor().clamp(0, 1 << 40) : 0;
  final minutes = (total ~/ 60).toString().padLeft(2, '0');
  return '$minutes:${(total % 60).toString().padLeft(2, '0')}';
}
