import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cancellation.dart';
import '../../domain/catalog.dart';
import '../../domain/release_traits.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../../features/appearance/appearance.dart';
import '../../features/acquisition/title_matching.dart';
import '../../features/subscriptions/subscription_controller.dart';
import '../../features/subscriptions/subscription_matcher.dart';
import '../acquisition/resource_widgets.dart';
import '../core/byte_units.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import '../discovery/schedule_timelines.dart';

/// The detail page's way to subscribe to a show still airing, or to see
/// and change its subscription.
class SubscribeButton extends StatelessWidget {
  const SubscribeButton({
    super.key,
    required this.controller,
    required this.subject,
    required this.preferredGroups,
    required this.onError,
    this.markWatching = MarkWatching.unavailable,
  });
  final SubscriptionController controller;
  final Subject subject;
  final List<String> Function() preferredGroups;
  final ValueChanged<Object> onError;
  final MarkWatching markWatching;

  /// Whether [subject] airs now or soon: on the week's schedule, or with an
  /// episode airing from two weeks ago on.
  static bool airing(SubscriptionController controller, Subject subject) {
    if (controller.airingsOf(subject.id).isNotEmpty) return true;
    final since = DateTime.now().subtract(const Duration(days: 14));
    return subject.episodes.any(
      (episode) => episode.main && (episode.aired?.isAfter(since) ?? false),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final subscription = controller.subscriptions[subject.id];
      if (subscription == null && !airing(controller, subject)) {
        return const SizedBox.shrink();
      }
      void open() => unawaited(
        showSubscription(
          context,
          controller: controller,
          subject: subject,
          preferredGroups: preferredGroups(),
          onError: onError,
          markWatching: markWatching,
        ),
      );
      if (subscription == null) {
        return OutlinedButton.icon(
          onPressed: open,
          icon: const Icon(Icons.notifications_none_rounded, size: 18),
          label: const Text('订阅更新'),
        );
      }
      final issue = controller.issueOf(subscription);
      return Tooltip(
        message: issue?.text ?? '新一话播出后自动缓存 · ${subscription.filter.label}',
        child: FilledButton.tonalIcon(
          onPressed: open,
          style: issue == null
              ? null
              : FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  foregroundColor: Theme.of(context)
                      .colorScheme
                      .onErrorContainer,
                ),
          icon: const Icon(Icons.notifications_active_rounded, size: 18),
          label: Text(issue == null ? '已订阅' : issue.late ?? '订阅出错'),
        ),
      );
    },
  );
}

/// A subscription's state in a few words: when the next episode airs, what
/// it waits for, or what needs the user, with [warn] set for the last.
({String text, bool warn}) subscriptionStatus(
  SubscriptionController controller,
  Subscription subscription,
) {
  if (controller.issueOf(subscription) case final issue?) {
    return (
      text: [?issue.episode?.label, issue.late ?? issue.text].join(' '),
      warn: true,
    );
  }
  if (subscription.finishedAt != null) return (text: '已完结 · 已订阅', warn: false);
  return switch (controller.nextOf(subscription)) {
    (_, final release?) when release.at.isAfter(DateTime.now()) => (
      text: '${releaseWhen(release).trim()} · 已订阅',
      warn: false,
    ),
    (final episode, _?) => (text: '${episode.label}等字幕组', warn: false),
    _ => (text: '已订阅', warn: false),
  };
}

/// Whether subscribing can also mark the show 在看 on Bangumi: not offered
/// while signed out, offered but off while syncing is paused.
enum MarkWatching { unavailable, paused, available }

/// Subscribes to [subject], or shows and changes its subscription: the
/// filter, what the user has to act on and what it did lately.
Future<void> showSubscription(
  BuildContext context, {
  required SubscriptionController controller,
  required Subject subject,
  required List<String> preferredGroups,
  required ValueChanged<Object> onError,
  MarkWatching markWatching = MarkWatching.unavailable,
}) => showMelonDialog<void>(
  context: context,
  builder: (context) => _SubscriptionDialog(
    controller: controller,
    subject: subject,
    preferredGroups: preferredGroups,
    onError: onError,
    markWatching: markWatching,
  ),
);

