import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../app_services.dart';
import 'playback.dart';
import 'player_theme.dart';

class PlayerSettings extends StatefulWidget {
  const PlayerSettings({
    super.key,
    required this.playback,
    required this.service,
    required this.menu,
    required this.onClose,
    required this.onError,
    required this.onPresentationChanged,
    this.closeFocusNode,
  });
  final Playback playback;
  final AppServices service;
  final PlayerMenu menu;
  final VoidCallback onClose;
  final ValueChanged<Object> onError;
  final VoidCallback onPresentationChanged;
  final FocusNode? closeFocusNode;
  @override
  State<PlayerSettings> createState() => _PlayerSettingsState();
}

class _PlayerSettingsState extends State<PlayerSettings> {
  final query = TextEditingController();
  String provider = 'bilibili';
  bool loading = false;
  bool manualSearching = false, manualSearched = false;
  String? manualError, loadError;
  List<Json> matches = [];
  String? _sessionId;
  int _searchRequest = 0;
  int _loadRequest = 0;
  bool get busy => loading || manualSearching;
  Playback get playback => widget.playback;
  Player get player => playback.player;
  @override
  void initState() {
    super.initState();
    _sessionId = playback.session?['id'] as String?;
    playback.addListener(refresh);
  }

  void refresh() {
    final sessionId = playback.session?['id'] as String?;
    if (sessionId != _sessionId) {
      _sessionId = sessionId;
      _searchRequest++;
      _loadRequest++;
      matches = [];
      loading = manualSearching = manualSearched = false;
      manualError = loadError = null;
    }
    if (mounted) setState(() {});
  }

  void changePresentation(VoidCallback change) {
    setState(change);
    widget.onPresentationChanged();
  }

