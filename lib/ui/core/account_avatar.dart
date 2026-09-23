import 'package:flutter/material.dart';

import 'theme.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    this.url,
    required this.name,
    this.size = 36,
  });
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: grape,
      child: Center(
        child: name.isEmpty
            ? const Icon(Icons.person_outline, color: Colors.white)
            : Text(
                name.characters.first,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url == null || url!.isEmpty
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, synchronous) =>
                    frame == null && !synchronous ? fallback : child,
                errorBuilder: (_, error, stack) => fallback,
              ),
      ),
    );
  }
}
