import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../data/cache_method.dart';
import '../../data/play_candidates.dart';
import '../acquisition/resource_widgets.dart';
import '../core/action_feedback.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'playback.dart';

class CandidateResources extends StatefulWidget {
  const CandidateResources({
    super.key,
    required this.service,
    required this.playback,
    required this.subject,
    required this.episode,
    required this.onPlay,
    this.onFindResources,
  });
  final AppServices service;
  final Playback playback;
  final Json subject, episode;
  final Future<void> Function(PlayCandidate) onPlay;
  final VoidCallback? onFindResources;
  @override
  State<CandidateResources> createState() => _CandidateResourcesState();
}

class _CandidateResourcesState extends State<CandidateResources> {
  final feedback = ActionFeedback();
  ActionFeedback searchFeedback = ActionFeedback();
  PlayCandidate? failedPlay;
  final phases = <String, ResourceDownloadPhase>{};
  List<PlayCandidate> candidates = [];
  PlayKind selected = PlayKind.local;
  bool loading = true;
  String? opening;
  int request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void didUpdateWidget(CandidateResources oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject['subjectId'] != widget.subject['subjectId'] ||
        oldWidget.episode['episodeId'] != widget.episode['episodeId']) {
      candidates = [];
      phases.clear();
      unawaited(load());
    }
  }

  Future<void> load() async {
    final ticket = ++request;
    searchFeedback.dispose();
    final status = searchFeedback = ActionFeedback();
    setState(() {
      loading = true;
      failedPlay = null;
      opening = null;
    });
    bool current() => mounted && request == ticket;
    void accept(List<PlayCandidate> values) {
      if (!current()) return;
      setState(() {
        final firstArrival = candidates.isEmpty;
        candidates = values;
        if (firstArrival && values.isNotEmpty) selected = values.first.kind;
      });
    }

    await status.run(() async {
      final settings = widget.playback.settings;
      final priority = subjectIsAiring(widget.subject)
          ? settings.airingPriority
          : settings.completedPriority;
      accept(
        await widget.service.selection.candidates(
          widget.subject,
          widget.episode,
          onlineFirst: priority == 'online',
          language: settings.subtitleLanguage,
          useContinuity:
              widget.playback.session?['subjectId'] ==
              widget.subject['subjectId'],
          onUpdate: accept,
        ),
      );
      return null;
    });
    if (current()) setState(() => loading = false);
  }

  Future<void> play(PlayCandidate candidate) async {
    if (opening != null) return;
    final ticket = request;
    final playAction = widget.onPlay;
    if (candidate.possibleMatch) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认条目匹配'),
          content: Text('此资源可能匹配当前番剧，请确认标题：\n${candidate.title}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('播放'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || ticket != request) return;
    }
    if (!mounted || ticket != request) return;
    setState(() => opening = candidate.id);
    await feedback.run(() async {
      await playAction(candidate);
      return null;
    });
    if (mounted && ticket == request) {
      setState(() {
        opening = null;
        failedPlay = feedback.issue == null ? null : candidate;
      });
    }
  }

  Future<void> download(PlayCandidate candidate, CacheMethod method) async {
    final key = '${candidate.id}:${method.name}';
    setState(() => phases[key] = ResourceDownloadPhase.adding);
    try {
      await widget.service.sources.enqueue(
        '${candidate.ref['candidateId']}',
        method: method,
      );
      if (mounted) setState(() => phases[key] = ResourceDownloadPhase.added);
    } catch (e) {
      if (mounted) {
        setState(() => phases[key] = ResourceDownloadPhase.failed);
        await feedback.run(() async => '$e');
      }
    }
  }

  @override
  void dispose() {
    request++;
    feedback.dispose();
    searchFeedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service.online,
    builder: (context, _) => content(context),
  );

  Widget content(BuildContext context) {
    final rows = candidates.where((c) => c.kind == selected).toList();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            children: [
              MelonSegmentedControl<PlayKind>(
                options: {
                  for (final kind in PlayKind.values)
                    kind:
                        '${kind.label} · ${candidates.where((c) => c.kind == kind).length}',
                },
                value: selected,
                onChanged: (value) => setState(() => selected = value),
              ),
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  if (loading) ...[
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: Gap.sm),
                  ],
                  Expanded(
                    child: Text(
                      loading ? '正在查找可播放资源…' : '点击播放；来源选择仅用于当前会话。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '重新查找',
                    onPressed: loading ? null : load,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                  if (widget.onFindResources != null)
                    TextButton(
                      onPressed: widget.onFindResources,
                      child: const Text('完整资源查找'),
                    ),
                ],
              ),
              FeedbackIssue(feedback: searchFeedback, onRetry: load),
              FeedbackIssue(
                feedback: feedback,
                onRetry: () => failedPlay == null ? load() : play(failedPlay!),
              ),
              if (selected == PlayKind.online)
                for (final rule in widget.service.online.rules)
                  if (widget.service.online.isEnabled('${rule['id']}') &&
                      (widget.service.online.errors.containsKey(
                            '${rule['id']}',
                          ) ||
                          widget.service.online.status('${rule['id']}') ==
                              'update'))
                    Row(
                      children: [
                        const Icon(Icons.error_outline, size: 18, color: coral),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Text(
                            '${rule['name']}：${widget.service.online.errors['${rule['id']}'] ?? '需要更新应用'}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: scheme.error),
                          ),
                        ),
                        TextButton(
                          onPressed: () => launchUrl(
                            Uri.parse(
                              '${rule['website'] ?? widget.service.online.currentDomain('${rule['id']}')}',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text('打开站点'),
                        ),
                      ],
                    ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    loading ? '正在搜索…' : '此分类暂无资源',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                  itemBuilder: (context, index) {
                    final candidate = rows[index];
                    final metadata = <String>[
                      candidate.sourceLabel,
                      if (candidate.kind == PlayKind.online)
                        switch (widget.service.online.status(
                          candidate.provider,
                        )) {
                          'ready' => '正常',
                          'partial' => '部分失败',
                          'error' => '失效',
                          'verification' => '需要验证',
                          _ => '未检查',
                        },
                      if (candidate.quality != null) candidate.quality!,
                      ...candidate.languages,
                      if (candidate.possibleMatch) '可能匹配',
                      if (candidate.health < 0) '近期播放失败',
                      if (!candidate.instant) '边下边播',
                      if (candidate.ref['sizeLabel'] != null)
                        '${candidate.ref['sizeLabel']}',
                      if (candidate.ref['publishedAt'] != null)
                        '${candidate.ref['publishedAt']}',
                    ];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: Material(
                        color: scheme.surfaceContainerLow,
                        borderRadius: controlBorderRadius,
                        child: ListTile(
                          shape: const RoundedRectangleBorder(
                            borderRadius: controlBorderRadius,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  candidate.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              if (index == 0)
                                const Padding(
                                  padding: EdgeInsets.only(left: Gap.sm),
                                  child: MelonBadge('推荐'),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            metadata.join(' · '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: opening == null ? () => play(candidate) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (candidate.kind == PlayKind.bt &&
                                  !candidate.instant)
                                ResourceDownloadButton(
                                  showLabel: true,
                                  defaultMethod:
                                      widget.service.downloads.defaultMethod,
                                  phase:
                                      phases['${candidate.id}:${widget.service.downloads.defaultMethod.name}'] ??
                                      ResourceDownloadPhase.idle,
                                  alternativePhase:
                                      phases['${candidate.id}:${widget.service.downloads.defaultMethod.other.name}'] ??
                                      ResourceDownloadPhase.idle,
                                  onPressed: () => download(
                                    candidate,
                                    widget.service.downloads.defaultMethod,
                                  ),
                                  onAlternative: () => download(
                                    candidate,
                                    widget
                                        .service
                                        .downloads
                                        .defaultMethod
                                        .other,
                                  ),
                                ),
                              IconButton(
                                tooltip: '播放',
                                onPressed: opening == null
                                    ? () => play(candidate)
                                    : null,
                                icon: opening == candidate.id
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.play_arrow_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
