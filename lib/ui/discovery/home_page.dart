import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../features/discovery/continue_range.dart';
import '../../features/discovery/discovery_controller.dart';
import '../../features/discovery/schedule_filter.dart';
import '../../features/playback/resume_controller.dart';
import '../../features/tracking/tracking_controller.dart';
import '../core/action_feedback.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';
import 'home_continue.dart';
import 'home_showcase.dart';
import 'today_timeline.dart';

/// Set once the home page has first been shown in this run: only that first
/// arrival brings its blocks in one after another.
bool _homeArrived = false;

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.discovery,
    required this.personal,
    required this.resume,
    required this.onExplore,
    required this.feedback,
    required this.onCalendar,
    required this.onRefresh,
    required this.onOpenSubject,
    required this.onPlayEpisode,
    required this.onOpenTracking,
    required this.scheduleFilter,
    this.range = ContinueRange.all,
    this.subscriptions = const {},
  });
  final DiscoveryController discovery;

  /// The schedule page's filter, which 今日更新 follows.
  final SchedulePreference scheduleFilter;
  final TrackingController personal;
  final ResumeController resume;
  final VoidCallback onExplore, onCalendar, onRefresh, onOpenTracking;
  final ActionFeedback feedback;
  final ValueChanged<Subject> onOpenSubject;
  final void Function(Subject subject, Episode episode) onPlayEpisode;

  /// Which shows 继续观看 lists.
  final ContinueRange range;

  /// Subscribed shows, by subject id.
  final Map<int, SubscriptionMark> subscriptions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([discovery, personal, resume, scheduleFilter]),
    builder: (context, _) => LayoutBuilder(builder: _layout),
  );

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final trending = discovery.trending, today = discovery.today;
    final trendingLoading = discovery.trendingLoading;
    final error = discovery.trendingError;
    final watching = personal.watching;
    final wide = constraints.maxWidth - 2 * pageGutter >= 860;
    // The lower row fills the window's rest, so the timeline scrolls inside.
    final lowerHeight = math.max(
      380.0,
      constraints.maxHeight - Gap.lg - showcaseHeight - Gap.xxl - Gap.xl,
    );
    // The startup's skeleton stands in until the home page first builds;
    // its own then follows at once.
    final arriving = !_homeArrived;
    final showcaseLoading = trendingLoading && trending.isEmpty;
    final showcase = DelayedBusy(
      busy: showcaseLoading,
      immediate: arriving,
      builder: (context, shown) => shown
          ? ShowcaseSkeleton(wide: wide)
          : showcaseLoading
          ? const SizedBox(height: showcaseHeight)
          : trending.isEmpty
          ? EmptyState(
              text: error == null ? '暂时没有热门番剧' : '暂时无法加载番剧',
              detail: error,
              action: onRefresh,
            )
          : TrendingShowcase(
              key: const PageStorageKey('trending-showcase'),
              items: trending,
              wide: wide,
              onOpen: onOpenSubject,
            ),
    );
    final now = DateTime.now();
    final filter = scheduleFilter.value;
    final listedToday = [
      for (final item in today)
        if (filter.accepts(item, now)) item,
    ];
    final timeline = TodayTimeline(
      items: listedToday,
      hidden: today.length - listedToday.length,
      loading: discovery.todayLoading,
      skeletonAtOnce: arriving,
      error: discovery.todayError,
      watchingIds: {for (final item in watching) item.id},
      onOpen: onOpenSubject,
      onCalendar: onCalendar,
      onRetry: onRefresh,
    );
    final airings = <int, List<DateTime>>{};
    for (final day in discovery.calendar) {
      for (final item in day.items) {
        if (item.airingAt case final at?) (airings[item.id] ??= []).add(at);
      }
    }
    // A show airs within the range while the schedule lists it or an episode
    // of it airs on or after the range's first day; one not known yet stays.
    final from = range.from(now);
    bool inRange(Subject item) {
      if (from == null || airings[item.id] != null) return true;
      final dates = [
        for (final episode in resume.watching[item.id]?.episodes ?? const [])
          if (episode.main) ?episode.aired,
      ];
      final latest = dates.isEmpty
          ? DateTime.tryParse(item.airDate ?? '')
          : dates.reduce((a, b) => a.isAfter(b) ? a : b);
      return latest == null || !latest.isBefore(from);
    }

    final listed = watching.where(inRange).toList();
    final continuation = ContinueSection(
      loaded: personal.loaded,
      watching: listed,
      outOfRange: watching.length - listed.length,
      range: range,
      subscriptions: subscriptions,
      details: resume.watching,
      playable: resume.watchingPlayable,
      resumable: resume.resumable,
      played: resume.played,
      airings: airings,
      airingToday: {for (final item in today) item.id},
      onOpenSubject: onOpenSubject,
      onPlayEpisode: onPlayEpisode,
      onExplore: onExplore,
      onOpenTracking: onOpenTracking,
    );
    if (arriving) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _homeArrived = true);
    }
    Widget arrive(int order, Widget child) =>
        _Arrival(order: order, play: arriving, child: child);
    return ListView(
      key: const PageStorageKey('page-scroll'),
      padding: const EdgeInsets.fromLTRB(
        pageGutter,
        Gap.lg,
        pageGutter,
        Gap.xl,
      ),
      children: [
        FeedbackIssue(feedback: feedback, onRetry: onRefresh),
        if (!wide)
          SectionTitle(
            title: '本季热度',
            icon: Icons.local_fire_department_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            top: 0,
          ),
        arrive(0, showcase),
        const SizedBox(height: Gap.xxl),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: arrive(
                  1,
                  SizedBox(height: lowerHeight, child: continuation),
                ),
              ),
              const SizedBox(width: Gap.lg),
              arrive(
                2,
                SizedBox(
                  width: homeSideColumnWidth,
                  height: lowerHeight,
                  child: timeline,
                ),
              ),
            ],
          )
        else ...[
          arrive(1, SizedBox(height: 420, child: continuation)),
          const SizedBox(height: Gap.xxl),
          arrive(2, SizedBox(height: 460, child: timeline)),
        ],
      ],
    );
  }
}

