import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/notices.dart';
import '../../domain/catalog.dart';
import '../../features/subscriptions/subscription_controller.dart';
import '../../features/tracking/tracking_controller.dart';
import '../core/collection_labels.dart';
import '../core/context_menu.dart';
import '../core/external_link.dart';
import '../core/notice_cards.dart';
import '../subscriptions/subscription_dialogs.dart';
import 'collection_editor.dart';

enum _Action { watch, edit, subscribe, resources, bangumi, copy }

/// The menu of a show in the collection: watching it, its status and
/// collection entry, its subscription and resources, and its Bangumi page
/// and title.
class CollectionMenu {
  const CollectionMenu({
    required this.personal,
    required this.subscriptions,
    required this.preferredGroups,
    required this.played,
    required this.onWatch,
    required this.onFindResources,
    required this.onError,
  });
  final TrackingController personal;
  final SubscriptionController subscriptions;
  final List<String> Function() preferredGroups;

  /// Whether an episode of the subject was played here.
  final bool Function(int id) played;

  /// Plays the episode the subject's own play button would.
  final Future<void> Function(Subject) onWatch;
  final ValueChanged<Subject> onFindResources;
  final ValueChanged<Object> onError;

  Future<void> show(BuildContext context, Subject item, Offset position) async {
    final status = item.status!;
    final started = played(item.id) || (item.watchedEpisodes ?? 0) > 0;
    final subscribed = subscriptions.subscriptions.containsKey(item.id);
    PopupMenuItem<Object> action(_Action value, String label) =>
        contextMenuItem(value, label, checked: false);
    const divider = PopupMenuDivider(height: 9);
    final choice = await showContextMenu<Object>(
      context,
      position: position,
      items: [
        action(_Action.watch, started ? '继续观看' : '开始观看'),
        divider,
        for (final MapEntry(key: value, value: label)
            in collectionLabels.entries)
          contextMenuItem(value, label, checked: value == status),
        action(_Action.edit, '编辑收藏…'),
        divider,
        action(_Action.subscribe, subscribed ? '订阅设置' : '订阅'),
        action(_Action.resources, '查找资源'),
        divider,
        action(_Action.bangumi, '在 Bangumi 打开'),
        action(_Action.copy, '复制标题'),
      ],
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case CollectionStatus value:
        await _setStatus(context, item, value);
      case _Action.watch:
        await onWatch(item);
      case _Action.edit:
        await _edit(context, item);
      case _Action.subscribe:
        await _subscribe(context, item);
      case _Action.resources:
        onFindResources(item);
      case _Action.bangumi:
        await openExternal(context, 'https://bgm.tv/subject/${item.id}');
      case _Action.copy:
        final notices = NoticesScope.of(context);
        await Clipboard.setData(ClipboardData(text: item.title));
        showMessage(notices, '已复制标题');
    }
  }

  Future<bool> _save(Subject item, CollectionChange change) async {
    try {
      await personal.saveCollection(item.id, change);
      return true;
    } catch (error) {
      onError(error);
      return false;
    }
  }

  /// Moves the show to [status], with the way back; moving it to 看过 also
  /// offers to mark the episodes left watched.
  Future<void> _setStatus(
    BuildContext context,
    Subject item,
    CollectionStatus status,
  ) async {
    final previous = item.status!;
    if (status == previous) return;
    final notices = NoticesScope.of(context);
    // 想看 clears the score on Bangumi; going back restores it.
    final score = item.collection?.score ?? 0;
    if (!await _save(item, CollectionChange(status: status))) return;
    final left = status == CollectionStatus.completed
        ? (item.episodeTotal ?? 0) - (item.watchedEpisodes ?? 0)
        : 0;
    notices.show(
      Notice(
        '「${item.title}」已改为${collectionLabels[status]}',
        key: ('collection-status', item.id),
        actions: [
          NoticeAction(
            '撤销',
            () => _save(
              item,
              CollectionChange(
                status: previous,
                score: status == CollectionStatus.wish && score > 0
                    ? score
                    : null,
              ),
            ),
          ),
          if (left > 0)
            NoticeAction(
              '剩余 $left 话标为已看',
              () => _save(
                item,
                const CollectionChange(
                  status: CollectionStatus.completed,
                  completeEpisodes: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, Subject item) async {
    final notices = NoticesScope.of(context);
    final key = CollectionDrafts.key(personal.userId, item.id);
    final change = await showCollectionDrawer(
      context,
      subject: item,
      draftKey: key,
    );
    if (change == null || change.isEmpty) return;
    if (await _save(item, change)) {
      CollectionDrafts.clear(key);
      showMessage(notices, '已保存「${item.title}」的收藏');
    }
  }

  Future<void> _subscribe(BuildContext context, Subject item) async {
    final Subject detail;
    try {
      detail = await subscriptions.detail(item.id);
    } catch (error) {
      onError(error);
      return;
    }
    if (!context.mounted) return;
    await showSubscription(
      context,
      controller: subscriptions,
      subject: detail,
      preferredGroups: preferredGroups(),
      onError: onError,
      markWatching: markWatchingFor(personal),
    );
  }
}
