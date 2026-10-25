import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/error_message.dart';
import '../../domain/danmaku.dart';
import '../../features/danmaku/danmaku_controller.dart';
import '../../features/playback/playback.dart';
import '../core/theme.dart';
import 'danmaku_filter_editor.dart';

/// The side panel's 弹幕 tab: each source with its match, a place to change
/// that match, local import, and blocking rules. Display options are in the
/// transport's popover.
class PlayerDanmakuPane extends StatefulWidget {
  const PlayerDanmakuPane({
    super.key,
    required this.playback,
    required this.onError,
    this.title,
  });
  final Playback playback;
  final ValueChanged<Object> onError;

  /// The subject's title, searched when a source's matching opens.
  final String? title;

  @override
  State<PlayerDanmakuPane> createState() => _PlayerDanmakuPaneState();
}

class _PlayerDanmakuPaneState extends State<PlayerDanmakuPane> {
  final query = TextEditingController();

  /// The source whose match is being changed.
  String? editing;
  bool loading = false, searching = false;
  String? loadError, searchError;

  /// Search results, then each opened group, as (group title, rows).
  List<(String, List<DanmakuCandidate>)> levels = [];
  String? _sessionId;
  int _searchRequest = 0, _loadRequest = 0, _importRequest = 0;
  Playback get playback => widget.playback;
  DanmakuController get danmaku => playback.danmaku;
  bool get busy => loading || searching;

  @override
  void initState() {
    super.initState();
    _sessionId = playback.session?.id;
    // Playback passes on the danmaku controller's changes.
    playback.addListener(refresh);
  }

  void refresh() {
    final sessionId = playback.session?.id;
    if (sessionId != _sessionId) {
      _sessionId = sessionId;
      _searchRequest++;
      _loadRequest++;
      _importRequest++;
      editing = null;
      levels = [];
      loading = searching = false;
      loadError = searchError = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    playback.removeListener(refresh);
    query.dispose();
    super.dispose();
  }

  void edit(String source) {
    setState(() {
      editing = editing == source ? null : source;
      _searchRequest++;
      query.text = editing == null ? '' : widget.title ?? '';
      levels = [];
      searching = false;
      searchError = null;
    });
    if (editing != null && danmaku.searchable(source)) {
      unawaited(search(source));
    }
  }

  Future<void> load(Future<void> Function() action) async {
    if (busy) return;
    final ticket = ++_loadRequest;
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      await action();
      if (mounted && ticket == _loadRequest) setState(() => editing = null);
    } catch (error) {
      if (mounted && ticket == _loadRequest) {
        setState(() => loadError = '弹幕加载失败：${errorMessage(error)}');
      }
    } finally {
      if (mounted && ticket == _loadRequest) setState(() => loading = false);
    }
  }

  Future<void> search(String provider) async {
    final keyword = query.text.trim();
    if (keyword.isEmpty) return;
    await reveal(provider, null, () => danmaku.search(provider, keyword));
  }

  /// Shows [fetch]'s rows as search results ([group] null) or as the opened
  /// [group]. A lone group opens at once, and an opened group holding a
  /// single episode loads it.
  Future<void> reveal(
    String provider,
    String? group,
    Future<List<DanmakuCandidate>> Function() fetch,
  ) async {
    if (busy) return;
    final ticket = ++_searchRequest;
    final sessionId = playback.session?.id;
    bool current() =>
        mounted &&
        ticket == _searchRequest &&
        sessionId == playback.session?.id;
    setState(() {
      searching = true;
      searchError = null;
      if (group == null) levels = [];
    });
    List<DanmakuCandidate> rows;
    try {
      rows = await fetch();
      while (current() && rows.length == 1 && rows.single.open != null) {
        group = rows.single.title;
        rows = await rows.single.open!();
      }
    } catch (error) {
      if (current()) {
        setState(() {
          searching = false;
          searchError = '搜索失败：${errorMessage(error)}';
        });
      }
      return;
    }
    if (!current()) return;
    setState(() {
      searching = false;
      levels = [...levels, (group ?? '', rows)];
    });
    if (group != null && rows.length == 1) {
      await load(() => danmaku.load(provider, rows.single.locator!));
    }
  }