/// The home page in grey while the app starts, in [HomePage]'s layout;
/// [HomePage] carries the same skeletons on at once.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({
    super.key,
    required this.onOpenTracking,
    required this.onCalendar,
  });
  final VoidCallback onOpenTracking, onCalendar;

  @override
  Widget build(BuildContext context) => DelayedBusy(
    busy: true,
    builder: (context, shown) => !shown
        ? const SizedBox.shrink()
        : MotionAppear(
            offset: 0,
            milliseconds: 200,
            child: LayoutBuilder(builder: _layout),
          ),
  );

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final wide = constraints.maxWidth - 2 * pageGutter >= 860;
    final lowerHeight = math.max(
      380.0,
      constraints.maxHeight - Gap.lg - showcaseHeight - Gap.xxl - Gap.xl,
    );
    final continuation = HeadedPanel(
      icon: Icons.play_circle_outline,
      title: '继续观看',
      action: TextButton(onPressed: onOpenTracking, child: const Text('全部追番')),
      child: const SizedBox.shrink(),
    );
    final timeline = TodayTimeline(
      items: const [],
      loading: true,
      skeletonAtOnce: true,
      error: null,
      watchingIds: const {},
      onOpen: (_) {},
      onCalendar: onCalendar,
      onRetry: () {},
    );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        pageGutter,
        Gap.lg,
        pageGutter,
        Gap.xl,
      ),
      children: [
        if (!wide)
          SectionTitle(
            title: '本季热度',
            icon: Icons.local_fire_department_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            top: 0,
          ),
        ShowcaseSkeleton(wide: wide),
        const SizedBox(height: Gap.xxl),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(height: lowerHeight, child: continuation),
              ),
              const SizedBox(width: Gap.lg),
              SizedBox(
                width: homeSideColumnWidth,
                height: lowerHeight,
                child: timeline,
              ),
            ],
          )
        else ...[
          SizedBox(height: 420, child: continuation),
          const SizedBox(height: Gap.xxl),
          SizedBox(height: 460, child: timeline),
        ],
      ],
    );
  }
}

/// One block of the home page, rising into place [order] beats after the
/// first when [play]; decided once, so later rebuilds keep the subtree.
class _Arrival extends StatefulWidget {
  const _Arrival({
    required this.order,
    required this.play,
    required this.child,
  });
  final int order;
  final bool play;
  final Widget child;

  @override
  State<_Arrival> createState() => _ArrivalState();
}

class _ArrivalState extends State<_Arrival> {
  late final bool _play = widget.play;

  @override
  Widget build(BuildContext context) => _play
      ? MotionAppear(
          offset: 8,
          milliseconds: 320,
          delay: widget.order * 40,
          child: widget.child,
        )
      : widget.child;
}
