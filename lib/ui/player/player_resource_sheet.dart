import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/catalog.dart';
import '../../domain/play_candidate.dart';
import '../../features/playback/resource_search.dart';
import '../acquisition/resource_search_view.dart';
import '../core/theme.dart';
import '../../features/playback/playback.dart';

class PlayerResourceSheet extends StatefulWidget {
  const PlayerResourceSheet({
    super.key,
    required this.newSearch,
    required this.playback,
    required this.subject,
    required this.episodeId,
    required this.visible,
    required this.onClose,
    required this.onPlay,
    this.onOpenPage,
  });
  final ResourceSearchController Function() newSearch;
  final Playback playback;
  final Subject subject;
  final int? episodeId;
  final bool visible;
  final VoidCallback onClose;
  final Future<void> Function(PlayCandidate candidate, Episode episode) onPlay;

  /// Continues this search on the resources page.
  final void Function(ResourceSearchController search)? onOpenPage;
  @override
  State<PlayerResourceSheet> createState() => _PlayerResourceSheetState();
}

class _PlayerResourceSheetState extends State<PlayerResourceSheet> {
  final focus = FocusScopeNode();
  bool initialized = false;
  ResourceSearchController? search;
  Episode? get episode => widget.subject.episodes
      .where(
        (e) => e.id == (widget.episodeId ?? widget.playback.session?.episodeId),
      )
      .firstOrNull;

  /// The search for the shown chapter; a new chapter starts a new one so the
  /// previous view never observes the change.
  ResourceSearchController searchFor(Episode? episode) {
    final current = search;
    if (current != null &&
        current.state.subject?.id == widget.subject.id &&
        current.state.episode?.id == episode?.id) {
      return current;
    }
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return search = widget.newSearch()..open(widget.subject, episode: episode);
  }

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
    search?.dispose();
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
      child: !initialized ? const SizedBox.shrink() : view(episode),
    ),
  );

  Widget view(Episode? episode) {
    final search = searchFor(episode);
    return KeyedSubtree(
      key: const PageStorageKey('player-resources'),
      child: ResourceSearchView(
        key: ValueKey('resources:${widget.subject.id}:${episode?.id}'),
        search: search,
        active: widget.visible,
        onPlay: (candidate, target) async {
          await widget.onPlay(candidate, target);
          if (mounted) widget.onClose();
        },
        actions: [
          if (widget.onOpenPage != null)
            TextButton(
              onPressed: () => widget.onOpenPage!(search),
              child: const Text('在页面中打开'),
            ),
          IconButton(
            tooltip: '关闭资源窗口',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