  Future<void> importLocal() async {
    final sessionId = playback.session?.id;
    if (sessionId == null) return;
    final ticket = ++_importRequest;
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Danmaku JSON', extensions: ['json']),
      ],
    );
    if (file == null ||
        !mounted ||
        ticket != _importRequest ||
        sessionId != playback.session?.id) {
      return;
    }
    try {
      await danmaku.importLocal(file.path);
    } catch (e) {
      widget.onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final sources = playback.session == null
        ? const <DanmakuSourceState>[]
        : danmaku.sources;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
      children: [
        Row(
          children: [
            Text('来源', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: Gap.sm),
            Text(
              danmaku.duplicates == 0
                  ? '共 ${danmaku.comments.length} 条'
                  : '共 ${danmaku.comments.length} 条（已去重 ${danmaku.duplicates} 条）',
              style: small,
            ),
            const Spacer(),
            TextButton(
              onPressed: busy || sources.isEmpty
                  ? null
                  : () => load(
                      () => danmaku.autoMatch(
                        playback.player.state.duration.inMilliseconds / 1000,
                      ),
                    ),
              child: const Text('重新匹配'),
            ),
          ],
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (loadError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
            child: Text(
              loadError!,
              style: small?.copyWith(color: scheme.error),
            ),
          ),
        for (final source in sources) sourceRow(source),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: playback.session == null ? null : importLocal,
            child: const Text('导入弹幕 JSON'),
          ),
        ),
        const SizedBox(height: Gap.md),
        DanmakuFilterEditor(preferences: danmaku.preferences),
      ],
    );
  }

  Widget sourceRow(DanmakuSourceState source) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final open = editing == source.id;
    final local = source.id == danmaku.repository.local.id;
    final status = switch (source.status) {
      DanmakuStatus.idle => '等待匹配',
      DanmakuStatus.loading => '匹配中',
      DanmakuStatus.ready => switch (source.followed) {
        final title? => '${source.count} 条 · 沿用之前的选择：$title',
        null => '${source.count} 条',
      },
      DanmakuStatus.unmatched =>
        source.candidates.isEmpty
            ? source.message ?? '未匹配'
            : '有 ${source.candidates.length} 个可能的匹配',
      DanmakuStatus.error => source.error ?? '加载失败',
    };
    final warn =
        source.status == DanmakuStatus.unmatched ||
        source.status == DanmakuStatus.error;
    return Container(
      margin: const EdgeInsets.only(top: Gap.xs),
      decoration: BoxDecoration(
        color: open ? scheme.surfaceContainerLow : null,
        borderRadius: controlBorderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, 0, Gap.xs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.label, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: small?.copyWith(
                          color: warn ? scheme.tertiary : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!local)
                  TextButton(
                    onPressed: busy ? null : () => edit(source.id),
                    child: Text(
                      open
                          ? '收起'
                          : !danmaku.searchable(source.id)
                          ? '详情'
                          : source.status == DanmakuStatus.ready
                          ? '更换'
                          : '匹配',
                    ),
                  ),
                Switch(
                  value: source.enabled,
                  onChanged: busy
                      ? null
                      : (value) => load(
                          () async => danmaku.setDefault(source.id, value),
                        ),
                ),
              ],
            ),
          ),
          if (open) matching(source),
        ],
      ),
    );
  }

  /// Suggested episodes and a manual search, for one source.
  Widget matching(DanmakuSourceState source) {
    final small = Theme.of(context).textTheme.bodySmall;
    final scheme = Theme.of(context).colorScheme;
    if (!danmaku.searchable(source.id)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.sm),
        child: Text(
          '随播放的章节自动匹配，无需手动选择',
          style: small?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    Widget choice(DanmakuCandidate match) => ListTile(
      dense: true,
      shape: const RoundedRectangleBorder(borderRadius: badgeBorderRadius),
      title: Text(match.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: match.subtitle == null || match.subtitle!.isEmpty
          ? null
          : Text(match.subtitle!),
      trailing: match.open == null
          ? null
          : const Icon(Icons.chevron_right, size: 18),
      onTap: busy
          ? null
          : match.open == null
          ? () => load(() => danmaku.load(source.id, match.locator!))
          : () => reveal(source.id, match.title, match.open!),
    );
    final level = levels.lastOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final match in source.candidates) choice(match),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: query,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '搜索番剧名称或粘贴链接',
                    ),
                    onSubmitted: (_) => search(source.id),
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton.tonal(
                onPressed: busy ? null : () => search(source.id),
                child: const Text('搜索'),
              ),
            ],
          ),
          if (searching)
            const Padding(
              padding: EdgeInsets.only(top: Gap.sm),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (searchError != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                searchError!,
                style: small?.copyWith(color: scheme.error),
              ),
            ),
          if (level != null && (levels.length > 1 || level.$1.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Row(
                children: [
                  if (levels.length > 1)
                    IconButton(
                      tooltip: '返回',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: busy
                          ? null
                          : () => setState(() => levels.removeLast()),
                    ),
                  Expanded(
                    child: Text(
                      level.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                  ),
                ],
              ),
            ),
          if (level != null && level.$2.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                levels.length == 1 && level.$1.isEmpty
                    ? '没有找到，试试原名或其他关键词'
                    : '这里没有可加载的弹幕',
                style: small,
              ),
            ),
          for (final match in level?.$2 ?? const <DanmakuCandidate>[])
            choice(match),
        ],
      ),
    );
  }
}
