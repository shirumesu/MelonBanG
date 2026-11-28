import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/cancellation.dart';
import '../../core/error_message.dart';
import '../../core/notices.dart';
import '../../domain/catalog.dart';
import '../../domain/release_traits.dart';
import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../../features/appearance/appearance.dart';
import '../../features/acquisition/online_candidates.dart';
import '../../features/subscriptions/subscription_controller.dart';
import '../../features/subscriptions/subscription_matcher.dart';
import '../../features/tracking/tracking_controller.dart';
import '../acquisition/resource_labels.dart';
import '../core/action_feedback.dart';
import '../core/notice_cards.dart';
import '../core/byte_units.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import '../core/tone.dart';
import '../discovery/release_labels.dart';

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
      final scheme = Theme.of(context).colorScheme;
      return Tooltip(
        message:
            issue?.text ??
            '${subscription.paused ? '本机不缓存' : '自动缓存新一话'}\n'
                '${subscription.filter.label}',
        child: FilledButton.tonalIcon(
          onPressed: open,
          style: switch (issue) {
            null => null,
            // An episode out late is something to know, not a failure.
            SubscriptionIssue(episode: _?) => FilledButton.styleFrom(
              backgroundColor: scheme.tertiaryContainer,
              foregroundColor: scheme.onTertiaryContainer,
            ),
            _ => FilledButton.styleFrom(
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
            ),
          },
          icon: const Icon(Icons.notifications_active_rounded, size: 18),
          label: Text(issue == null ? '已订阅' : issue.late ?? '订阅出错'),
        ),
      );
    },
  );
}

/// A subscription's state in a few words: when the next episode airs, what
/// it waits for, or what needs the user, with `warn` set for the last and
/// `late` when that is an episode out later than usual, not a failure.
({String text, bool warn, bool late}) subscriptionStatus(
  SubscriptionController controller,
  Subscription subscription,
) {
  if (controller.issueOf(subscription) case final issue?) {
    return (
      text: [?issue.episode?.label, issue.late ?? issue.text].join(' '),
      warn: true,
      late: issue.episode != null,
    );
  }
  if (subscription.finishedAt != null) {
    return (text: '已完结', warn: false, late: false);
  }
  if (subscription.paused) {
    return (text: '本机不缓存', warn: false, late: false);
  }
  return switch (controller.nextOf(subscription)) {
    (_, final release?) when release.at.isAfter(DateTime.now()) => (
      text: '${releaseWhen(release)}更新',
      warn: false,
      late: false,
    ),
    (final episode, _?) => (
      text: '${episode.label}等字幕组',
      warn: false,
      late: false,
    ),
    _ => (text: '已订阅', warn: false, late: false),
  };
}

/// Whether subscribing can also mark the show 在看 on Bangumi: not offered
/// while signed out, offered but off while syncing is paused.
enum MarkWatching { unavailable, paused, available }

MarkWatching markWatchingFor(TrackingController personal) =>
    personal.profile == null
    ? MarkWatching.unavailable
    : personal.needsAuthorization || personal.sessionExpired
    ? MarkWatching.paused
    : MarkWatching.available;

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

