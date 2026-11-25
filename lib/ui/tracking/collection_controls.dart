import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/collection_edit.dart';
import '../core/collection_labels.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';

/// Ten stars scoring 1–10, previewed under the pointer or with ← and →.
/// [onTap] fires even when [enabled] is false, so callers can explain why
/// scoring is unavailable.
class StarRating extends StatefulWidget {
  const StarRating({
    super.key,
    required this.value,
    required this.onTap,
    required this.labelWidth,
    this.enabled = true,
    this.size = 18,
  });
  final int value;
  final ValueChanged<int> onTap;
  final bool enabled;
  final double size;

  /// Room for the longest label, "5 不过不失" or "10 超神作".
  final double labelWidth;

  @override
  State<StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends State<StarRating> {
  int hover = 0;

  /// The star last tapped and how many taps there were, so each tap gives
  /// that star a small bounce.
  int popped = 0, pops = 0;

  /// Whether the stars have keyboard focus and show its ring.
  bool highlighted = false;

  void _pick(int n) {
    if (widget.enabled) {
      setState(() {
        popped = n;
        pops++;
      });
    }
    widget.onTap(n);
  }

  /// Moves the keyboard preview by [step] stars.
  void _step(int step) {
    if (!widget.enabled) return;
    final from = hover > 0 ? hover : widget.value;
    setState(() => hover = (from + step).clamp(1, 10));
  }

  void _confirm() {
    final n = widget.enabled && hover > 0 ? hover : widget.value;
    setState(() => hover = 0);
    _pick(math.max(n, 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = scheme.surfaceContainerHighest;
    final shown = widget.enabled && hover > 0 ? hover : widget.value;
    final stars = MouseRegion(
      onExit: (_) => setState(() => hover = 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var n = 1; n <= 10; n++)
            Semantics(
              button: true,
              label: '$n 分',
              selected: widget.value == n,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => hover = n),
                child: GestureDetector(
                  onTap: () => _pick(n),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: .5),
                    child: _Star(
                      key: ValueKey(n == popped ? pops : 0),
                      pop: n == popped && pops > 0,
                      lifted: widget.enabled && hover == n,
                      size: widget.size,
                      color: n > shown
                          ? empty
                          : hover > 0 && widget.enabled
                          ? gold.withValues(alpha: .6)
                          : widget.enabled
                          ? gold
                          : gold.withValues(alpha: .35),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FocusableActionDetector(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(-1),
            SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(1),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            _StepIntent: CallbackAction<_StepIntent>(
              onInvoke: (intent) => _step(intent.step),
            ),
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => _confirm(),
            ),
          },
          onShowFocusHighlight: (value) => setState(() => highlighted = value),
          // A preview left by the keyboard goes when focus does.
          onFocusChange: (focused) {
            if (!focused && hover > 0) setState(() => hover = 0);
          },
          child: Semantics(
            label: '评分',
            hint: '左右方向键选择，回车确认',
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: badgeBorderRadius,
                border: highlighted
                    ? Border.all(
                        color: scheme.primary.withValues(alpha: .7),
                        width: 1.5,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      )
                    : null,
              ),
              child: stars,
            ),
          ),
        ),
        const SizedBox(width: Gap.sm),
        // Fixed height: the label's size changes with hover, and a shifting
        // row would move the stars out from under the pointer.
        SizedBox(
          width: widget.labelWidth,
          height: 28,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ScoreText(shown),
          ),
        ),
      ],
    );
  }
}

class _StepIntent extends Intent {
  const _StepIntent(this.step);
  final int step;
}

/// One star; [pop] bounces it once, just after a tap.
class _Star extends StatelessWidget {
  const _Star({
    super.key,
    required this.color,
    required this.size,
    required this.lifted,
    required this.pop,
  });
  final Color color;
  final double size;
  final bool lifted, pop;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: pop ? 0 : 1, end: 1),
    duration: motionDuration(context, 380),
    builder: (context, bounce, child) => Transform.scale(
      scale: 1 + math.sin(bounce * math.pi) * .3,
      child: child,
    ),
    child: AnimatedScale(
      scale: lifted ? 1.18 : 1,
      duration: motionDuration(context, 160),
      curve: Curves.easeOutCubic,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: motionDuration(context, 140),
        builder: (context, color, _) =>
            Icon(Icons.star_rounded, size: size, color: color),
      ),
    ),
  );
}

class _ScoreText extends StatelessWidget {
  const _ScoreText(this.score);
  final int score;

  @override
  Widget build(BuildContext context) => score <= 0
      ? Text('未评分', style: Theme.of(context).textTheme.bodySmall)
      : Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$score',
                style: const TextStyle(
                  fontSize: FontSize.emphasis,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: ' ${scoreLabels[score]}',
                style: TextStyle(
                  fontSize: FontSize.small,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          maxLines: 1,
        );
}

/// Popular tags as on/off chips.
class TagToggles extends StatelessWidget {
  const TagToggles({
    super.key,
    required this.tags,
    required this.selected,
    required this.onToggle,
  });
  final Iterable<String> tags;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Gap.sm,
    runSpacing: Gap.sm,
    children: [
      for (final tag in tags)
        FilterChip(
          label: Text(tag),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          selected: selected.contains(tag),
          onSelected: (_) => onToggle(tag),
        ),
    ],
  );
}

/// "+ 添加" chip opening a small tag menu: free input plus popular tags.
class TagAdder extends StatefulWidget {
  const TagAdder({
    super.key,
    required this.tags,
    required this.popular,
    required this.blocked,
    required this.onBlocked,
    required this.onSave,
  });
  final List<String> tags, popular;
  final bool blocked;
  final VoidCallback onBlocked;

  /// Returns a validation message, or null once saved.
  final Future<String?> Function(List<String>) onSave;

  @override
  State<TagAdder> createState() => _TagAdderState();
}

class _TagAdderState extends State<TagAdder> {
  final input = TextEditingController();
  String? error;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _save(List<String> tags) async {
    final message = await widget.onSave(tags);
    if (!mounted) return;
    setState(() => error = message);
    if (message == null) input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return MelonMenuAnchor(
      onClose: () => setState(() => error = null),
      menuChildren: [
        // With the menu's own 4px, 12px around the field.
        Padding(
          padding: const EdgeInsets.all(Gap.sm),
          child: SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: input,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '输入标签，回车或逗号添加',
                    errorText: error,
                  ),
                  onSubmitted: (value) => unawaited(
                    _save([...widget.tags, ...splitCollectionTags(value)]),
                  ),
                  onChanged: (value) {
                    if (endsWithTagSeparator(value)) {
                      unawaited(
                        _save([...widget.tags, ...splitCollectionTags(value)]),
                      );
                    }
                  },
                ),
                if (widget.popular.isNotEmpty) ...[
                  const SizedBox(height: Gap.md),
                  Text('大家常用', style: small),
                  const SizedBox(height: Gap.sm),
                  TagToggles(
                    tags: widget.popular,
                    selected: widget.tags.toSet(),
                    onToggle: (tag) => unawaited(
                      _save(
                        widget.tags.contains(tag)
                            ? ([...widget.tags]..remove(tag))
                            : [...widget.tags, tag],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Gap.sm),
                Text('${widget.tags.length}/$collectionTagLimit', style: small),
              ],
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => ActionChip(
        avatar: const Icon(Icons.add_rounded, size: 16),
        label: const Text('添加'),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: () {
          if (widget.blocked) {
            widget.onBlocked();
          } else if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
    );
  }
}