class _SubscriptionDialog extends StatefulWidget {
  const _SubscriptionDialog({
    required this.controller,
    required this.subject,
    required this.preferredGroups,
    required this.onError,
    required this.markWatching,
  });
  final SubscriptionController controller;
  final Subject subject;
  final List<String> preferredGroups;
  final ValueChanged<Object> onError;
  final MarkWatching markWatching;

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

enum _Part { groups, qualities, languages, forms }

/// Menu values standing for every group, the preferred ones and the ones
/// [smartGroups] picks.
const _anyGroup = '\u0000any',
    _preferred = '\u0000preferred',
    _smart = '\u0000smart';

/// A single-episode release of the show, as the search found it.
typedef _File = ({
  ReleaseCandidate candidate,
  ResourceTitleInfo info,
  Episode episode,
});

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  late final Subscription? subscription =
      widget.controller.subscriptions[widget.subject.id];
  late SubscriptionFilter filter =
      subscription?.filter ??
      widget.controller.preferences.defaultFilter(widget.preferredGroups);
  late final bool watching =
      widget.subject.collection?.status == CollectionStatus.watching;

  /// A new subscription marks the show 在看 unless unticked; a change
  /// only when ticked.
  late bool markWatching = subscription == null;

  /// Aired episodes the subscription could cache too.
  late final List<Episode> earlier = widget.controller.earlierEpisodes(
    widget.subject,
  );
  late bool cacheEarlier =
      subscription == null && widget.controller.preferences.cacheEarlier;
  final cancel = RequestCancellation();

  /// What the show's releases offer, as one search finds them.
  /// Groups as the resource search names them, by their most common
  /// spelling; the traditional and simplified spellings of one group count
  /// together.
  final groupCounts = <String, int>{},
      qualityCounts = <String, int>{},
      languageCounts = <String, int>{},
      formCounts = <String, int>{};

  /// Every release found, and the single-episode ones, the earliest
  /// published first.
  var releases = <ReleaseCandidate>[];
  var files = <_File>[];

