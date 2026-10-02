import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../data/play_candidates.dart';
import '../core/theme.dart';
import 'candidate_resources.dart';
import 'playback.dart';

class PlayerResourceSheet extends StatefulWidget {
  const PlayerResourceSheet({
    super.key,
    required this.service,
    required this.playback,
    required this.subject,
    required this.episodeId,
    required this.visible,
    required this.onClose,
    this.onPlayCandidate,
    this.onFindAllResources,
  });
  final AppServices service;
  final Playback playback;
  final Json subject;
  final int? episodeId;
  final bool visible;
  final VoidCallback onClose;
  final Future<void> Function(PlayCandidate candidate, Json episode)?
  onPlayCandidate;
  final ValueChanged<Json?>? onFindAllResources;
  @override
  State<PlayerResourceSheet> createState() => _PlayerResourceSheetState();
}

class _PlayerResourceSheetState extends State<PlayerResourceSheet> {
  final focus = FocusScopeNode();
  bool initialized = false;
  Json? get episode => objects(widget.subject['episodes'])
      .where(
        (e) =>
            e['episodeId'] ==
            (widget.episodeId ?? widget.playback.session?['episodeId']),
      )
      .firstOrNull;
  @override
  void initState() {
    super.initState();
    initialized = widget.visible;
  }

  @override
  void didUpdateWidget(PlayerResourceSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) initialized = true;
    if (widget.visible && !oldWidget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible) focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: focus,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onClose();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 12,
      borderRadius: panelBorderRadius,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(pageGutter, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    episode == null ? '选择资源' : '选择资源 · 第 ${episode!['sort']} 话',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: '关闭资源窗口',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: !initialized
                ? const SizedBox.shrink()
                : episode == null
                ? Center(
                    child: TextButton(
                      onPressed: () => widget.onFindAllResources?.call(episode),
                      child: const Text('查找本作资源'),
                    ),
                  )
                : CandidateResources(
                    service: widget.service,
                    playback: widget.playback,
                    subject: widget.subject,
                    episode: episode!,
                    onFindResources: () =>
                        widget.onFindAllResources?.call(episode),
                    onPlay: (candidate) async {
                      await widget.onPlayCandidate?.call(candidate, episode!);
                      if (mounted) widget.onClose();
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
