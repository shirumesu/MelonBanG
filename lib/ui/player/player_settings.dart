import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../app_services.dart';
import 'playback.dart';

class PlayerSettings extends StatefulWidget {
  const PlayerSettings({
    super.key,
    required this.playback,
    required this.service,
    required this.subject,
    required this.onEpisode,
    required this.onError,
    required this.onPresentationChanged,
  });
  final Playback playback;
  final AppServices service;
  final Json? subject;
  final ValueChanged<Json> onEpisode;
  final ValueChanged<Object> onError;
  final VoidCallback onPresentationChanged;
  @override
  State<PlayerSettings> createState() => _PlayerSettingsState();
}

class _PlayerSettingsState extends State<PlayerSettings> {
  final query = TextEditingController();
  String tab = 'tracks', provider = 'bilibili';
  bool loading = false;
  List<Json> matches = [];
  String? _sessionId;
  int _searchRequest = 0;
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
      matches = [];
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
  Widget build(BuildContext context) => Container(
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
  Future<void> offsetSubtitle(double delta) => perform(() async {
    await playback.offsetSubtitle(delta);
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
    const Text('不透明度'),
    Slider(
      value: playback.danmakuOpacity,
      min: .2,
      max: 1,
      onChanged: (value) =>
          changePresentation(() => playback.danmakuOpacity = value),
    ),
    const Text('显示区域'),
    Slider(
      value: playback.danmakuArea,
      min: .2,
      max: 1,
      onChanged: (value) =>
          changePresentation(() => playback.danmakuArea = value),
    ),
    const Divider(),
    FilledButton.icon(
      onPressed: loading
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
    for (final source in objects(playback.session?['danmakuSources']))
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${source['label']}'),
            subtitle: Text('${source['count']} 条 · ${source['status']}'),
            value: source['enabled'] == true,
            onChanged: (value) => loadDanmaku(
              () async =>
                  widget.service.library.enable('${source['id']}', value),
            ),
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
        _searchRequest++;
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
        onTap: () => loadDanmaku(
          () => widget.service.library.selectEpisode(match['episodeId'] as int),
        ),
      ),
    const SizedBox(height: 12),
    Text('已加载 ${playback.comments.length} 条弹幕'),
    TextButton(onPressed: loadLocalComments, child: const Text('导入弹幕 JSON')),
  ];
  Future<void> loadDanmaku(Future<void> Function() load) async {
    setState(() => loading = true);
    await perform(() async {
      await load();
      if (widget.service.library.current case final Json next) {
        playback.accept(next);
      }
    });
    if (mounted) setState(() => loading = false);
  }

  Future<void> manualDanmaku() async {
    if (query.text.trim().isEmpty) return;
    if (provider == 'dandanplay') {
      final ticket = ++_searchRequest;
      final sessionId = playback.session?['id'];
      await perform(() async {
        final result = await widget.service.danmaku.search(query.text.trim());
        if (mounted &&
            ticket == _searchRequest &&
            sessionId == playback.session?['id']) {
          setState(() => matches = objects(result));
        }
      });
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
