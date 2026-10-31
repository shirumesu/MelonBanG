import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';
import 'subject_posters.dart' show imageDecodeWidth;
import 'cached_image.dart';

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
    final scheme = Theme.of(context).colorScheme;
    // Nobody to show, such as before signing in: a neutral silhouette.
    final fallback = ColoredBox(
      color: name.isEmpty ? scheme.surfaceContainerHigh : grape,
      child: Center(
        child: name.isEmpty
            ? Icon(
                Icons.person_outline,
                size: size * .55,
                color: scheme.onSurfaceVariant,
              )
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
            : CachedImage(
                url: url!,
                cacheWidth: imageDecodeWidth(context, size),
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, synchronous) => ImageFadeIn(
                  frame: frame,
                  synchronous: synchronous,
                  placeholder: fallback,
                  child: child,
                ),
                errorBuilder: (_, error, stack) => fallback,
              ),
      ),
    );
  }
}