/// What the filter takes for an episode: a group's release, or an online
/// entry filling in for one.
typedef _Pick = ({
  Episode episode,
  ReleaseJudgement? release,
  OnlineRelease? online,
});

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  /// The subscription when the dialog opened. The dialog follows the live
  /// one, which a check may end meanwhile; [earlier] and [cached] stay as
  /// they were when it opened.
  late final Subscription? opened =
      widget.controller.subscriptions[widget.subject.id];
  late SubscriptionFilter filter =
      opened?.filter ??
      widget.controller.preferences.defaultFilter(widget.preferredGroups);
  late final bool watching =
      widget.subject.collection?.status == CollectionStatus.watching;

  /// A new subscription marks the show 在看 unless unticked; a change
  /// only when ticked.
  late bool markWatching = opened == null;

  /// Aired episodes the subscription could cache too.
  late final List<Episode> earlier = widget.controller.earlierEpisodes(
    widget.subject,
  );

  /// Aired episodes left out of [earlier] as they have a cache already.
  late final List<Episode> cached = widget.controller.cachedEarlier(
    widget.subject,
  );
  late bool cacheEarlier =
      opened == null && widget.controller.preferences.cacheEarlier;
  final cancel = RequestCancellation();

  /// Every release the search found, and what they offer.
  var releases = <ReleaseCandidate>[];
  late var survey = surveyReleases(widget.subject, const []);

  /// Why the search found nothing: no site answered, or it failed.
  String? searchError;
  bool searching = true;
  bool saving = false;

  /// What the online sources list, searched once the filter includes them.
  var onlineFound = <OnlineRelease>[];
  bool onlineSearched = false, onlineSearching = false;

  /// Set when no online source answered.
  String? onlineError;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
    if (filter.online) _searchOnline();
  }

  /// Searches the online sources, once.
  void _searchOnline() {
    if (onlineSearched) return;
    onlineSearched = true;
    onlineSearching = true;
    void show(OnlineReleaseResult result) {
      if (!mounted) return;
      setState(() {
        onlineFound = result.releases;
        onlineError =
            result.sources.isNotEmpty &&
                result.sources.every(
                  (source) => source.status == SearchStatus.error,
                )
            ? '在线源都没有响应，检查时会再试'
            : null;
      });
    }

    unawaited(() async {
      try {
        show(
          await widget.controller.browseOnline(
            widget.subject,
            onUpdate: show,
            cancel: cancel,
          ),
        );
      } on RequestCancelled {
        // The dialog closed.
      } finally {
        if (mounted) setState(() => onlineSearching = false);
      }
    }());
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
        releases = result.candidates;
        survey = surveyReleases(widget.subject, result.candidates);
        searchError = switch (result.sources) {
          [] => '没有可用的资源站',
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
    } catch (error) {
      // The menus still offer every choice, without counts.
      if (mounted) {
        setState(() => searchError = '查找失败：${errorMessage(error)}');
      }
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

  /// Ends [subscription], with a way back: its book and events go with it.
  void _unsubscribe(Subscription subscription) {
    final notices = NoticesScope.of(context);
    final controller = widget.controller;
    final onError = widget.onError;
    unawaited(
      _run(() async {
        await controller.unsubscribe(subscription.subjectId);
        showMessage(
          notices,
          '已取消订阅 ${subscription.title}，缓存的剧集保留',
          actionLabel: '撤销',
          onAction: () => controller.restore(subscription).catchError(onError),
        );
      }),
    );
  }

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
      filter.gaps(info, survey.subtitlesOf) != null;

  /// How long after its episode aired [file] came out, when both times
  /// are known to the minute.
  Duration? _delay(ReleaseFile file) {
    final raw = file.candidate.release.publishedAt ?? '';
    // A bare date says nothing about the hour.
    final published = raw.length > 10 ? releasePublished(raw) : null;
    final aired = widget.controller.airedAt(file.episode);
    if (published == null || aired == null) return null;
    final delay = published.difference(aired);
    return delay.isNegative ? null : delay;
  }

  /// What [record]'s files meeting the quality and subtitles are like: how
  /// soon after airing they come out, then the latest one's tags and size.
  String _groupSummary(GroupRecord record, ByteUnits units) {
    final latest = survey.files
        .where(
          (file) =>
              groupsMatch(file.info.groups, [record.name]) && _meets(file.info),
        )
        .lastOrNull;
    return [
      if (record.lag case final lag?) '播出后约 ${_span(lag)}',
      if (latest != null) ...[
        if (_fileLabels(latest).isNotEmpty) _fileLabels(latest),
        resourceSizeLabel(latest.candidate.release, units),
      ],
    ].join('  ');
  }

  /// `1080p MP4 简日内嵌`.
  String _fileLabels(ReleaseFile file) => file.info.labels.take(4).join(' ');

  /// The file the filter takes for each of the latest episodes, the
  /// latest first: a group's, else an online entry as a check would fill
  /// in with.
  List<_Pick> _picks() {
    final chosen = judgeReleases(
      subject: widget.subject,
      filter: filter,
      candidates: releases,
      wanted: (_) => true,
      preferredGroups: widget.preferredGroups,
      aired: widget.controller.airedAt,
    ).where((judgement) => judgement.download).toList();
    final online = pickOnline(
      filter: filter,
      releases: onlineFound,
      wanted: (_) => true,
      chosen: {for (final judgement in chosen) judgement.episode!.id},
    );
    return [
      for (final judgement in chosen)
        (episode: judgement.episode!, release: judgement, online: null),
      for (final entry in online.values)
        (episode: entry.episode, release: null, online: entry),
    ]..sort((a, b) => b.episode.sort.compareTo(a.episode.sort));
  }

  /// [pick] in the preview; an online entry names its site and quality.
  Widget _pickRow(
    _Pick pick,
    ByteUnits units,
    TextStyle? style,
  ) => switch (pick) {
    (release: final release?, online: _, episode: final episode) => MotionSwap(
      value: release.candidate.candidateId,
      scale: 1,
      alignment: Alignment.centerLeft,
      child: _PickRow(
        episode: episode.label,
        group: resourceGroupLabel(release.info),
        file: _fileLabels((
          candidate: release.candidate,
          info: release.info,
          episode: episode,
        )),
        size: resourceSizeLabel(release.candidate.release, units),
        delay: switch (_delay((
          candidate: release.candidate,
          info: release.info,
          episode: episode,
        ))) {
          final delay? => '播出后 ${_span(delay)}发布',
          null => '',
        },
        title: release.candidate.release.title,
        style: style,
      ),
    ),
    (online: final online?, release: _, episode: final episode) => MotionSwap(
      value: online.identity,
      scale: 1,
      alignment: Alignment.centerLeft,
      child: _PickRow(
        episode: episode.label,
        group: online.source.name,
        file: [?online.quality, '在线'].join(' '),
        size: '',
        delay: '',
        title: online.title,
        style: style,
      ),
    ),
    _ => throw StateError('预览的一集既没有字幕组文件也没有在线源'),
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _dialog(context),
  );

  Widget _dialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final units = ByteUnitsScope.of(context);
    final subscription = widget.controller.subscriptions[widget.subject.id];
    // Ended while open, such as by a check finding the show gone.
    final ended = opened != null && subscription == null;
    final issue = subscription == null
        ? null
        : widget.controller.issueOf(subscription);
    final checking =
        subscription != null &&
        widget.controller.checking(subscription.subjectId);
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
    final judged = !searching && survey.files.isNotEmpty;
    // Groups without a single-episode file meeting the quality and
    // subtitles, or usually a week late, leave the list unless chosen.
    bool worth(String name) => switch (records[groupKey(name)]) {
      null => !judged,
      final record => !((record.lag ?? Duration.zero) > slowGroupLag),
    };
    final found = {...survey.groups.keys};
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
          : (survey.groups[b] ?? 0).compareTo(survey.groups[a] ?? 0);
    });
    final ours = [
      for (final record in records.values)
        if (groupsMatch(record.credits, preferred)) record,
    ];
    // The smart choice goes by files sure to meet the filter, as checks do.
    final picked = smartGroups(
      groupRecords(
        subject: widget.subject,
        filter: filter,
        candidates: releases,
        aired: widget.controller.airedAt,
        stated: true,
      ).values,
      preferred,
    );
    String lagOf(Iterable<GroupRecord> chosen) => [
      chosen.map((record) => record.name).join('、'),
      if (fastestLag(chosen) case final lag?) '通常播出后约 ${_span(lag)}',
    ].join('  ');
    final partly =
        !filter.preferred &&
        preferred.any((name) => groupsMatch(filter.groups, [name]));
    final subtitles = {...filter.languages, ...filter.forms};
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
            '智能：按更新快慢、发布集数和偏好自动选择字幕组，最多三个；'
            '选择多个时缓存最先发布的',
        sections: [
          MelonFilterSection([
            const MelonFilterOption(_anyGroup, '不限'),
            MelonFilterOption(
              _smart,
              '智能',
              subtitle: picked.isEmpty
                  ? judged
                        ? '本作还没有符合画质和字幕的发布'
                        : '按更新快慢、发布集数和偏好挑选'
                  : lagOf(picked),
            ),
            MelonFilterOption(
              _preferred,
              '偏好字幕组',
              detail: preferred.isEmpty
                  ? '未设置'
                  : searching && survey.groups.isEmpty
                  ? null
                  : '${survey.groups.entries.where((entry) => groupsMatch([entry.key], preferred)).fold(0, (sum, entry) => sum + entry.value)}',
              subtitle: preferred.isEmpty
                  ? '在 设置 › 字幕组 中设置'
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
                  detail: counted(name, survey.groups).detail,
                  subtitle: switch (records[groupKey(name)]) {
                    final record? => _groupSummary(record, units),
                    null when judged =>
                      survey.groups.containsKey(name)
                          ? '没有符合画质和字幕的单集文件'
                          : '没有找到本作的发布',
                    null => null,
                  },
                ),
            ],
            title: searching
                ? '正在查找本作的字幕组…'
                : survey.groups.isEmpty
                ? searchError ?? '没有找到本作的字幕组'
                : [
                    '本作的字幕组',
                    // The section title takes text only, so the hidden
                    // count follows two spaces apart.
                    if (hidden > 0) '已隐藏 $hidden 个',
                  ].join('  '),
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
              counted(value, survey.qualities),
          ]),
        ],
        selected: filter.qualities,
        onToggle: (value, on) => _toggle(_Part.qualities, value, on),
      ),
      MelonFilterMenu<String>(
        label: subtitles.isEmpty ? '不限字幕' : subtitleFilterSummary(subtitles),
        icon: Icons.subtitles_outlined,
        active: subtitles.isNotEmpty,
        tooltip: '按字幕语言和能否关闭筛选',
        sections: subtitleFilterSections(
          (value, label, help) => MelonFilterOption(
            value,
            label,
            help: help,
            detail: counted(value, survey.subtitles).detail,
          ),
        ),
        selected: subtitles,
        onToggle: (value, on) => _toggle(
          resourceSubtitleForms.contains(value) ? _Part.forms : _Part.languages,
          value,
          on,
        ),
      ),
    ];
    final picks = _picks();
    final onlineSources = widget.controller.onlineSources;
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
    final intro = ended
        ? '这部番的订阅已取消，缓存的剧集保留'
        : subscription == null
        ? '新一话播出后，自动缓存第一个符合筛选的文件'
        : null;
    return AlertDialog(
      // A short window scrolls the filter, preview and events.
      scrollable: true,
      title: ended || subscription == null
          ? Text(ended ? '已退订' : '订阅更新')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.subject.title),
                const SizedBox(height: 2),
                Text(
                  subscriptionStatus(widget.controller, subscription).text,
                  style: small?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // How subscribing works is said before subscribing only.
            if (intro != null) ...[
              Text(intro, style: small),
              const SizedBox(height: Gap.lg),
            ],
            IssueBanner(
              issue: issue?.text,
              // An episode out late is something to know, not a failure.
              tone: issue?.episode != null
                  ? NoticeTone.warning
                  : NoticeTone.failed,
              actions: [
                if (issue?.episode case final episode?)
                  NoticeAction(
                    '继续等',
                    () => _run(
                      () => widget.controller.keepWaiting(
                        subscription!.subjectId,
                        episode,
                      ),
                    ),
                  )
                else
                  NoticeAction(
                    '重试',
                    () => _run(
                      () => widget.controller.retry(subscription!.subjectId),
                    ),
                  ),
              ],
            ),
            Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: menus),
            const SizedBox(height: Gap.md),
            Material(
              color: insetSurface(context),
              borderRadius: controlBorderRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.md,
                  vertical: Gap.sm,
                ),
                // Sites answer one by one, so the preview changes as they
                // do: it resizes and crossfades rather than jumping.
                child: AnimatedSize(
                  duration: motionDuration(context, 220),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topLeft,
                  child: MotionSwap(
                    value: picks.isEmpty,
                    scale: 1,
                    alignment: Alignment.topLeft,
                    child: picks.isEmpty
                        ? switch (searchError) {
                            final error? when !searching && !onlineSearching =>
                              InlineIssue(error),
                            _ => Text(
                              searching || onlineSearching
                                  ? '正在查找符合筛选的文件…'
                                  : '最近没有符合筛选的文件',
                              style: small,
                            ),
                          }
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // What the filter takes for episodes already
                              // out, as it would for the next.
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '按当前筛选，最近几话将缓存',
                                      style: small?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  // Until every site answers, the picks
                                  // may still change.
                                  DelayedBusy(
                                    busy: searching || onlineSearching,
                                    builder: (context, shown) => MotionReveal(
                                      visible: shown,
                                      axis: Axis.horizontal,
                                      alignment: Alignment.centerRight,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const BusyIndicator(size: 12),
                                          const SizedBox(width: Gap.xs),
                                          Text(
                                            '还在查找…',
                                            style: small?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: Gap.xs),
                              for (final pick in picks.take(3))
                                _pickRow(pick, units, tabular),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
            check(
              value: filter.online,
              onChanged: filter.online || onlineSources.isNotEmpty
                  ? (value) {
                      filter = filter.copyWith(online: value);
                      if (value) _searchOnline();
                    }
                  : null,
              title: '包含在线源',
              subtitle: switch (onlineError) {
                _ when onlineSources.isEmpty => '没有启用的在线源，可在「数据源」中启用',
                final error? when filter.online => error,
                _ =>
                  '字幕组还没发布符合筛选的文件时，先缓存在线源的。'
                      '在线源不分字幕组和字幕，'
                      '${filter.qualities.isEmpty ? '只用 1080p 及以上' : '按所选画质'}',
              },
            ),
            if (earlier.isNotEmpty)
              check(
                value: cacheEarlier,
                onChanged: (value) => cacheEarlier = value,
                title:
                    '${subscription == null ? '同时' : ''}缓存已播出'
                    '${widget.subject.episodes.any((e) => e.watched) ? '、还没看' : ''}'
                    '的${episodeRange(earlier)}',
                subtitle: cached.isEmpty ? null : '${episodeRange(cached)}已有缓存',
              ),
            if (offerWatching)
              check(
                value: canMark && markWatching,
                onChanged: canMark ? (value) => markWatching = value : null,
                title: '在 Bangumi 标成在看',
                subtitle: canMark ? null : 'Bangumi 同步已暂停，可在 设置 › 账户与同步 中恢复',
              ),
            // Per device and applied at once: the subscription itself, and
            // whether other devices cache it, stay as they are.
            if (subscription != null)
              check(
                value: !subscription.paused,
                onChanged: (value) => unawaited(
                  widget.controller.setPaused([subscription.subjectId], !value),
                ),
                title: '这台设备缓存新一话',
                subtitle: subscription.paused ? '订阅仍在各设备间同步，只是这台不下载' : null,
              ),
            if (subscription != null) ...[
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '订阅动态',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (!subscription.paused)
                    Tooltip(
                      message: '立即查找新剧集',
                      child: TextButton.icon(
                        onPressed: checking
                            ? null
                            : () => unawaited(
                                widget.controller.checkOne(
                                  subscription.subjectId,
                                ),
                              ),
                        icon: checking
                            ? const BusyIndicator(size: 14)
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(checking ? '检查中' : '立即检查'),
                      ),
                    ),
                ],
              ),
              if (subscription.events.isEmpty)
                const EmptyState.compact(text: '还没有动态', center: false),
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
                                ? toneColor(context, NoticeTone.failed)
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
            onPressed: saving ? null : () => _unsubscribe(subscription),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('取消订阅'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ended || subscription == null || !changed ? '关闭' : '不保存'),
        ),
        if (!ended && (subscription == null || changed))
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

/// One episode's chosen file in the preview; the full title on hover.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.episode,
    required this.group,
    required this.file,
    required this.size,
    required this.delay,
    required this.title,
    required this.style,
  });
  final String episode, group, file, size, delay, title;
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
          const SizedBox(width: Gap.sm),
          // Sizes line up in a column of their own.
          SizedBox(
            width: 64,
            child: Text(size, textAlign: TextAlign.end, style: style),
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
  // Calendar days in UTC, so a daylight saving change does not shift them.
  final today = DateTime.utc(now.year, now.month, now.day);
  final day = DateTime.utc(at.year, at.month, at.day);
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
        '播放会停止。之后可在 设置 › 订阅与缓存 中更改',
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
