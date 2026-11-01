import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final slivers = <Widget>[];
    var boxes = <Widget>[];
    void flush() {
      if (boxes.isEmpty) return;
      slivers.add(SliverList.list(children: boxes));
      boxes = [];
    }

    for (final child in children) {
      if (child is PageSliver) {
        flush();
        slivers.add(child);
      } else {
        boxes.add(child);
      }
    }
    flush();
    return CustomScrollView(
      key: const PageStorageKey('page-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(pageGutter, 6, pageGutter, 40),
          sliver: SliverMainAxisGroup(slivers: slivers),
        ),
      ],
    );
  }
}

class PageSliver extends StatelessWidget {
  const PageSliver({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class MelonPanel extends StatelessWidget {
  const MelonPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        customBorder: CardTheme.of(context).shape,
        child: content,
      );
    }
    // Dark panels sit close to the page; light along the top edge gives
    // them thickness.
    if (Theme.of(context).brightness == Brightness.dark) {
      content = CustomPaint(
        foregroundPainter: EdgeLight(
          color: Colors.white.withValues(alpha: .055),
          radius: panelBorderRadius,
        ),
        child: content,
      );
    }
    return Card(child: content);
  }
}

/// A panel that fills its height under a heading row: [icon], [title],
/// [detail], then [action] at the end, ruled off from [child].
class HeadedPanel extends StatelessWidget {
  const HeadedPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.detail,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return MelonPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.xs, 0),
            child: Row(
              children: [
                Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(title, style: text.titleSmall),
                const SizedBox(width: Gap.sm),
                if (detail case final detail?)
                  Text(detail, style: text.bodySmall),
                const Spacer(),
                ?action,
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.trailing,
    this.subtitle,
    this.icon,
    this.color,
    this.top = Gap.xl,
  });
  final String title;
  final double top;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  /// The secondary text colour by default; section icons stay neutral.
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: Gap.md),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 20,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// The heading of a folding group: a turning chevron, [title], the member
/// [count], then [trailing] at the end.
class FoldHeader extends StatelessWidget {
  const FoldHeader({
    super.key,
    required this.title,
    required this.count,
    required this.open,
    required this.onTap,
    required this.padding,
    this.trailing,
    this.borderRadius,
    this.chevronColor,
  });
  final String title;
  final int count;
  final bool open;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;
  final BorderRadius? borderRadius;
  final Color? chevronColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            AnimatedRotation(
              turns: open ? .25 : 0,
              duration: motionDuration(context, 200),
              curve: Curves.easeOutCubic,
              child: Icon(Icons.chevron_right, size: 18, color: chevronColor),
            ),
            const SizedBox(width: Gap.xs),
            Text(title, style: text.titleSmall),
            const SizedBox(width: Gap.sm),
            Text('$count', style: text.bodySmall),
            const Spacer(),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class MelonBadge extends StatelessWidget {
  const MelonBadge(
    this.text, {
    super.key,
    this.color,
    this.onTap,
    this.tooltip,
  });
  final String text;

  /// The theme's accent by default.
  final Color? color;

  /// Makes the badge a link, such as a tag that searches the catalogue.
  final VoidCallback? onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final color = this.color ?? accentOf(context).accent;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = BadgeTheme.of(context);
    final duration = motionDuration(context, 200);
    // A status that changes, such as a finished download, shifts colour.
    final badge = AnimatedContainer(
      duration: duration,
      constraints: BoxConstraints(minHeight: theme.largeSize!),
      padding: theme.padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? .2 : .13),
        borderRadius: badgeBorderRadius,
      ),
      child: AnimatedDefaultTextStyle(
        duration: duration,
        style: theme.textStyle!.copyWith(
          color: badgeInk(
            dark
                ? Color.lerp(color, Colors.white, .25)!
                : Color.lerp(color, Colors.black, .28)!,
            dark,
          ),
        ),
        child: Text(text),
      ),
    );
    if (onTap == null) return badge;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: badgeBorderRadius,
          hoverColor: color.withValues(alpha: dark ? .16 : .1),
          child: badge,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.text,
    this.detail,
    this.action,
    this.actionLabel = '重试',
  });
  final String text;
  final String? detail;
  final VoidCallback? action;
  final String actionLabel;
  @override
  Widget build(BuildContext context) => MotionAppear(
    child: MelonPanel(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _MarkHop(),
            const SizedBox(height: Gap.md),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  detail!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (action != null)
              TextButton(onPressed: action, child: Text(actionLabel)),
          ],
        ),
      ),
    ),
  );
}

