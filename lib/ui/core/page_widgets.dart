import 'package:flutter/material.dart';

import 'theme.dart';

class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('page-scroll'),
    padding: const EdgeInsets.fromLTRB(pageGutter, 6, pageGutter, 40),
    children: children,
  );
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
    final content = Padding(padding: padding, child: child);
    return Card(
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              customBorder: CardTheme.of(context).shape,
              child: content,
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
    this.color = coral,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: color),
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

class MelonBadge extends StatelessWidget {
  const MelonBadge(this.text, {super.key, this.color = mint});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = BadgeTheme.of(context);
    return Container(
      constraints: BoxConstraints(minHeight: theme.largeSize!),
      padding: theme.padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? .2 : .13),
        borderRadius: badgeBorderRadius,
      ),
      child: Text(
        text,
        style: theme.textStyle!.copyWith(
          color: dark
              ? Color.lerp(color, Colors.white, .25)
              : Color.lerp(color, Colors.black, .28),
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
  Widget build(BuildContext context) => MelonPanel(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_outlined,
            size: 32,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
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
  );
}
