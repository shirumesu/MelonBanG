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
        icon: AnimatedSwitcher(
          duration: motionDuration(context, 150),
          child: feedback.busy
              ? const SizedBox.square(
                  key: ValueKey('busy'),
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  feedback.succeeded ? Icons.check_rounded : icon,
                  key: ValueKey(feedback.succeeded),
                  size: 18,
                ),
        ),
        label: Text(
          feedback.busy
              ? runningLabel
              : feedback.succeeded
              ? successLabel
              : label,
        ),
      ),
    ),
  );
}

class FeedbackIssue extends StatelessWidget {
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: feedback,
    builder: (context, _) {
      if (feedback.issue == null) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      return Padding(
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
                    feedback.issue!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(onPressed: onRetry, child: Text(actionLabel)),
              ],
            ),
          ),
        ),
      );
    },
  );
}
