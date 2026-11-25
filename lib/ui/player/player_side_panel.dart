import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/community.dart';
import '../../domain/play_candidate.dart';
import '../../domain/playback_session.dart';
import '../../domain/transfer.dart';
import '../../features/playback/play_ranking.dart';
import '../../features/playback/playback.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'player_danmaku_panel.dart';
import 'player_discussion_pane.dart';
import 'player_episodes_pane.dart';

enum PlayerPanelTab { episodes, discussion, danmaku }

/// The panel beside the video: the subject's episodes with the playing
/// source and cache, the episode's Bangumi comments, and danmaku sources.
/// It follows the app's light or dark theme.
class PlayerSidePanel extends StatefulWidget {
  const PlayerSidePanel({
    super.key,
    required this.playback,
    required this.community,
    required this.subject,
    required this.session,
    required this.source,
    required this.downloads,
    required this.tab,
    required this.onTab,
    required this.onEpisode,
    required this.onFindResources,
    required this.onPlayFile,
    required this.onToggleTask,
    required this.onMarkEpisode,
    required this.onOpenSubject,
    required this.onError,
    this.remembered,
    required this.onForgetSource,
  });
  final Playback playback;
  final SubjectCommunitySource community;
  final Subject? subject;
  final PlaybackSession? session;

  /// The source chosen for the session, when one was.
  final PlayCandidate? source;

  /// The source the subject remembers for its next episodes.
  final RememberedSource? remembered;
  final VoidCallback onForgetSource;
  final ValueListenable<TransferSnapshot> downloads;
  final PlayerPanelTab tab;
  final ValueChanged<PlayerPanelTab> onTab;
  final ValueChanged<Episode> onEpisode;
  final ValueChanged<Episode?> onFindResources;
  final void Function(String id, String? fileId) onPlayFile;
  final Future<void> Function(DownloadTask) onToggleTask;
  final Future<void> Function(Episode episode, bool watched) onMarkEpisode;
  final ValueChanged<Subject> onOpenSubject;
  final ValueChanged<Object> onError;

  @override
  State<PlayerSidePanel> createState() => _PlayerSidePanelState();
}

class _PlayerSidePanelState extends State<PlayerSidePanel> {
  Episode? get current => switch ((widget.subject, widget.session)) {
    (final subject?, PlaybackSession(:final episodeId?)) => subject.episode(
      episodeId,
    ),
    _ => null,
  };

  Future<void> mark(Episode episode, bool watched) async {
    try {
      await widget.onMarkEpisode(episode, watched);
    } catch (e) {
      widget.onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final subject = widget.subject;
    final episode = current;
    final linked = widget.session?.subjectId != null;
    final tab = linked ? widget.tab : PlayerPanelTab.danmaku;
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.md, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject?.title ?? widget.session?.title ?? '播放器',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontSize: FontSize.emphasis),
                      ),
                      if (episode != null) ...[
                        const SizedBox(height: Gap.xs),
                        Text(
                          episodeLabel(episode),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ],
                    ],
                  ),
                ),
                if (subject != null && linked) ...[
                  const SizedBox(width: Gap.sm),
                  _DetailButton(onPressed: () => widget.onOpenSubject(subject)),
                ],
              ],
            ),
          ),
          if (linked)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
              child: MelonSegmentedControl<PlayerPanelTab>(
                options: const {
                  PlayerPanelTab.episodes: '剧集',
                  PlayerPanelTab.discussion: '讨论',
                  PlayerPanelTab.danmaku: '弹幕',
                },
                value: tab,
                onChanged: widget.onTab,
              ),
            ),
          Expanded(
            child: MotionSwap(
              value: tab,
              scale: 1,
              milliseconds: 200,
              alignment: Alignment.topCenter,
              child: SizedBox.expand(
                child: switch (tab) {
                  // Only this pane follows download progress.
                  PlayerPanelTab.episodes =>
                    ValueListenableBuilder<TransferSnapshot>(
                      key: ValueKey('episodes:${widget.session?.subjectId}'),
                      valueListenable: widget.downloads,
                      builder: (context, downloads, _) => PlayerEpisodesPane(
                        subject: subject,
                        session: widget.session,
                        source: widget.source,
                        remembered: widget.remembered,
                        onForgetSource: widget.onForgetSource,
                        downloads: downloads,
                        onEpisode: widget.onEpisode,
                        onFindResources: widget.onFindResources,
                        onPlayFile: widget.onPlayFile,
                        onToggleTask: widget.onToggleTask,
                        onMark: mark,
                      ),
                    ),
                  PlayerPanelTab.discussion => PlayerDiscussionPane(
                    key: ValueKey('discussion:${episode?.id}'),
                    community: widget.community,
                    episode: episode,
                  ),
                  PlayerPanelTab.danmaku => PlayerDanmakuPane(
                    playback: widget.playback,
                    title: subject?.title ?? widget.session?.title,
                  ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Leaves the player for the subject's detail page.
class _DetailButton extends StatelessWidget {
  const _DetailButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurface,
        shape: const RoundedRectangleBorder(borderRadius: badgeBorderRadius),
        textStyle: appFont.copyWith(fontSize: FontSize.small),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.info_outline_rounded, size: 15),
      label: const Text('番剧详情'),
    );
  }
}

/// Room the panel takes beside the video.
double sidePanelWidth(double contentWidth) =>
    math.min(contentWidth < 900 ? 296.0 : 336.0, contentWidth * .45);