/// The melon mark of an empty state, hopping once as it appears.
class _MarkHop extends StatelessWidget {
  const _MarkHop();

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: motionDuration(context, 520),
    // Waits for the panel to settle first.
    curve: const Interval(.27, 1),
    builder: (context, t, child) {
      final bump = math.sin(math.pi * Curves.easeOutCubic.transform(t));
      return Transform.translate(
        offset: Offset(0, -7 * bump),
        child: Transform.rotate(angle: -.07 * bump, child: child),
      );
    },
    child: Image.asset(
      'assets/images/mark.png',
      width: 56,
      height: 56,
      excludeFromSemantics: true,
    ),
  );
}

/// The page's one leading action, such as playing the next episode: solid
/// primary with light along its top edge, giving a little under a press.
/// Disabled, it looks like any disabled [FilledButton].
class ProminentButton extends StatefulWidget {
  const ProminentButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });
  final VoidCallback? onPressed;
  final Widget icon, label;

  @override
  State<ProminentButton> createState() => _ProminentButtonState();
}

class _ProminentButtonState extends State<ProminentButton> {
  final _states = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    _states.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pressed = _states.value.contains(WidgetState.pressed);
    final button = FilledButton.icon(
      statesController: _states,
      onPressed: widget.onPressed,
      style:
          FilledButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            shadowColor: Theme.of(context).shadowColor.withValues(alpha: 1),
          ).copyWith(
            elevation: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.disabled) ||
                      states.contains(WidgetState.pressed)
                  ? 0
                  : states.contains(WidgetState.hovered)
                  ? 2
                  : 1,
            ),
          ),
      icon: widget.icon,
      label: widget.label,
    );
    return AnimatedScale(
      scale: pressed && widget.onPressed != null ? .98 : 1,
      duration: motionDuration(context, 80),
      curve: Curves.easeOut,
      // Along the button's own edge: a foregroundBuilder only wraps the
      // label, which drew a second outline inside.
      child: CustomPaint(
        foregroundPainter: EdgeLight(
          color: Colors.white.withValues(
            alpha: widget.onPressed == null ? 0 : .22,
          ),
          radius: controlBorderRadius,
          depth: 10,
        ),
        child: button,
      ),
    );
  }
}

/// A grey block standing in for content that is loading, in its layout;
/// wrap a group of them in one [MotionPulse].
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    this.height,
    this.radius = badgeBorderRadius,
    this.color,
  });
  final double? width, height;
  final BorderRadius radius;

  /// [ColorScheme.surfaceContainerHigh] by default.
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: radius,
    ),
  );
}

/// Fades the edges of a scrolling [child] into [color] wherever more
/// content lies beyond, so a list cut off by its panel reads as one that
/// scrolls. Drawn over the list rather than masking it, which would need an
/// offscreen layer.
class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({super.key, required this.child, this.color});
  final Widget child;

  /// The panel behind the list; [ColorScheme.surface] by default.
  final Color? color;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  final _before = ValueNotifier(false), _after = ValueNotifier(false);

  bool _update(ScrollMetrics metrics) {
    if (metrics.axis == Axis.vertical) {
      _before.value = metrics.extentBefore > 1;
      _after.value = metrics.extentAfter > 1;
    }
    return false;
  }

  @override
  void dispose() {
    _before.dispose();
    _after.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.surface;
    Widget edge(ValueNotifier<bool> shown, bool top) => Positioned(
      left: 0,
      right: 0,
      top: top ? 0 : null,
      bottom: top ? null : 0,
      height: 18,
      child: IgnorePointer(
        child: ValueListenableBuilder(
          valueListenable: shown,
          builder: (context, value, child) => AnimatedOpacity(
            opacity: value ? 1 : 0,
            duration: motionDuration(context, 150),
            child: child,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [color, color.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) => _update(notification.metrics),
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) => _update(notification.metrics),
            child: widget.child,
          ),
        ),
        edge(_before, true),
        edge(_after, false),
      ],
    );
  }
}
