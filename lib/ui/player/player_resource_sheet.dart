import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/catalog.dart';
import '../../domain/play_candidate.dart';
import '../../features/playback/play_selection.dart';
import '../core/theme.dart';
import 'candidate_resources.dart';
import '../../features/playback/playback.dart';

class PlayerResourceSheet extends StatefulWidget {
  const PlayerResourceSheet({
    super.key,
    required this.choices,
    required this.playback,
    required this.subject,
    required this.episodeId,
    required this.visible,
    required this.onClose,
    this.onPlayCandidate,
    this.onFindAllResources,
  });
  final SourceChoices choices;
  final Playback playback;
  final Subject subject;
  final int? episodeId;
  final bool visible;
  final VoidCallback onClose;
  final Future<void> Function(PlayCandidate candidate, Episode episode)?
  onPlayCandidate;
  final ValueChanged<Episode?>? onFindAllResources;
  @override
  State<PlayerResourceSheet> createState() => _PlayerResourceSheetState();
}

class _PlayerResourceSheetState extends State<PlayerResourceSheet> {
  final focus = FocusScopeNode();
  bool initialized = false;
  Episode? get episode => widget.subject.episodes
      .where(
        (e) => e.id == (widget.episodeId ?? widget.playback.session?.episodeId),
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
                    episode == null ? '选择资源' : '选择资源 · 第 ${episode!.number} 话',
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
                    active: widget.visible,
                    choices: widget.choices,
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
