import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/json.dart';
import '../../data/online_sources/repository.dart';
import '../../data/pikpak.dart';
import '../../data/sources.dart';
import '../core/action_feedback.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';

class SourcesPage extends StatefulWidget {
  const SourcesPage({
    super.key,
    required this.repository,
    required this.sources,
    required this.pikpak,
    required this.onPlay,
  });
  final OnlineSourceRepository repository;
  final SourceRepository sources;
  final PikPakClient pikpak;
  final Future<void> Function(Json) onPlay;
  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  final _update = ActionFeedback(),
      _probe = ActionFeedback(),
      _search = ActionFeedback(),
      _resolve = ActionFeedback(),
      _runtimeIssue = ActionFeedback(),
      _engineIssue = ActionFeedback();
  final _query = TextEditingController();
  String? _selected;
  bool _narrowDetail = false;
  List<Json> _subjects = [], _episodes = [];
  Json? _subject, _resolved;
  int _generation = 0;
  OnlineSourceRepository get repository => widget.repository;
  List<Json> get entries => [
    ...repository.rules,
    {
      'id': 'dmhy',
      'name': '动漫花园',
      'engine': 'RSS',
      'website': 'https://share.dmhy.org',
      'group': 'BT 索引',
    },
    {
      'id': 'mikan',
      'name': '蜜柑计划',
      'engine': 'RSS',
      'website': 'https://mikanani.me',
      'group': 'BT 索引',
    },
    {
      'id': 'pikpak',
      'name': 'PikPak',
      'engine': '网盘',
      'website': 'https://mypikpak.com',
      'group': '网盘',
    },
  ];
  @override
  void initState() {
    super.initState();
    unawaited(repository.refreshRules().catchError((Object _) {}));
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

  String label(String status) => switch (status) {
    'ready' => '正常',
    'partial' => '部分失败',
    'error' => '失效',
    'verification' => '需要验证',
    'update' => '需要更新应用',
    'disabled' => '已停用',
    _ => '未检查',
  };
  Color color(String status) => switch (status) {
    'ready' => mint,
    'error' => coral,
    'partial' || 'verification' || 'update' => gold,
    _ => sky,
  };
  Future<void> _probeSource(String id) => repository.probe(
    id,
    external: switch (id) {
      'dmhy' || 'mikan' => () async {
        final uri = id == 'dmhy'
            ? Uri.https('share.dmhy.org', '/topics/rss/rss.xml', {
                'keyword': '葬送的芙莉莲',
              })
            : Uri.https('mikanani.me', '/RSS/Search', {'searchstr': '葬送的芙莉莲'});
        repository.results[id]?.last['url'] = uri.toString();
        final response = await repository.api.send(
          uri,
          headers: {'Accept': 'application/rss+xml,application/xml'},
        );
        final rows = parseRss(utf8.decode(response.bodyBytes), base: uri);
        if (rows.isEmpty) throw StateError('RSS 暂无匹配的资源');
      },
      'pikpak' => () async {
        if (!widget.pikpak.isSignedIn || widget.pikpak.needsAuthorization) {
          throw StateError('请在设置中登录 PikPak 后重试');
        }
        repository.results[id]?.last['url'] =
            'https://api-drive.mypikpak.com/drive/v1/files';
        try {
          await widget.pikpak.files('');
        } on PikPakCaptchaRequired catch (error) {
          throw SourceVerificationRequired(error.url.toString());
        }
      },
      _ => null,
    },
  );
  void _select(String id) {
    _generation++;
    setState(() {
      _selected = id;
      _narrowDetail = true;
      _subjects = [];
      _episodes = [];
      _subject = null;
      _resolved = null;
    });
  }

  void _manualSearch(String id) {
    if (_search.busy) return;
    final generation = ++_generation;
    _search.run(() async {
      final query = _query.text.trim();
      if (query.isEmpty) return '请输入番名';
      final rows = await repository.search(id, [query], refresh: true);
      if (mounted && generation == _generation) {
        setState(() {
          _subjects = rows;
          _subject = null;
          _episodes = [];
          _resolved = null;
        });
      }
      return null;
    });
  }

  void _loadEpisodes(String id, Json site) {
    if (_search.busy) return;
    final generation = ++_generation;
    _search.run(() async {
      final rows = await repository.episodes(id, site);
      if (mounted && generation == _generation) {
        setState(() {
          _subject = site;
          _episodes = rows;
          _resolved = null;
        });
      }
      return null;
    });
  }

  void _resolveEpisode(Json episode) {
    if (_resolve.busy) return;
    final generation = _generation;
    setState(() => _resolved = null);
    _resolve.run(() async {
      final value = await repository.resolve({'ref': episode['ref']});
      if (mounted && generation == _generation) {
        setState(() => _resolved = value);
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([repository, _search, _resolve]),
    builder: (context, _) {
      final selected = entries
          .where(
            (entry) =>
                entry['id'] ==
                (_selected ?? repository.rules.firstOrNull?['id'] ?? 'dmhy'),
          )
          .firstOrNull;
      final hasUpdate = repository.rules.any(
        (rule) => number(rule['minEngine']) > onlineEngineVersion,
      );
      _engineIssue.issue = hasUpdate ? '部分视频源需要更新应用后才能使用' : null;
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
                    Text('视频源', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: Gap.sm),
                    Wrap(
                      spacing: Gap.md,
                      runSpacing: Gap.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '规则 ${repository.version} · ${repository.ruleOrigin}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '更新 ${snapshotDate(repository.snapshot['updatedAt'])}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        FeedbackButton(
                          feedback: _update,
                          label: '检查更新',
                          runningLabel: '检查中',
                          successLabel: '已更新',
                          icon: Icons.refresh,
                          onPressed: () => _update.run(() async {
                            await repository.refreshRules();
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
                                  repository.isEnabled('${e['id']}') &&
                                  e['disabled'] != true &&
                                  number(e['minEngine']) <= onlineEngineVersion,
                            )) {
                              await _probeSource('${entry['id']}');
                            }
                            return null;
                          }),
                        ),
                      ],
                    ),
                    FeedbackIssue(
                      feedback: _update,
                      onRetry: () => _update.run(() async {
                        await repository.refreshRules();
                        return null;
                      }),
                    ),
                    if (repository.updateIssue != null && _update.issue == null)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.sm),
                        child: Text(
                          repository.updateIssue!,
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
                          SizedBox(width: 280, child: _list(selected)),
                          const VerticalDivider(width: 1),
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
  Widget _list(Json? selected) => ListView(
    padding: const EdgeInsets.fromLTRB(pageGutter, 0, Gap.md, Gap.lg),
    children: [
      for (final group in ['在线源', 'BT 索引', '网盘']) ...[
        SectionTitle(title: group, top: Gap.sm),
        for (final entry in entries.where(
          (e) => (e['group'] ?? '在线源') == group,
        ))
          ListTile(
            selected: selected?['id'] == entry['id'],
            title: Text('${entry['name']}'),
            subtitle: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: MelonBadge(
                  label(repository.status('${entry['id']}')),
                  color: color(repository.status('${entry['id']}')),
                ),
              ),
            ),
            trailing: Switch(
              value:
                  repository.isEnabled('${entry['id']}') &&
                  entry['disabled'] != true,
              onChanged: entry['disabled'] == true
                  ? null
                  : (value) => repository.setEnabled('${entry['id']}', value),
            ),
            onTap: () => _select('${entry['id']}'),
          ),
      ],
    ],
  );
  Widget _details(Json entry, {bool narrow = false}) {
    final id = '${entry['id']}';
    final online = entry['group'] == null;
    final domain = online
        ? repository.currentDomain(id)
        : '${entry['website']}';
    _runtimeIssue.issue = repository.errors[id];
    return ListView(
      padding: const EdgeInsets.fromLTRB(pageGutter, 0, pageGutter, 40),
      children: [
        FeedbackIssue(
          feedback: _runtimeIssue,
          onRetry: () => _probe.run(() async {
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
          title: '${entry['name']}',
          top: Gap.sm,
          trailing: MelonBadge(
            label(repository.status(id)),
            color: color(repository.status(id)),
          ),
        ),
        MelonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('当前域名：$domain'),
              const SizedBox(height: Gap.sm),
              Text(
                '引擎：${entry['engine']}${online ? ' · 规则 ${repository.version}' : ''}',
              ),
              const SizedBox(height: Gap.sm),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('${entry['website'] ?? domain}'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('在浏览器打开站点'),
              ),
            ],
          ),
        ),
        SectionTitle(
          title: '测试结果',
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
        if (repository.results[id] case final steps?) ...[
          for (final step in steps)
            Card(
              child: ExpansionTile(
                leading: step['status'] == 'loading'
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        step['status'] == 'ready'
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: color('${step['status']}'),
                      ),
                title: Text('${step['label']}'),
                subtitle: Text(
                  '${step['milliseconds'] ?? '…'} ms${step['statusCode'] == null ? '' : ' · HTTP ${step['statusCode']}'}',
                ),
                initiallyExpanded: step['status'] == 'error',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (step['url'] != null)
                          SelectableText('${step['url']}'),
                        if (step['error'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: Gap.sm),
                            child: SelectableText(
                              '${step['error']}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ] else
          const Text('健康状态只保存在本次运行中。点击测试查看搜索与播放链路。'),
        if (online) ...[
          const SectionTitle(title: '手动试搜'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  decoration: const InputDecoration(hintText: '输入番名'),
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
          for (final site in _subjects)
            ListTile(
              title: Text('${site['title']}'),
              subtitle: Text('${site['year'] ?? ''}'),
              selected: _subject?['id'] == site['id'],
              trailing: const Icon(Icons.chevron_right),
              onTap: _search.busy ? null : () => _loadEpisodes(id, site),
            ),
          if (_subject != null)
            SectionTitle(
              title: '${_subject!['title']} · ${_episodes.length} 个播放入口',
            ),
          for (final episode in _episodes)
            ListTile(
              title: Text('${episode['label']}'),
              subtitle: Text('${episode['line']}'),
              trailing: const Icon(Icons.link),
              onTap: _resolve.busy ? null : () => _resolveEpisode(episode),
            ),
          FeedbackIssue(
            feedback: _resolve,
            onRetry: () {
              if (_episodes.isNotEmpty) _resolveEpisode(_episodes.first);
            },
          ),
          if (_resolved != null)
            MelonPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText('${_resolved!['url']}'),
                  const SizedBox(height: Gap.sm),
                  if (_resolved!['playlist'] != null)
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
}

String snapshotDate(dynamic value) {
  final parsed = DateTime.tryParse('$value')?.toLocal();
  if (parsed == null) return '$value';
  return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
}
