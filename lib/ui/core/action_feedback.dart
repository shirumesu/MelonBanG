import 'dart:async';

import 'package:flutter/material.dart';

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
      result = e.toString().replaceFirst('Bad state: ', '');
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
  });
  final ActionFeedback feedback;
  final String label, runningLabel, successLabel;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: feedback,
    builder: (context, _) => Semantics(
      liveRegion: true,
      child: TextButton.icon(
        onPressed: feedback.busy ? null : onPressed,
        style: TextButton.styleFrom(
          disabledForegroundColor: Theme.of(context).colorScheme.primary,
        ),
        icon: SizedBox.square(
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
        ),
        label: _FeedbackLabel(
          labels: [label, runningLabel, successLabel],
          current: feedback.busy
              ? runningLabel
              : feedback.succeeded
              ? successLabel
              : label,
        ),
      ),
    ),
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

class FeedbackIssue extends StatefulWidget {
  const FeedbackIssue({
    super.key,
    required this.feedback,
    required this.onRetry,
    this.actionLabel = '重试',
  });
  final ActionFeedback feedback;
  final VoidCallback onRetry;
  final String actionLabel;

  @override
  State<FeedbackIssue> createState() => _FeedbackIssueState();
}

class _FeedbackIssueState extends State<FeedbackIssue> {
  String? _lastIssue;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.feedback,
    builder: (context, _) {
      _lastIssue = widget.feedback.issue ?? _lastIssue;
      final scheme = Theme.of(context).colorScheme;
      return MotionReveal(
        visible: widget.feedback.issue != null,
        child: _lastIssue == null
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
                            _lastIssue!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: widget.onRetry,
                          child: Text(widget.actionLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      );
    },
  );
}
