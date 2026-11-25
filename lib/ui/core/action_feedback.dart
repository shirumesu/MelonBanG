import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/error_message.dart';
import '../../core/notices.dart';
import 'motion.dart';
import 'theme.dart';
import 'tone.dart';

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
  });
  final ActionFeedback feedback;
  final String label, runningLabel, successLabel;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: feedback,
    builder: (context, _) => DelayedBusy(
      busy: feedback.busy,
      builder: (context, spinning) => _button(context, spinning),
    ),
  );

  /// The button; [spinning] once the action has run long enough to show.
  Widget _button(BuildContext context, bool spinning) {
    final current = spinning
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
        child: spinning
            ? const Padding(
                key: ValueKey('busy'),
                padding: EdgeInsets.all(1),
                child: BusyIndicator(),
              )
            : Icon(
                feedback.succeeded ? Icons.check_rounded : icon,
                key: ValueKey(feedback.succeeded),
                size: 18,
              ),
      ),
    );
    return Semantics(
      liveRegion: true,
      child: TextButton.icon(
        onPressed: feedback.busy || spinning ? null : onPressed,
        style: TextButton.styleFrom(
          disabledForegroundColor: Theme.of(context).colorScheme.primary,
        ),
        icon: glyph,
        label: _FeedbackLabel(
          labels: [label, runningLabel, successLabel],
          current: current,
        ),
      ),
    );
  }
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
      actions: [
        if (onRetry case final retry?) NoticeAction(actionLabel, retry),
      ],
    ),
  );
}

/// A tinted strip naming what went wrong or needs a look, unfolding while
/// [issue] is set. A whole operation failing is [NoticeTone.failed]; one
/// part of several, with the rest still shown, [NoticeTone.warning].
class IssueBanner extends StatefulWidget {
  const IssueBanner({
    super.key,
    required this.issue,
    this.tone = NoticeTone.failed,
    this.actions = const [],
  });
  final String? issue;
  final NoticeTone tone;
  final List<NoticeAction> actions;

  @override
  State<IssueBanner> createState() => _IssueBannerState();
}

class _IssueBannerState extends State<IssueBanner> {
  /// The last issue, its tone and actions, kept while the banner folds away.
  String? _issue;
  NoticeTone _tone = NoticeTone.failed;
  List<NoticeAction> _actions = const [];

  @override
  Widget build(BuildContext context) {
    if (widget.issue != null) {
      _issue = widget.issue;
      _tone = widget.tone;
      _actions = widget.actions;
    }
    return MotionReveal(
      visible: widget.issue != null,
      child: _issue == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.md,
                    Gap.xs,
                    Gap.xs,
                    Gap.xs,
                  ),
                  decoration: BoxDecoration(
                    color: toneContainer(context, _tone),
                    borderRadius: controlBorderRadius,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        toneIcon(_tone),
                        size: 18,
                        color: toneColor(context, _tone),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          _issue!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      for (final action in _actions)
                        TextButton(
                          onPressed: widget.issue == null
                              ? null
                              : action.onPressed,
                          child: Text(action.label),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// One line naming what went wrong or needs a look, beside the row, card or
/// field it is about; [IssueBanner] for a whole panel. Only the icon takes
/// [tone]'s colour.
class InlineIssue extends StatelessWidget {
  const InlineIssue(
    this.text, {
    super.key,
    this.tone = NoticeTone.failed,
    this.onRetry,
    this.actionLabel = '重试',
    this.maxLines,
  });
  final String text;
  final NoticeTone tone;

  /// Null when the issue offers no action.
  final VoidCallback? onRetry;
  final String actionLabel;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final line = Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: Icon(
                toneIcon(tone),
                size: 14,
                color: toneColor(context, tone),
              ),
            ),
          ),
          TextSpan(text: text),
        ],
      ),
      style: Theme.of(context).textTheme.bodySmall,
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
                const SizedBox(width: Gap.xs),
                TextButton(
                  onPressed: onRetry,
                  style: compactTextButtonStyle,
                  child: Text(actionLabel),
                ),
              ],
            ),
    );
  }
}
