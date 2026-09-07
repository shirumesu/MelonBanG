import 'package:flutter/material.dart';

import 'theme.dart';

class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(26, 6, 26, 40),
    children: children,
  );
}

class MelonPanel extends StatelessWidget {
  const MelonPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: surfaceColor(context),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: lineColor(context)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark(context) ? .14 : .035),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12, color: mutedColor(context)),
                ),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: isDark(context) ? .2 : .13),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: isDark(context)
            ? Color.lerp(color, Colors.white, .25)
            : Color.lerp(color, Colors.black, .18),
      ),
    ),
  );
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
          Icon(Icons.movie_outlined, size: 32, color: mutedColor(context)),
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
                style: TextStyle(color: mutedColor(context), fontSize: 12),
              ),
            ),
          if (action != null)
            TextButton(onPressed: action, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}
