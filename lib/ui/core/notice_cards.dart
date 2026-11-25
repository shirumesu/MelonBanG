import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/notices.dart';
import '../player/player_theme.dart';
import 'motion.dart';
import 'selection_controls.dart';
import 'theme.dart';

/// Gives the pages the window's [Notices], so any of them can show one.
class NoticesScope extends InheritedWidget {
  const NoticesScope({super.key, required this.notices, required super.child});
  final Notices notices;

  static Notices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NoticesScope>()!.notices;

  @override
  bool updateShouldNotify(NoticesScope oldWidget) =>
      oldWidget.notices != notices;
}

/// Shows [text] as a notice, with a way back or onward when [actionLabel]
/// and [onAction] are given; the one place for messages that have no place
/// of their own on the page.
void showMessage(
  Notices notices,
  String text, {
  NoticeTone tone = NoticeTone.info,
  String? actionLabel,
  VoidCallback? onAction,
}) => notices.show(
  Notice(
    text,
    tone: tone,
    actions: [
      if (actionLabel != null && onAction != null)
        NoticeAction(actionLabel, onAction),
    ],
  ),
);

/// The notices as a column of cards, the newest at the bottom, nearest the
/// corner they sit in. Cards slide in from the side, a line along each one's
/// foot runs down the time it has left, and the others close up when one
/// goes. Over the video they are the player's dark glass ([glass]);
/// elsewhere raised panels.
///
/// It may sit above the navigator, so it uses nothing that needs an
/// [Overlay]: no tooltips.
class NoticeStack extends StatefulWidget {
  const NoticeStack({super.key, required this.notices, this.glass = false});
  final Notices notices;
  final bool glass;

  /// The cards' width where the window has room.
  static const width = 340.0;

  @override
  State<NoticeStack> createState() => _NoticeStackState();
}

class _Item {
  _Item(this.entry);
  final ShownNotice entry;
  bool leaving = false;
}

class _NoticeStackState extends State<NoticeStack> {
  final _items = <_Item>[];

  @override
  void initState() {
    super.initState();
    widget.notices.addListener(_sync);
    _diff();
  }