  @override
  void dispose() {
    playback.removeListener(refresh);
    query.dispose();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      widget.onError(e);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(14),
    elevation: 8,
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 6, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(switch (widget.menu) {
                  PlayerMenu.audio => '音轨',
                  PlayerMenu.danmaku => '弹幕',
                  PlayerMenu.subtitles => '播放设置',
                }, style: Theme.of(context).textTheme.titleSmall),
              ),
              IconButton(
                focusNode: widget.closeFocusNode,
                tooltip: '关闭播放菜单',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: switch (widget.menu) {
              PlayerMenu.audio => audioSettings(),
              PlayerMenu.danmaku => danmakuSettings(),
              PlayerMenu.subtitles => subtitleSettings(),
            },
          ),
        ),
      ],
    ),
  );

  Widget trackChoices(bool subtitle) => StreamBuilder<Tracks>(
    stream: player.stream.tracks,
    initialData: player.state.tracks,
    builder: (_, snapshot) {
      final tracks = subtitle ? snapshot.data!.subtitle : snapshot.data!.audio;
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            for (final track in tracks)
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                selected: subtitle
                    ? player.state.track.subtitle == track
                    : player.state.track.audio == track,
                title: Text(
                  track.id == 'no'
                      ? (subtitle ? '关闭字幕' : '关闭音频')
                      : track.id == 'auto'
                      ? '自动选择'
                      : track.title ??
                            track.language ??
                            '${subtitle ? '字幕' : '音轨'} ${track.id}',
                ),
                trailing:
                    (subtitle
                        ? player.state.track.subtitle == track
                        : player.state.track.audio == track)
                    ? const Icon(Icons.check, size: 16)
                    : null,
                onTap: () => perform(() async {
                  if (subtitle) {
                    await player.setSubtitleTrack(track as SubtitleTrack);
                  } else {
                    await player.setAudioTrack(track as AudioTrack);
                  }
                  refresh();
                }),
              ),
          ],
        ),
      );
    },
  );

  List<Widget> audioSettings() => [
    trackChoices(false),
    const SizedBox(height: 16),
    StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (_, snapshot) => Column(
        children: [
          Row(
            children: [
              const Expanded(child: Text('音量')),
              Text('${snapshot.data!.round()}%'),
            ],
          ),
          Slider(
            value: snapshot.data!.clamp(0, 100),
            max: 100,
            onChanged: (value) => player.setVolume(value),
          ),
        ],
      ),
    ),
  ];

  List<Widget> subtitleSettings() => [
    const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text('字幕'),
    ),
    trackChoices(true),
    const SizedBox(height: 16),
    Row(
      children: [
        const Expanded(child: Text('字幕时间偏移')),
        TextButton(
          onPressed: () => offsetSubtitle(-playback.subtitleDelay),
          child: const Text('重置'),
        ),
      ],
    ),
    Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: '提前 0.5 秒',
            onPressed: () => offsetSubtitle(-.5),
            icon: const Icon(Icons.remove),
          ),
          Text(
            '${playback.subtitleDelay > 0 ? '+' : ''}${playback.subtitleDelay.toStringAsFixed(1)} 秒',
          ),
          IconButton(
            tooltip: '延后 0.5 秒',
            onPressed: () => offsetSubtitle(.5),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    ),
  ];

  Future<void> offsetSubtitle(double delta) => perform(() async {
    await playback.offsetSubtitle(delta);
    refresh();
  });

  List<Widget> danmakuSettings() => [
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('显示弹幕'),
      value: playback.danmakuEnabled,
      onChanged: (value) =>
          changePresentation(() => playback.danmakuEnabled = value),
    ),
    Text('字号 ${playback.danmakuSize.round()}'),
    Slider(
      value: playback.danmakuSize,
      min: 14,
      max: 36,
      onChanged: (value) =>
          changePresentation(() => playback.danmakuSize = value),
    ),
    Text('不透明度 ${(playback.danmakuOpacity * 100).round()}%'),
    Slider(
      value: playback.danmakuOpacity,
      min: .2,
      max: 1,
      onChanged: (value) =>
          changePresentation(() => playback.danmakuOpacity = value),
    ),
    Text('显示区域 ${(playback.danmakuArea * 100).round()}%'),
    Slider(
      value: playback.danmakuArea,
      min: .2,
      max: 1,
      onChanged: (value) =>
          changePresentation(() => playback.danmakuArea = value),
    ),
    const SizedBox(height: 12),
    FilledButton.icon(
      onPressed: busy
          ? null
          : () => loadDanmaku(
              () => widget.service.library.autoMatch(
                player.state.duration.inMilliseconds / 1000,
              ),
            ),
      icon: const Icon(Icons.auto_awesome_outlined),
      label: const Text('自动匹配弹幕'),
    ),
    if (loading) const LinearProgressIndicator(),
    if (loadError != null)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          loadError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    for (final source in objects(playback.session?['danmakuSources']))
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${source['label']}'),
            subtitle: Text(
              '${source['count']} 条 · ${switch (source['status']) {
                'idle' => '等待匹配',
                'loading' => '匹配中',
                'ready' => '已加载',
                'unmatched' => source['statusMessage'] ?? '未匹配',
                'error' => '加载失败',
                _ => '',
              }}',
            ),
            value: source['enabled'] == true,
            onChanged: busy
                ? null
                : (value) => loadDanmaku(
                    () async =>
                        widget.service.library.enable('${source['id']}', value),
                  ),
          ),
          for (final match in objects(source['candidates']))
            ListTile(
              dense: true,
              title: Text('${match['animeTitle'] ?? '候选番剧'}'),
              subtitle: Text(
                '${match['episodeTitle'] ?? match['episodeNumber'] ?? ''}',
              ),
              onTap: busy
                  ? null
                  : () => loadDanmaku(
                      () => widget.service.library.selectEpisode(
                        int.parse('${match['episodeId']}'),
                      ),
                    ),
            ),
          if (source['errorMessage'] != null)
            Text(
              '${source['errorMessage']}',
              style: const TextStyle(fontSize: 11, color: Colors.orange),
            ),
        ],
      ),
    const SizedBox(height: 20),
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
        _searchRequest++;
        matches = [];
        manualSearching = manualSearched = false;
        manualError = null;
      }),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: query,
      decoration: InputDecoration(
        hintText: provider == 'dandanplay' ? '番剧名称' : '剧集网址或编号',
      ),
      onSubmitted: (_) => manualDanmaku(),
      onChanged: (_) => setState(() {
        _searchRequest++;
        manualSearching = manualSearched = false;
        manualError = null;
        matches = [];
      }),
    ),
    const SizedBox(height: 10),
    OutlinedButton(
      onPressed: busy ? null : manualDanmaku,
      child: Text(
        manualSearching
            ? '正在搜索…'
            : provider == 'dandanplay'
            ? '搜索剧集'
            : '加载弹幕',
      ),
    ),
    if (manualSearching) const LinearProgressIndicator(),
    if (manualError != null)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          manualError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    if (manualSearched && matches.isEmpty)
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('没有找到匹配的剧集，试试原名或其他关键词。'),
      ),
    for (final match in matches)
      ListTile(
        dense: true,
        title: Text('${match['animeTitle']}'),
        subtitle: Text('${match['episodeTitle']}'),
        onTap: busy
            ? null
            : () => loadDanmaku(
                () => widget.service.library.selectEpisode(
                  match['episodeId'] as int,
                ),
              ),
      ),
    const SizedBox(height: 12),
    Text('已加载 ${playback.comments.length} 条弹幕'),
    TextButton(onPressed: loadLocalComments, child: const Text('导入弹幕 JSON')),
  ];
  Future<void> loadDanmaku(Future<void> Function() load) async {
    if (busy) return;
    final ticket = ++_loadRequest;
    final sessionId = playback.session?['id'];
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      await load();
      if (!mounted ||
          ticket != _loadRequest ||
          sessionId != playback.session?['id']) {
        return;
      }
      if (widget.service.library.current case final Json next) {
        playback.accept(next);
      }
    } catch (error) {
      if (mounted && ticket == _loadRequest) {
        setState(() => loadError = '弹幕加载失败，请重试：$error');
      }
    } finally {
      if (mounted && ticket == _loadRequest) setState(() => loading = false);
    }
  }

  Future<void> manualDanmaku() async {
    if (busy) return;
    final keyword = query.text.trim();
    if (keyword.isEmpty) {
      setState(
        () => manualError =
            '请先输入${provider == 'dandanplay' ? '番剧名称' : '剧集网址或编号'}。',
      );
      return;
    }
    if (provider == 'dandanplay') {
      final ticket = ++_searchRequest;
      final sessionId = playback.session?['id'];
      setState(() {
        manualSearching = true;
        manualSearched = false;
        manualError = null;
        matches = [];
      });
      try {
        final result = await widget.service.danmaku.search(keyword);
        if (mounted &&
            ticket == _searchRequest &&
            sessionId == playback.session?['id']) {
          setState(() {
            matches = objects(result);
            manualSearched = true;
          });
        }
      } catch (error) {
        if (mounted && ticket == _searchRequest) {
          setState(() => manualError = '搜索失败，请重试：$error');
        }
      } finally {
        if (mounted && ticket == _searchRequest) {
          setState(() => manualSearching = false);
        }
      }
    } else {
      await loadDanmaku(
        () => widget.service.library.loadSource(provider, query.text.trim()),
      );
    }
  }

  Future<void> loadLocalComments() async {
    final sessionId = playback.session?['id'];
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
        if (mounted && sessionId == playback.session?['id']) {
          changePresentation(() => playback.comments = comments);
        }
      });
    }
  }
}