  /// Why the search found nothing, when no site answered.
  String? searchError;
  bool searching = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    cancel.cancel();
    super.dispose();
  }

  Future<void> _search() async {
    void count(ReleaseSearchResult result) {
      if (!mounted) return;
      setState(() {
        final spellings = <String, int>{};
        for (final counts in [
          groupCounts,
          qualityCounts,
          languageCounts,
          formCounts,
        ]) {
          counts.clear();
        }
        final found = <(_File, DateTime?)>[];
        for (final candidate in result.candidates) {
          final info = describeResource(
            candidate.release.title,
            releaseGroups: candidate.release.releaseGroups,
          );
          void add(Map<String, int> counts, Iterable<String> values) {
            for (final value in values) {
              counts[value] = (counts[value] ?? 0) + 1;
            }
          }

          add(spellings, info.groups);
          add(qualityCounts, [?info.quality]);
          add(languageCounts, info.languages);
          add(formCounts, info.subtitleForms);
          if (info.batch || releaseRebroadcast(candidate.release.title)) {
            continue;
          }
          if (releaseEpisode(widget.subject, info) case final episode?) {
            found.add((
              (candidate: candidate, info: info, episode: episode),
              releasePublished(candidate.release.publishedAt),
            ));
          }
        }
        final byKey = <String, List<MapEntry<String, int>>>{};
        for (final entry in spellings.entries) {
          (byKey[groupKey(entry.key)] ??= []).add(entry);
        }
        for (final names in byKey.values) {
          names.sort((a, b) => b.value.compareTo(a.value));
          groupCounts[names.first.key] = names.fold(
            0,
            (sum, entry) => sum + entry.value,
          );
        }
        found.sort(
          (a, b) => (a.$2 ?? DateTime(0)).compareTo(b.$2 ?? DateTime(0)),
        );
        files = [for (final (file, _) in found) file];
        releases = result.candidates;
        searchError = switch (result.sources) {
          [] => '没有可用的 BT 资源站',
          final sources
              when sources.every(
                (source) => source.status == SearchStatus.error,
              ) =>
            '资源站都没有响应',
          _ => null,
        };
      });
    }

    try {
      count(
        await widget.controller.browse(
          widget.subject,
          onUpdate: count,
          cancel: cancel,
        ),
      );
    } on RequestCancelled {
      // The dialog closed.
    } catch (_) {
      // The menus still offer every choice, without counts.
      if (mounted) setState(() => searchError = '查找失败');
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => saving = true);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      widget.onError(e);
      if (mounted) setState(() => saving = false);
    }
  }

  /// Turns [value] on or off in the filter's selection of [part].
  void _toggle(_Part part, String value, bool on) => setState(() {
    Set<String> toggled(Set<String> values) =>
        on ? {...values, value} : ({...values}..remove(value));
    filter = switch (part) {
      _Part.groups => filter.copyWith(
        groups: toggled(filter.groups),
        smart: false,
      ),
      _Part.qualities => filter.copyWith(qualities: toggled(filter.qualities)),
      _Part.languages => filter.copyWith(languages: toggled(filter.languages)),
      _Part.forms => filter.copyWith(forms: toggled(filter.forms)),
    };
  });

  /// Whether group [name] counts: chosen by name, or among the preferred
  /// groups while they count.
  bool _on(String name) =>
      groupsMatch(filter.groups, [name]) ||
      (filter.preferred && groupsMatch([name], widget.preferredGroups));

  /// Turns group [name], one of the preferred ones, on or off. Turning one
  /// off while all of them count keeps the others by name; naming every
  /// preferred group counts them as the preferred groups again.
  void _togglePreferred(String name, bool on) => setState(() {
    final preferred = widget.preferredGroups;
    final groups = {...filter.groups};
    if (on) {
      groups.add(name);
    } else {
      if (filter.preferred) groups.addAll(preferred);
      groups.removeWhere((group) => groupsMatch([group], [name]));
    }
    final all = preferred.every((group) => groupsMatch(groups, [group]));
    if (all) groups.removeWhere((group) => groupsMatch([group], preferred));
    filter = filter.copyWith(groups: groups, preferred: all, smart: false);
  });

  /// Whether [info] meets the filter's quality and subtitles, or states
  /// nothing for them.
  bool _meets(ResourceTitleInfo info) =>
      resourceSelectionGaps(
        info,
        qualities: filter.qualities,
        languages: filter.languages,
        subtitleForms: filter.forms,
      ) !=
      null;

  /// How long after its episode aired [file] came out, when both times
  /// are known to the minute.
  Duration? _delay(_File file) {
    final raw = file.candidate.release.publishedAt ?? '';
    // A bare date says nothing about the hour.
    final published = raw.length > 10 ? releasePublished(raw) : null;
    final aired = widget.controller.airedAt(file.episode);
    if (published == null || aired == null) return null;
    final delay = published.difference(aired);
    return delay.isNegative ? null : delay;
  }

  /// What [record]'s files meeting the quality and subtitles are like: the
  /// latest one's tags and size, and how soon after airing they come out.
  String _groupSummary(GroupRecord record, ByteUnits units) {
    final latest = files
        .where(
          (file) =>
              groupsMatch(file.info.groups, [record.name]) && _meets(file.info),
        )
        .lastOrNull;
    return [
      if (latest != null) _fileSummary(latest, units),
      if (record.lag case final lag?) '播出后约 ${_span(lag)}',
    ].join(' · ');
  }

  /// `1080p MP4 简日内嵌 · 580 MB`.
  String _fileSummary(_File file, ByteUnits units) => [
    if (file.info.labels.isNotEmpty) file.info.labels.take(4).join(' '),
    resourceSizeLabel(file.candidate.release, units),
  ].join(' · ');

  /// The file the filter takes for each of the latest episodes, the
  /// latest first.
  List<ReleaseJudgement> _picks() =>
      judgeReleases(
          subject: widget.subject,
          filter: filter,
          candidates: releases,
          wanted: (_) => true,
          preferredGroups: widget.preferredGroups,
          aired: widget.controller.airedAt,
        ).where((judgement) => judgement.download).toList()
        ..sort((a, b) => b.episode!.sort.compareTo(a.episode!.sort));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final units = ByteUnitsScope.of(context);
    final subscription = this.subscription;
    final issue = subscription == null
        ? null
        : widget.controller.issueOf(subscription);
    final offerWatching =
        widget.markWatching != MarkWatching.unavailable && !watching;
    final canMark = widget.markWatching == MarkWatching.available;
    final changed =
        subscription != null &&
        (subscription.filter != filter ||
            (cacheEarlier && earlier.isNotEmpty) ||
            (offerWatching && canMark && markWatching));
    MelonFilterOption<String> counted(String value, Map<String, int> counts) =>
        MelonFilterOption(
          value,
          value,
          detail: searching && counts.isEmpty ? null : '${counts[value] ?? 0}',
        );
    final preferred = widget.preferredGroups;
    final records = groupRecords(
      subject: widget.subject,
      filter: filter,
      candidates: releases,
      aired: widget.controller.airedAt,
    );
    final judged = !searching && files.isNotEmpty;
    // Groups without a single-episode file meeting the quality and
    // subtitles, or usually a week late, leave the list unless chosen.
    bool worth(String name) => switch (records[groupKey(name)]) {
      null => !judged,
      final record => !((record.lag ?? Duration.zero) > slowGroupLag),
    };
    final found = {...groupCounts.keys};
    final groupNames = [
      for (final name in {...filter.groups, ...found})
        if (groupsMatch(filter.groups, [name]) || worth(name)) name,
    ];
    final hidden = found.length - groupNames.where(found.contains).length;
    int byPreference(String name) => groupsMatch([name], preferred) ? 0 : 1;
    groupNames.sort((a, b) {
      final first = byPreference(a).compareTo(byPreference(b));
      return first != 0
          ? first
          : (groupCounts[b] ?? 0).compareTo(groupCounts[a] ?? 0);
    });
    final ours = [
      for (final record in records.values)
        if (groupsMatch(record.credits, preferred)) record,
    ];
    final picked = smartGroups(records.values, preferred);
    String lagOf(Iterable<GroupRecord> chosen) => [
      if (fastestLag(chosen) case final lag?) '播出后约 ${_span(lag)}',
      chosen.map((record) => record.name).join('、'),
    ].join(' · ');
    final partly =
        !filter.preferred &&
        preferred.any((name) => groupsMatch(filter.groups, [name]));
    final subtitles = [
      ...resourceLanguages.where(filter.languages.contains),
      ...resourceSubtitleForms.where(filter.forms.contains),
    ];
    final menus = [
      MelonFilterMenu<String>(
        label: switch ((filter.groups.length, filter.preferred)) {
          _ when filter.smart => '智能选择字幕组',
          (0, false) => '不限字幕组',
          (0, true) => '偏好字幕组',
          (1, false) => filter.groups.single,
          (final count, final preferred) =>
            '${preferred ? '偏好和' : ''} $count 个字幕组'.trim(),
        },
        icon: Icons.groups_outlined,
        active: !filter.anyGroup,
        tooltip:
            '智能：每次检查时挑本作发布集数多、播出后发布快的字幕组，偏好的优先，最多三个。'
            '选了几个字幕组时，谁先发布就缓存谁的',
        sections: [
          MelonFilterSection([
            const MelonFilterOption(_anyGroup, '不限'),
            MelonFilterOption(
              _smart,
              '智能',
              subtitle: picked.isEmpty
                  ? judged
                        ? '本作还没有符合画质和字幕的发布'
                        : '按发布集数、发布快慢和偏好挑选'
                  : lagOf(picked),
            ),
            MelonFilterOption(
              _preferred,
              '偏好字幕组',
              detail: preferred.isEmpty
                  ? '未设置'
                  : searching && groupCounts.isEmpty
                  ? null
                  : '${groupCounts.entries.where((entry) => groupsMatch([entry.key], preferred)).fold(0, (sum, entry) => sum + entry.value)}',
              subtitle: preferred.isEmpty
                  ? '在 设置 › 字幕组 里设置'
                  : ours.isNotEmpty
                  ? lagOf(ours)
                  : judged
                  ? '本作还没有偏好字幕组符合画质和字幕的发布'
                  : null,
              enabled: preferred.isNotEmpty,
              mixed: partly,
            ),
          ]),
          MelonFilterSection(
            [
              for (final name in groupNames)
                MelonFilterOption(
                  name,
                  name,
                  detail: counted(name, groupCounts).detail,
                  subtitle: switch (records[groupKey(name)]) {
                    final record? => _groupSummary(record, units),
                    null when judged =>
                      groupCounts.containsKey(name)
                          ? '没有符合画质和字幕的单集文件'
                          : '没有找到本作的发布',
                    null => null,
                  },
                ),
            ],
            title: searching
                ? '正在查找本作的字幕组…'
                : groupCounts.isEmpty
                ? searchError ?? '没有找到本作的字幕组'
                : [
                    '本作的字幕组',
                    if (hidden > 0) '另有 $hidden 个不符合画质和字幕或发布太慢',
                  ].join(' · '),
          ),
        ],
        selected: {
          if (filter.anyGroup) _anyGroup,
          if (filter.smart) _smart,
          if (filter.preferred) _preferred,
          for (final name in groupNames)
            if (_on(name)) name,
          ...filter.groups,
        },
        onToggle: (value, on) => switch (value) {
          _anyGroup => setState(
            () => filter = filter.copyWith(
              groups: {},
              preferred: false,
              smart: false,
            ),
          ),
          _smart => setState(
            () => filter = filter.copyWith(
              groups: {},
              preferred: false,
              smart: on,
            ),
          ),
          _preferred => setState(
            () => filter = filter.copyWith(
              groups: {
                for (final group in filter.groups)
                  if (!groupsMatch([group], preferred)) group,
              },
              preferred: on,
              smart: false,
            ),
          ),
          _ when groupsMatch([value], preferred) => _togglePreferred(value, on),
          _ => _toggle(_Part.groups, value, on),
        },
      ),
      MelonFilterMenu<String>(
        label: filter.qualities.isEmpty
            ? '不限画质'
            : resourceQualities.where(filter.qualities.contains).join('、'),
        icon: Icons.high_quality_outlined,
        sections: [
          MelonFilterSection([
            for (final value in resourceQualities)
              counted(value, qualityCounts),
          ]),
        ],
        selected: filter.qualities,
        onToggle: (value, on) => _toggle(_Part.qualities, value, on),
      ),
      MelonFilterMenu<String>(
        label: switch (subtitles) {
          [] => '不限字幕',
          ['简体'] => '简体（含简繁、简日）',
          ['繁体'] => '繁体（含简繁、繁日）',
          _ => subtitles.join('、'),
        },
        icon: Icons.subtitles_outlined,
        active: subtitles.isNotEmpty,
        tooltip: '勾选“简体”也包含简繁、简日双语',
        sections: [
          MelonFilterSection([
            for (final value in resourceLanguages)
              counted(value, languageCounts),
          ], title: '字幕语言'),
          MelonFilterSection([
            for (final value in resourceSubtitleForms)
              counted(value, formCounts),
          ], title: '字幕形式'),
        ],
        selected: {...filter.languages, ...filter.forms},
        onToggle: (value, on) => _toggle(
          resourceLanguages.contains(value) ? _Part.languages : _Part.forms,
          value,
          on,
        ),
      ),
    ];
    final picks = _picks();
    final tabular = small?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget check({
      required bool value,
      required ValueChanged<bool>? onChanged,
      required String title,
      String? subtitle,
    }) => CheckboxListTile(
      value: value,
      onChanged: onChanged == null
          ? null
          : (value) => setState(() => onChanged(value ?? false)),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
    );
    return AlertDialog(
      title: Text(subscription == null ? '订阅更新' : '已订阅'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新一话播出后，自动缓存第一个符合筛选的文件', style: small),
            if (issue != null) ...[
              const SizedBox(height: Gap.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: controlBorderRadius,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          issue.text,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                      if (issue.episode case final episode?)
                        TextButton(
                          onPressed: () => _run(
                            () => widget.controller.keepWaiting(
                              subscription!.subjectId,
                              episode,
                            ),
                          ),
                          child: const Text('继续等'),
                        )
                      else
                        TextButton(
                          onPressed: () => _run(
                            () => widget.controller.retry(
                              subscription!.subjectId,
                            ),
                          ),
                          child: const Text('重试'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: Gap.lg),
            Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: menus),
            const SizedBox(height: Gap.md),
            Material(
              color: insetSurface(context),
              borderRadius: controlBorderRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: picks.isEmpty
                    ? Text(
                        searching
                            ? '正在查找符合筛选的文件…'
                            : searchError ?? '最近没有符合筛选的文件',
                        style: small,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // A preview: what the filter takes for episodes
                          // already out, as it would for the next.
                          Text(
                            '按现在的筛选，最近几话会选这些文件',
                            style: small?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: Gap.xs),
                          for (final pick in picks.take(3))
                            _PickRow(
                              episode: pick.episode!.label,
                              group: resourceGroupLabel(pick.info),
                              file: _fileSummary((
                                candidate: pick.candidate,
                                info: pick.info,
                                episode: pick.episode!,
                              ), units),
                              delay: switch (_delay((
                                candidate: pick.candidate,
                                info: pick.info,
                                episode: pick.episode!,
                              ))) {
                                final delay? => '播出后 ${_span(delay)}发布',
                                null => '',
                              },
                              title: pick.candidate.release.title,
                              style: tabular,
                            ),
                        ],
                      ),
              ),
            ),
            if (earlier.isNotEmpty || offerWatching)
              const SizedBox(height: Gap.sm),
            if (earlier.isNotEmpty)
              check(
                value: cacheEarlier,
                onChanged: (value) => cacheEarlier = value,
                title:
                    '${subscription == null ? '同时' : ''}缓存已播出'
                    '${widget.subject.episodes.any((e) => e.watched) ? '、还没看' : ''}'
                    '的${episodeRange(earlier)}',
              ),
            if (offerWatching)
              check(
                value: canMark && markWatching,
                onChanged: canMark ? (value) => markWatching = value : null,
                title: '在 Bangumi 标成在看',
                subtitle: canMark ? null : 'Bangumi 同步暂停了，到 设置 › 账户与同步 处理',
              ),
            if (subscription != null && subscription.events.isNotEmpty) ...[
              const SizedBox(height: Gap.lg),
              Text('订阅动态', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: Gap.xs),
              for (final event in subscription.events.take(4))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(_eventTime(event.at), style: tabular),
                      ),
                      Expanded(
                        child: Text(
                          event.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: small?.copyWith(
                            color: event.kind == SubscriptionEventKind.failed
                                ? scheme.error
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (subscription != null)
          TextButton(
            onPressed: saving
                ? null
                : () => _run(
                    () => widget.controller.unsubscribe(subscription.subjectId),
                  ),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('取消订阅'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(subscription == null || !changed ? '关闭' : '不保存'),
        ),
        if (subscription == null || changed)
          FilledButton(
            onPressed: saving
                ? null
                : () => _run(
                    () => widget.controller.subscribe(
                      widget.subject,
                      filter,
                      earlier: earlier.isEmpty
                          ? null
                          : cacheEarlier
                          ? earlier
                          : const [],
                      markWatching: offerWatching && canMark && markWatching,
                    ),
                  ),
            child: Text(subscription == null ? '订阅' : '保存'),
          ),
      ],
    );
  }
}

/// One episode's chosen file in the preview: the episode, the group, what
/// the file is like and how soon it came out; the full title on hover.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.episode,
    required this.group,
    required this.file,
    required this.delay,
    required this.title,
    required this.style,
  });
  final String episode, group, file, delay, title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: title,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(episode, style: style)),
          Flexible(
            child: Text(
              group,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            flex: 2,
            child: Text(
              file,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (delay.isNotEmpty) ...[
            const SizedBox(width: Gap.sm),
            Text(delay, style: style),
          ],
        ],
      ),
    ),
  );
}