  @override
  void didUpdateWidget(NoticeStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notices != widget.notices) {
      oldWidget.notices.removeListener(_sync);
      widget.notices.addListener(_sync);
      _diff();
    }
  }

  @override
  void dispose() {
    widget.notices.removeListener(_sync);
    super.dispose();
  }

  void _sync() => setState(_diff);

  /// Marks the cards no longer shown as leaving and adds the new ones.
  void _diff() {
    final ids = {for (final entry in widget.notices.shown) entry.id};
    for (final item in _items) {
      if (!ids.contains(item.entry.id)) item.leaving = true;
    }
    final known = {for (final item in _items) item.entry.id};
    for (final entry in widget.notices.shown) {
      if (!known.contains(entry.id)) _items.add(_Item(entry));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Takes no room with nothing to show, so it widens nothing around it.
    if (_items.isEmpty) return const SizedBox.shrink();
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: NoticeStack.width),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in _items)
              _NoticeTile(
                key: ValueKey(item.entry.id),
                entry: item.entry,
                leaving: item.leaving,
                glass: widget.glass,
                onHold: (held) {
                  if (!item.leaving) widget.notices.hold(item.entry, held);
                },
                onClose: () => widget.notices.dismiss(item.entry),
                onGone: () => setState(() => _items.remove(item)),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoticeTile extends StatefulWidget {
  const _NoticeTile({
    super.key,
    required this.entry,
    required this.leaving,
    required this.glass,
    required this.onHold,
    required this.onClose,
    required this.onGone,
  });
  final ShownNotice entry;
  final bool leaving, glass;
  final ValueChanged<bool> onHold;
  final VoidCallback onClose, onGone;

  @override
  State<_NoticeTile> createState() => _NoticeTileState();
}

class _NoticeTileState extends State<_NoticeTile>
    with TickerProviderStateMixin {
  late final controller = AnimationController(vsync: this);
  late final curve = CurvedAnimation(
    parent: controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// The share of its time the card has left, run down while it runs. It
  /// stands for the time itself, so reduced motion does not hurry it.
  late final countdown = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  bool started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller
      ..duration = motionDuration(context, 240)
      ..reverseDuration = motionDuration(context, 180);
    if (!started) {
      started = true;
      if (!widget.leaving) {
        controller.forward();
        syncCountdown();
      } else {
        // Gone before it was shown; the stack is still building.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onGone();
        });
      }
    }
  }

  @override
  void didUpdateWidget(_NoticeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leaving && !oldWidget.leaving) {
      countdown.stop();
      controller.reverse().whenComplete(() {
        if (mounted) widget.onGone();
      });
    } else if (!widget.leaving) {
      // The stack rebuilds whenever a card's time stops, runs again or
      // starts over.
      syncCountdown();
    }
  }

  void syncCountdown() {
    final entry = widget.entry;
    final total = entry.notice.duration.inMicroseconds;
    countdown.value = entry.left.inMicroseconds / total;
    if (entry.running) {
      unawaited(countdown.animateTo(0, duration: entry.left));
    }
  }

  @override
  void dispose() {
    curve.dispose();
    controller.dispose();
    countdown.dispose();
    super.dispose();
  }

  void act(VoidCallback action) {
    widget.onClose();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.entry.notice;
    final glass = widget.glass;
    final scheme = Theme.of(context).colorScheme;
    final ink = glass ? Colors.white : scheme.onSurface;
    final muted = glass ? overlayMuted : scheme.onSurfaceVariant;
    final (icon, tint) = switch (notice.tone) {
      NoticeTone.info => (Icons.notifications_none_rounded, muted),
      NoticeTone.done => (
        Icons.check_circle_outline_rounded,
        glass ? Colors.white : scheme.primary,
      ),
      NoticeTone.warning => (
        Icons.error_outline_rounded,
        glass ? Colors.white : scheme.tertiary,
      ),
      NoticeTone.failed => (
        Icons.error_outline_rounded,
        glass ? overlayTheme.colorScheme.error : scheme.error,
      ),
    };
    final detail = notice.detail;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: appFont.copyWith(
                    fontSize: FontSize.body,
                    height: 1.45,
                    color: ink,
                    fontWeight: detail == null
                        ? FontWeight.w400
                        : FontWeight.w700,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: appFont.copyWith(
                      fontSize: FontSize.small,
                      height: 1.45,
                      color: muted,
                    ),
                  ),
                ],
                if (notice.actions.isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Wrap(
                    spacing: Gap.xs,
                    children: [
                      for (final action in notice.actions)
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.sm,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            foregroundColor: glass ? Colors.white : null,
                            overlayColor: glass ? Colors.white : null,
                            textStyle: appFont.copyWith(
                              fontSize: FontSize.body,
                              fontWeight: glass
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          onPressed: () => act(action.onPressed),
                          child: Text(action.label),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gap.xs),
          // No tooltip: the stack may sit outside any overlay.
          Semantics(
            button: true,
            label: '关闭',
            child: IconButton(
              onPressed: widget.onClose,
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              color: muted,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(28),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
    final open = notice.onOpen;
    final body = Stack(
      children: [
        AnimatedSize(
          duration: motionDuration(context, 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open == null
              ? content
              : InkWell(onTap: () => act(open), child: content),
        ),
        // A card waiting on a decision has no time to run down.
        if (!notice.sticky)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2,
            child: AnimatedBuilder(
              animation: countdown,
              builder: (_, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: countdown.value,
                child: ColoredBox(color: tint.withValues(alpha: .5)),
              ),
            ),
          ),
      ],
    );
    final card = glass
        ? OverlayGlass(borderRadius: panelBorderRadius, child: body)
        : DecoratedBox(
            decoration: BoxDecoration(
              color: menuSurface(context),
              borderRadius: panelBorderRadius,
              boxShadow: panelShadows(context),
            ),
            child: ClipRRect(borderRadius: panelBorderRadius, child: body),
          );
    return SizeTransition(
      sizeFactor: curve,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(.12, 0),
            end: Offset.zero,
          ).animate(curve),
          child: Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Semantics(
              liveRegion: true,
              child: MouseRegion(
                onEnter: (_) => widget.onHold(true),
                onExit: (_) => widget.onHold(false),
                child: card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
