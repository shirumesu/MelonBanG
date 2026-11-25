import 'package:flutter/material.dart';

import '../../core/notices.dart';
import 'overlay_glass.dart';

/// The colour of [tone]'s icon, and of a short status word standing alone
/// without one, such as 受限; a sentence beside a tone icon keeps the normal
/// text colour. [glass] is for text on [OverlayGlass].
Color toneColor(BuildContext context, NoticeTone tone, {bool glass = false}) {
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    NoticeTone.info => glass ? overlayMuted : scheme.onSurfaceVariant,
    NoticeTone.done => glass ? Colors.white : scheme.primary,
    NoticeTone.warning => glass ? Colors.white : scheme.tertiary,
    NoticeTone.failed => glass ? overlayTheme.colorScheme.error : scheme.error,
  };
}

/// The fill of a banner or strip in [tone].
Color toneContainer(BuildContext context, NoticeTone tone) {
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    NoticeTone.info => scheme.surfaceContainerHigh,
    NoticeTone.done => scheme.primaryContainer.withValues(alpha: .5),
    NoticeTone.warning => scheme.tertiaryContainer,
    NoticeTone.failed => scheme.errorContainer.withValues(alpha: .45),
  };
}

IconData toneIcon(NoticeTone tone) => switch (tone) {
  NoticeTone.info => Icons.info_outline_rounded,
  NoticeTone.done => Icons.check_circle_outline_rounded,
  NoticeTone.warning || NoticeTone.failed => Icons.error_outline_rounded,
};