/// `40 分钟`, `3 小时` or `2 天`.
String _span(Duration duration) => switch (duration) {
  _ when duration < const Duration(hours: 1) =>
    '${duration.inMinutes.clamp(1, 59)} 分钟',
  _ when duration < const Duration(hours: 48) =>
    '${(duration.inMinutes / 60).round()} 小时',
  _ => '${duration.inDays} 天',
};

/// `14:20`, `昨天 09:10`, `10月28日 21:00`.
String _eventTime(DateTime time) {
  final at = time.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final clock =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  return switch (today.difference(day).inDays) {
    0 => clock,
    1 => '昨天 $clock',
    _ => '${at.month}月${at.day}日 $clock',
  };
}

/// Asks once, on the first close with subscriptions, whether closing the
/// window keeps the app running in the background.
Future<CloseAction?> askCloseAction(
  BuildContext context, {
  required int shows,
}) => showMelonDialog<CloseAction>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('关闭窗口后继续在后台运行？'),
    content: SizedBox(
      width: 400,
      child: Text(
        '你订阅了 $shows 部番。留在后台时，MelonBanG 会在新一话播出后检查并缓存，'
        '播放会停止。之后可以在 设置 › 订阅与缓存 里改。',
        style: const TextStyle(fontSize: 13, height: 1.6),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, CloseAction.quit),
        child: const Text('退出'),
      ),
      FilledButton(
        autofocus: true,
        onPressed: () => Navigator.pop(context, CloseAction.background),
        child: const Text('留在后台'),
      ),
    ],
  ),
);
