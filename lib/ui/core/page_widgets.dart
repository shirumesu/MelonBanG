import 'package:flutter/material.dart';

import 'theme.dart';

class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 10, 28, 28),
    children: children,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 16),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        ?trailing,
      ],
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(40),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.local_florist_outlined, size: 42, color: mint),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(fontSize: 17)),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(detail!, textAlign: TextAlign.center),
            ),
          if (action != null)
            TextButton(onPressed: action, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}
