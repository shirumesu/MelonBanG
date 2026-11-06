import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/error_message.dart';
import 'motion.dart';
import 'theme.dart';

class ActionFeedback extends ChangeNotifier {
  bool busy = false, succeeded = false;
  String? issue;
  Timer? _reset;
  bool _disposed = false;

  Future<void> run(Future<String?> Function() action) async {
    if (busy || _disposed) return;
    _reset?.cancel();
    busy = true;
    succeeded = false;
    issue = null;
    notifyListeners();
    String? result;
    try {
      result = await action();
    } catch (e) {
      result = errorMessage(e);
    }
    if (_disposed) return;
    busy = false;
    issue = result;
    succeeded = result == null;
    notifyListeners();
    if (succeeded) {
      _reset = Timer(const Duration(seconds: 3), () {
        succeeded = false;
        notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reset?.cancel();
    super.dispose();
  }
}

class FeedbackButton extends StatelessWidget {
  const FeedbackButton({
    super.key,
    required this.feedback,
    required this.label,
    required this.runningLabel,
    required this.successLabel,
    required this.icon,
    required this.onPressed,
    this.iconOnly = false,
  });
  final ActionFeedback feedback;
  final String label, runningLabel, successLabel;
  final IconData icon;
  final VoidCallback onPressed;

  /// Shows only the icon, with the current label as its tooltip.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: feedback,
    builder: (context, _) {
      final current = feedback.busy
          ? runningLabel
          : feedback.succeeded
          ? successLabel
          : label;
      final glyph = SizedBox.square(
        dimension: 18,
        child: AnimatedSwitcher(
          duration: motionDuration(context, 150),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          child: feedback.busy
              ? MediaQuery.disableAnimationsOf(context)
                    ? const Icon(
                        Icons.hourglass_empty_rounded,
                        key: ValueKey('busy'),
                        size: 18,
                      )
                    : const Padding(
                        key: ValueKey('busy'),
                        padding: EdgeInsets.all(1),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
              : Icon(
                  feedback.succeeded ? Icons.check_rounded : icon,
                  key: ValueKey(feedback.succeeded),
                  size: 18,
                ),
        ),
      );
      final primary = Theme.of(context).colorScheme.primary;
      return Semantics(
        liveRegion: true,
        child: iconOnly
            ? IconButton(
                tooltip: current,
                onPressed: feedback.busy ? null : onPressed,
                color: feedback.succeeded ? primary : null,
                disabledColor: primary,
                icon: glyph,
              )
            : TextButton.icon(
                onPressed: feedback.busy ? null : onPressed,
                style: TextButton.styleFrom(disabledForegroundColor: primary),
                icon: glyph,
                label: _FeedbackLabel(
                  labels: [label, runningLabel, successLabel],
                  current: current,
                ),
              ),
      );
    },
  );
}

class _FeedbackLabel extends StatelessWidget {
  const _FeedbackLabel({required this.labels, required this.current});

  final List<String> labels;
  final String current;

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    final style = DefaultTextStyle.of(context).style;
    var width = 0.0;
    for (final label in labels) {
      painter.text = TextSpan(text: label, style: style);
      painter.layout();
      if (painter.width > width) width = painter.width;
    }
    painter.dispose();
    return Semantics(
      label: current,
      child: ExcludeSemantics(
        child: SizedBox(
          width: width.ceilToDouble(),
          child: AnimatedSwitcher(
            duration: motionDuration(context, 150),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            child: Text(current, key: ValueKey(current)),
          ),
        ),
      ),
    );
  }
}

class FeedbackIssue extends StatelessWidget {
  const FeedbackIssue({
    super.key,
    required this.feedback,
    this.onRetry,
    this.actionLabel = '重试',
  });
  final ActionFeedback feedback;

  /// Null when the issue offers no action.
  final VoidCallback? onRetry;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: feedback,
    builder: (context, _) => IssueBanner(
      issue: feedback.issue,
      onAction: onRetry,
      actionLabel: actionLabel,
    ),
  );
}

/// A tinted line naming what went wrong, unfolding while [issue] is set.
class IssueBanner extends StatefulWidget {
  const IssueBanner({
    super.key,
    required this.issue,
    this.onAction,
    this.actionLabel = '重试',
  });
  final String? issue;

  /// Null when the issue offers no action.
  final VoidCallback? onAction;
  final String actionLabel;

  @override
  State<IssueBanner> createState() => _IssueBannerState();
}

class _IssueBannerState extends State<IssueBanner> {
  /// The last issue, and its action, kept while the banner folds away.
  String? _issue;
  VoidCallback? _action;
  String _actionLabel = '';

  @override
  Widget build(BuildContext context) {
    if (widget.issue != null) {
      _issue = widget.issue;
      _action = widget.onAction;
      _actionLabel = widget.actionLabel;
    }
    final scheme = Theme.of(context).colorScheme;
    return MotionReveal(
      visible: widget.issue != null,
      child: _issue == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: .45),
                    borderRadius: controlBorderRadius,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: scheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _issue!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (_action != null)
                        TextButton(
                          onPressed: widget.issue == null ? null : _action,
                          child: Text(_actionLabel),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// The tone for words about something that went wrong: the error hue,
/// drawn toward the muted text colour so a failure reads calmly.
Color issueColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Color.lerp(scheme.error, scheme.onSurfaceVariant, .3)!;
}

/// One compact line naming what went wrong, for a row, card or form whose
/// failure belongs right beside it; [IssueBanner] for a whole panel.
class InlineIssue extends StatelessWidget {
  const InlineIssue(
    this.text, {
    super.key,
    this.onRetry,
    this.actionLabel = '重试',
    this.maxLines,
  });
  final String text;

  /// Null when the issue offers no action.
  final VoidCallback? onRetry;
  final String actionLabel;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final color = issueColor(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    final line = Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.error_outline_rounded, size: 14, color: color),
            ),
          ),
          TextSpan(text: text),
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
    return Semantics(
      liveRegion: true,
      child: onRetry == null
          ? line
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: line),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
    );
  }
}

/// Shows [text] in the app's snackbar, the one place transient messages
/// and failures without a place of their own appear.
void showMessage(
  ScaffoldMessengerState? messenger,
  String text, {
  String? actionLabel,
  VoidCallback? onAction,
}) => messenger?.showSnackBar(
  SnackBar(
    content: Text(text),
    action: actionLabel == null || onAction == null
        ? null
        : SnackBarAction(label: actionLabel, onPressed: onAction),
  ),
);
