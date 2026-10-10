import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/pikpak.dart';
import '../../domain/sources.dart';
import '../../features/acquisition/pikpak_probe.dart';
import '../../features/acquisition/source_registry.dart';
import '../core/action_feedback.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

class SourcesPage extends StatefulWidget {
  const SourcesPage({
    super.key,
    required this.registry,
    required this.pikpak,
    required this.onPlay,
  });
  final SourceRegistry registry;
  final PikPakClient pikpak;
  final Future<void> Function(ResolvedStream) onPlay;
  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  final _update = ActionFeedback(),
      _probe = ActionFeedback(),
      _runtimeIssue = ActionFeedback(),
      _engineIssue = ActionFeedback();
  var _search = ActionFeedback(), _resolve = ActionFeedback();
  final _query = TextEditingController();
  String? _selected;
  bool _narrowDetail = false;
  bool _searched = false;
  List<SourceSubject> _subjects = [];
  List<SourceEpisode> _episodes = [];
  SourceSubject? _subject;
  SourceEpisode? _episode;
  ResolvedStream? _resolved;
  int _generation = 0;
  SourceRegistry get registry => widget.registry;
  List<_Entry> get entries => [
    for (final instance in registry.instances)
      _Entry(
        instance.id,
        instance.name,
        instance.kind == SourceKind.torrent ? 'BT 索引' : '在线源',
        instance: instance,
      ),
    const _Entry('pikpak', 'PikPak', '网盘'),
  ];
  @override
  void initState() {
    super.initState();
    unawaited(registry.refreshRules().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _generation++;
    for (final feedback in [
      _update,
      _probe,
      _search,
      _resolve,
      _runtimeIssue,
      _engineIssue,
    ]) {
      feedback.dispose();
    }
    _query.dispose();
    super.dispose();
  }

  String label(SourceHealth status) => switch (status) {
    SourceHealth.ready => '正常',
    SourceHealth.partial => '部分失败',
    SourceHealth.error => '失效',
    SourceHealth.verification => '需要验证',
    SourceHealth.update => '需要更新应用',
    SourceHealth.disabled => '已停用',
    SourceHealth.unknown => '未检查',
  };
  Color color(SourceHealth status) => switch (status) {
    SourceHealth.ready => mint,
    SourceHealth.error => coral,
    SourceHealth.partial ||
    SourceHealth.verification ||
    SourceHealth.update => gold,
    _ => sky,
  };
  Color stepColor(ProbeStatus status) => switch (status) {
    ProbeStatus.ready => mint,
    ProbeStatus.error => coral,
    ProbeStatus.loading => sky,
  };
  Future<void> _probeSource(String id) => id == 'pikpak'
      ? probePikPak(registry, widget.pikpak)
      : registry.probe(id);
  void _select(String id) {
    _generation++;
    _search.dispose();
    _resolve.dispose();
    setState(() {
      _search = ActionFeedback();
      _resolve = ActionFeedback();
      _selected = id;
      _narrowDetail = true;
      _searched = false;
      _subjects = [];
      _episodes = [];
      _subject = null;
      _episode = null;
      _resolved = null;
    });
  }

  void _manualSearch(String id) {
    if (_search.busy) return;
    final generation = ++_generation;
    _search.run(() async {
      final query = _query.text.trim();
      if (query.isEmpty) return '请输入番名';
      final rows = await registry.searchSubjects(id, [query], refresh: true);
      if (mounted && generation == _generation) {
        setState(() {
          _searched = true;
          _subjects = rows;
          _subject = null;
          _episodes = [];
          _episode = null;
          _resolved = null;
        });
      }
      return null;
    });
  }

  void _loadEpisodes(String id, SourceSubject site) {
    if (_search.busy) return;
    final generation = ++_generation;
    _search.run(() async {
      final rows = await registry.episodes(id, site);
      if (mounted && generation == _generation) {
        setState(() {
          _subject = site;
          _episodes = rows;
          _episode = null;
          _resolved = null;
        });
      }
      return null;
    });
  }

  void _resolveEpisode(SourceEpisode episode) {
    if (_resolve.busy) return;
    final generation = _generation;
    setState(() {
      _episode = episode;
      _resolved = null;
    });
    _resolve.run(() async {
      final value = await registry.resolve(episode.ref);
      if (mounted && generation == _generation) {
        setState(() => _resolved = value);
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([registry, _search, _resolve]),
    builder: (context, _) {
      final selected = entries
          .where((entry) => entry.id == (_selected ?? entries.first.id))
          .firstOrNull;
      _engineIssue.issue = registry.needsUpdate ? '部分视频源需要更新应用后才能使用' : null;
      return LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 820;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  pageGutter,
                  Gap.lg,
                  pageGutter,
                  Gap.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '视频源',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        FeedbackButton(
                          feedback: _update,
                          label: '检查更新',
                          runningLabel: '检查中',
                          successLabel: '已更新',
                          icon: Icons.refresh,
                          onPressed: () => _update.run(() async {
                            await registry.refreshRules();
                            return null;
                          }),
                        ),
                        FeedbackButton(
                          feedback: _probe,
                          label: '全部测试',
                          runningLabel: '测试中',
                          successLabel: '测试完成',
                          icon: Icons.fact_check_outlined,
                          onPressed: () => _probe.run(() async {
                            for (final entry in entries.where(
                              (e) =>
                                  registry.isEnabled(e.id) &&
                                  e.instance?.disabled != true &&
                                  e.instance?.manualOnly != true &&
                                  e.instance?.supported != false,
                            )) {
                              await _probeSource(entry.id);
                            }
                            return null;
                          }),
                        ),
                      ],
                    ),
                    Text(
                      '规则 ${registry.version} · ${registry.ruleOrigin} · ${snapshotDate(registry.snapshot.updatedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    FeedbackIssue(
                      feedback: _update,
                      onRetry: () => _update.run(() async {
                        await registry.refreshRules();
                        return null;
                      }),
                    ),
                    if (registry.updateIssue != null && _update.issue == null)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.sm),
                        child: Text(
                          registry.updateIssue!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    FeedbackIssue(
                      feedback: _engineIssue,
                      actionLabel: '查看版本',
                      onRetry: () => launchUrl(
                        Uri.parse(
                          'https://github.com/shirumesu/MelonBanG/releases',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: narrow
                    ? _narrowDetail && selected != null
                          ? _details(selected, narrow: true)
                          : _list(selected)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 244, child: _list(selected)),
                          Expanded(
                            child: selected == null
                                ? const SizedBox()
                                : _details(selected),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      );
    },
  );
  Widget _list(_Entry? selected) => ListView(
    padding: const EdgeInsets.fromLTRB(pageGutter, 0, Gap.md, Gap.lg),
    children: [
      for (final group in ['在线源', 'BT 索引', '网盘']) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.lg, Gap.md, Gap.sm),
          child: Text(group, style: Theme.of(context).textTheme.titleSmall),
        ),
        for (final entry in entries.where((e) => e.group == group))
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.xs),
            child: ListTile(
              dense: true,
              minTileHeight: 56,
              contentPadding: const EdgeInsets.only(
                left: Gap.md,
                right: Gap.sm,
              ),
              selected: selected?.id == entry.id,
              titleTextStyle: Theme.of(context).textTheme.titleSmall,
              title: Text(entry.name),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: MelonBadge(
                  label(registry.status(entry.id)),
                  color: color(registry.status(entry.id)),
                ),
              ),
              trailing: Switch(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                value:
                    registry.isEnabled(entry.id) &&
                    entry.instance?.disabled != true,
                onChanged: entry.instance?.disabled == true
                    ? null
                    : (value) => registry.setEnabled(entry.id, value),
              ),
              onTap: () => _select(entry.id),
            ),
          ),
      ],
    ],
  );
  Widget _details(_Entry entry, {bool narrow = false}) {
    final id = entry.id;
    final instance = entry.instance;
    final online = instance?.kind == SourceKind.online;
    final manual = instance?.manualOnly == true;
    final domain = instance == null
        ? 'https://mypikpak.com'
        : registry.currentDomain(id);
    _runtimeIssue.issue = registry.errors[id];
    return ListView(
      padding: const EdgeInsets.fromLTRB(pageGutter, 0, pageGutter, 40),
      children: [
        FeedbackIssue(
          feedback: _runtimeIssue,
          onRetry: manual
              ? () => _manualSearch(id)
              : () => _probe.run(() async {
                  await _probeSource(id);
                  return null;
                }),
        ),
        if (narrow)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _narrowDetail = false),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回来源列表'),
            ),
          ),
        SectionTitle(
          title: entry.name,
          top: 0,
          trailing: MelonBadge(
            label(registry.status(id)),
            color: color(registry.status(id)),
          ),
        ),
        MelonPanel(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: SelectableText(domain)),
                  const SizedBox(width: Gap.sm),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(instance?.website ?? domain),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('打开站点'),
                  ),
                ],
              ),
              Text(
                instance == null
                    ? '网盘'
                    : manual
                    ? '外接数据源 · 手动选择'
                    : '${instance.engine} · 规则 ${registry.version}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (instance?.description case final description?)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        if (!manual) ...[
          SectionTitle(
            title: '测试结果',
            top: Gap.lg,
            trailing: FeedbackButton(
              feedback: _probe,
              label: '测试此源',
              runningLabel: '测试中',
              successLabel: '测试完成',
              icon: Icons.play_arrow,
              onPressed: () => _probe.run(() async {
                await _probeSource(id);
                return null;
              }),
            ),
          ),
          if (registry.probes[id] case final steps?)
            MelonPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var index = 0; index < steps.length; index++) ...[
                    if (index > 0)
                      const Divider(
                        height: 1,
                        indent: Gap.lg,
                        endIndent: Gap.lg,
                      ),
                    _diagnostic(id, steps[index]),
                  ],
                ],
              ),
            )
          else
            Text(
              '检查搜索与播放链路，结果仅保留于本次运行。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
        if (online) ...[
          const SectionTitle(title: '手动搜索', top: Gap.lg),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    hintText: manual ? '输入番名、BV 号或 B 站播放链接' : '输入番名',
                  ),
                  onSubmitted: (_) => _manualSearch(id),
                ),
              ),
              const SizedBox(width: Gap.sm),
              FeedbackButton(
                feedback: _search,
                label: '搜索',
                runningLabel: '读取中',
                successLabel: '已读取',
                icon: Icons.search,
                onPressed: () => _manualSearch(id),
              ),
            ],
          ),
          FeedbackIssue(feedback: _search, onRetry: () => _manualSearch(id)),
          if (_searched &&
              _subjects.isEmpty &&
              !_search.busy &&
              _search.issue == null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                '没有匹配条目，请换个名称搜索。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_subjects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: MelonPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final site in _subjects)
                      ListTile(
                        dense: true,
                        minTileHeight: 44,
                        title: Text(site.title),
                        subtitle: site.description == null
                            ? null
                            : Text(site.description!),
                        selected: _subject?.id == site.id,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${site.year ?? ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(width: Gap.sm),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                        onTap: _search.busy
                            ? null
                            : () => _loadEpisodes(id, site),
                      ),
                  ],
                ),
              ),
            ),
          if (_subject != null)
            SectionTitle(
              title: '${_subject!.title} · ${_episodes.length} 个播放入口',
              top: Gap.lg,
            ),
          if (_episodes.isNotEmpty) _episodeChoices(),
          FeedbackIssue(
            feedback: _resolve,
            onRetry: () {
              if (_episode != null) _resolveEpisode(_episode!);
            },
          ),
          if (_resolved != null)
            MelonPanel(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _resolved!.url,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: Gap.sm),
                  if (_resolved!.format == StreamFormat.hls &&
                      _resolved!.playlist != null)
                    const Text('已过滤验证过的插入广告分片'),
                  FeedbackButton(
                    feedback: _resolve,
                    label: '试播',
                    runningLabel: '打开中',
                    successLabel: '已打开',
                    icon: Icons.play_arrow,
                    onPressed: () => _resolve.run(() async {
                      await widget.onPlay(_resolved!);
                      return null;
                    }),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _diagnostic(String id, ProbeStep step) => ExpansionTile(
    key: ValueKey('$id:${step.label}:${step.status}'),
    dense: true,
    minTileHeight: 44,
    tilePadding: const EdgeInsets.symmetric(horizontal: Gap.lg),
    childrenPadding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
    shape: const Border(),
    collapsedShape: const Border(),
    leading: step.status == ProbeStatus.loading
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            step.status == ProbeStatus.ready
                ? Icons.check_circle_outline
                : Icons.error_outline,
            size: 18,
            color: stepColor(step.status),
          ),
    title: Row(
      children: [
        Expanded(child: Text(step.label)),
        const SizedBox(width: Gap.sm),
        Text(
          '${step.milliseconds ?? '…'} ms${step.statusCode == null ? '' : ' · HTTP ${step.statusCode}'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
    initiallyExpanded: step.status == ProbeStatus.error,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (step.url != null)
              SelectableText(
                step.url!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (step.error != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: SelectableText(
                  step.error!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _episodeChoices() => MelonPanel(
    padding: const EdgeInsets.all(Gap.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in _episodes.map((e) => e.line).toSet()) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Text(line, style: Theme.of(context).textTheme.titleSmall),
          ),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final episode in _episodes.where((e) => e.line == line))
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 36),
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                    backgroundColor: _episode == episode
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
                  onPressed: _resolve.busy
                      ? null
                      : () => _resolveEpisode(episode),
                  child: Text(episode.label),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
        ],
      ],
    ),
  );
}

final class _Entry {
  const _Entry(this.id, this.name, this.group, {this.instance});
  final String id, name, group;

  /// `null` for the PikPak transfer, which shares this page's switches.
  final SourceInstance? instance;
}

String snapshotDate(DateTime? value) {
  final parsed = value?.toLocal();
  if (parsed == null) return '未知时间';
  return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
}
