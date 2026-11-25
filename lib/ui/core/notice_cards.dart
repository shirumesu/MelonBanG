import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/notices.dart';
import 'motion.dart';
import 'overlay_glass.dart';
import 'selection_controls.dart';
import 'theme.dart';
import 'tone.dart';

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

  @override
  Widget build(BuildContext context) {
    final notice = widget.entry.notice;
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
            child: MouseRegion(
              onEnter: (_) => widget.onHold(true),
              onExit: (_) => widget.onHold(false),
              child: NoticeCard(
                title: notice.title,
                detail: notice.detail,
                tone: notice.tone,
                actions: notice.actions,
                onOpen: notice.onOpen,
                onClose: widget.onClose,
                // A card waiting on a decision has no time to run down.
                remaining: notice.sticky ? null : countdown,
                glass: widget.glass,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A message card: [tone]'s icon, [title], [detail] and [actions]; an action
/// or a tap on the card ([onOpen]) also calls [onClose]. [remaining] runs a
/// line down its foot. Needs a bounded width ([NoticeStack.width]); shows no
/// tooltips, so it works outside any [Overlay]. [glass] is for the video.
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.title,
    this.detail,
    this.tone = NoticeTone.info,
    this.actions = const [],
    this.onOpen,
    this.onClose,
    this.remaining,
    this.glass = false,
  });
  final String title;
  final String? detail;
  final NoticeTone tone;
  final List<NoticeAction> actions;
  final VoidCallback? onOpen;

  /// Null for a card without a close button.
  final VoidCallback? onClose;

  /// From 1 to 0; null for no line.
  final Animation<double>? remaining;
  final bool glass;

  void _act(VoidCallback action) {
    onClose?.call();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = glass ? Colors.white : scheme.onSurface;
    final muted = glass ? overlayMuted : scheme.onSurfaceVariant;
    final tint = toneColor(context, tone, glass: glass);
    final detail = this.detail;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(toneIcon(tone), size: 18, color: tint),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
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
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Wrap(
                    spacing: Gap.xs,
                    children: [
                      for (final (index, action) in actions.indexed)
                        TextButton(
                          // On glass the first action is the white one.
                          style: glass
                              ? overlayTextButtonStyle(primary: index == 0)
                              : compactTextButtonStyle,
                          onPressed: () => _act(action.onPressed),
                          child: Text(action.label),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gap.xs),
          if (onClose case final close?)
            Semantics(
              button: true,
              label: '关闭',
              child: IconButton(
                onPressed: close,
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
    final open = onOpen;
    final remaining = this.remaining;
    final body = Stack(
      children: [
        AnimatedSize(
          duration: motionDuration(context, 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open == null
              ? content
              : InkWell(onTap: () => _act(open), child: content),
        ),
        if (remaining != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2,
            child: AnimatedBuilder(
              animation: remaining,
              builder: (_, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: remaining.value,
                child: ColoredBox(color: tint.withValues(alpha: .5)),
              ),
            ),
          ),
      ],
    );
    return Semantics(
      liveRegion: true,
      child: glass
          ? OverlayGlass(borderRadius: panelBorderRadius, child: body)
          : DecoratedBox(
              decoration: BoxDecoration(
                color: menuSurface(context),
                borderRadius: panelBorderRadius,
                boxShadow: panelShadows(context),
              ),
              child: ClipRRect(borderRadius: panelBorderRadius, child: body),
            ),
    );
  }
}
