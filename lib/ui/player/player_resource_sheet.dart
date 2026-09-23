import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../data/resource_metadata.dart';
import '../acquisition/resources_page.dart';
import '../core/theme.dart';

/// Hosts the same resource page as catalogue navigation, in a playback-local context.
class PlayerResourceSheet extends StatefulWidget {
  const PlayerResourceSheet({
    super.key,
    required this.service,
    required this.subject,
    required this.episodeId,
    required this.visible,
    required this.onClose,
  });

  final AppServices service;
  final Json subject;
  final int? episodeId;
  final bool visible;
  final VoidCallback onClose;

  @override
  State<PlayerResourceSheet> createState() => _PlayerResourceSheetState();
}

class _PlayerResourceSheetState extends State<PlayerResourceSheet> {
  final query = TextEditingController();
  final focus = FocusScopeNode();
  final storage = PageStorageBucket();
  List<Json> candidates = [], providers = [];
  bool busy = false, initialized = false;
  int request = 0;
  String? error;

  Json? get episode =>
      objects(widget.subject['episodes'])
          .where((e) => e['episodeId'] == widget.episodeId)
          .firstOrNull;

  @override
  void initState() {
    super.initState();
    prepare();
  }

  @override
  void didUpdateWidget(PlayerResourceSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodeId != widget.episodeId ||
        oldWidget.subject['subjectId'] != widget.subject['subjectId']) {
      request++;
      initialized = false;
      candidates = [];
      providers = [];
      busy = false;
      error = null;
    }
    prepare();
    if (widget.visible && !oldWidget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible) focus.requestFocus();
      });
    }
  }

  void prepare() {
    if (initialized || !widget.visible) return;
    initialized = true;
    query.text = titleOf(widget.subject);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      focus.requestFocus();
      unawaited(
        search(resourceNames(widget.subject), resourceEpisodeKeyword(episode)),
      );
    });
  }

  Future<void> search(List<String> names, String episodeKeyword) async {
    final ticket = ++request;
    bool current() => mounted && ticket == request;
    setState(() {
      busy = true;
      error = null;
      candidates = [];
      providers = [];
    });
    void update(Json result) {
      if (!current()) return;
      setState(() {
        candidates = objects(result['candidates']);
        providers = objects(result['providers']);
      });
    }

    try {
      update(
        await widget.service.sources.search(
          widget.subject['subjectId'] as int,
          query.text.trim(),
          episodeId: widget.episodeId,
          alternativeNames: names,
          episodeKeyword: episodeKeyword,
          coverUrl: widget.subject['coverUrl'] as String?,
          isCurrent: current,
          onUpdate: update,
        ),
      );
    } catch (e) {
      if (current()) setState(() => error = '搜索失败：$e');
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    request++;
    query.dispose();
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
      key: const ValueKey('player-resource-sheet'),
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
                    episode == null ? '查找资源' : '查找资源 · 第 ${episode!['sort']} 话',
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
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: pageGutter,
                vertical: 8,
              ),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: PageStorage(
              bucket: storage,
              child: ResourcesPage(
                key: ValueKey(
                  'player-resources:${widget.subject['subjectId']}:${widget.episodeId}',
                ),
                subject: widget.subject,
                resourceSearch: query,
                resourceEpisode: widget.episodeId,
                providers: providers,
                candidates: candidates,
                busy: busy,
                onSearch: search,
                onDownload: (candidate) async {
                  await widget.service.sources.enqueue(
                    '${candidate['candidateId']}',
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
