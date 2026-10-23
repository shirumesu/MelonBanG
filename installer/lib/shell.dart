import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bot.dart';
import 'install.dart';

// MelonBanG's palette; see Design/brand.md.
const mint = Color(0xff22b388);
const deep = Color(0xff168364);
const ink = Color(0xff263833);
const muted = Color(0xff6f7d78);
const coral = Color(0xffff6b81);
const danger = Color(0xffe8445a);
const gold = Color(0xffffb83d);
const canvas = Color(0xfff3f5f4);
const surface = Color(0xfffbfcfb);
const _stage = Color(0xffeaf5ef);
const _plate = Color(0xffddf0e6);

const _easeOut = Cubic(0.22, 1, 0.36, 1);

/// The pointer in global coordinates, which the character turns toward.
final pointer = ValueNotifier<Offset?>(null);

class SetupApp extends StatelessWidget {
  const SetupApp({super.key, required this.title, required this.home});
  final String title;
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: title,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'Resource Han Rounded',
      colorScheme: ColorScheme.fromSeed(seedColor: mint)
          .copyWith(primary: deep, surface: surface, onSurface: ink),
      scaffoldBackgroundColor: surface,
      textSelectionTheme: const TextSelectionThemeData(
        selectionColor: Color(0x4422b388),
      ),
    ),
    home: MouseRegion(
      onHover: (event) => pointer.value = event.position,
      onExit: (_) => pointer.value = null,
      child: home,
    ),
  );
}

/// The window: the character's stage on the left, content on the right.
class SetupShell extends StatelessWidget {
  const SetupShell({
    super.key,
    required this.step,
    required this.content,
    required this.mode,
    this.tone = BotTone.mint,
    this.progress = 0,
    this.closable = true,
    this.onClose = closeWindow,
  });

  /// Identifies the current step; changing it animates the content in.
  final Object step;
  final Widget content;
  final BotMode mode;
  final BotTone tone;
  final double progress;
  final bool closable;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onPanStart: (_) => startDrag(),
          child: _Stage(mode: mode, tone: tone, progress: progress),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TitleBar(onClose: closable ? onClose : null),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(44, 12, 44, 36),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    layoutBuilder: (current, previous) =>
                        Stack(children: [...previous, ?current]),
                    child: KeyedSubtree(key: ValueKey(step), child: content),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.mode,
    required this.tone,
    required this.progress,
  });
  final BotMode mode;
  final BotTone tone;
  final double progress;

  @override
  Widget build(BuildContext context) => Container(
    width: 296,
    color: _stage,
    child: Stack(
      children: [
        Positioned(
          left: 28,
          top: 66,
          child: Container(
            width: 240,
            height: 240,
            decoration: const BoxDecoration(
              color: _plate,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const Positioned(left: 40, top: 60, child: _Twinkle(22, gold, 0)),
        const Positioned(left: 246, top: 96, child: _Twinkle(14, coral, 0.33)),
        const Positioned(left: 236, top: 288, child: _Twinkle(12, mint, 0.66)),
        Positioned(
          left: 48,
          top: 78,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (mode == BotMode.cheer) const Positioned.fill(child: _Burst()),
              Bot(mode: mode, tone: tone, progress: progress, pointer: pointer),
            ],
          ),
        ),
        Positioned(
          left: 22,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset('assets/logotype.png', width: 176),
              const SizedBox(height: 4),
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: deep.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  appVersion,
                  style: TextStyle(
                    color: deep,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A four-point star that slowly pulses, starting at [phase] of its cycle.
class _Twinkle extends StatefulWidget {
  const _Twinkle(this.size, this.colour, this.phase);
  final double size;
  final Color colour;
  final double phase;
  @override
  State<_Twinkle> createState() => _TwinkleState();
}

class _TwinkleState extends State<_Twinkle>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final star = CustomPaint(
      size: Size.square(widget.size),
      painter: _StarPainter(widget.colour),
    );
    if (MediaQuery.disableAnimationsOf(context)) return star;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final wave =
            (1 - math.cos(2 * math.pi * (_controller.value + widget.phase))) /
            2;
        return Opacity(
          opacity: 0.45 + 0.55 * wave,
          child: Transform.scale(scale: 0.6 + 0.4 * wave, child: child),
        );
      },
      child: star,
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    canvas.translate(r, r);
    final k = r / 14;
    final star = Path()
      ..moveTo(0, -14 * k)
      ..quadraticBezierTo(2 * k, -2 * k, 14 * k, 0)
      ..quadraticBezierTo(2 * k, 2 * k, 0, 14 * k)
      ..quadraticBezierTo(-2 * k, 2 * k, -14 * k, 0)
      ..quadraticBezierTo(-2 * k, -2 * k, 0, -14 * k)
      ..close();
    canvas.drawPath(star, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_StarPainter oldDelegate) => oldDelegate.colour != colour;
}

/// Coloured dots flying out of the character once, on completion.
class _Burst extends StatefulWidget {
  const _Burst();
  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  static const _colours = [
    mint,
    gold,
    coral,
    mint,
    Color(0xff8bbcf6),
    gold,
    mint,
    coral,
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final t = _easeOut.transform(_controller.value);
      final fade = _controller.value < 0.12
          ? _controller.value / 0.12
          : _controller.value < 0.7
          ? 1.0
          : 1 - (_controller.value - 0.7) / 0.3;
      return Stack(
        children: [
          for (var i = 0; i < 8; i++)
            Positioned(
              left: 95 + math.sin(i * math.pi / 4) * 124 * t,
              top: 99 - math.cos(i * math.pi / 4) * 124 * t,
              child: Opacity(
                opacity: _controller.isAnimating ? fade : 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _colours[i],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.onClose});
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanStart: (_) => startDrag(),
    child: Container(
      height: 40,
      color: Colors.transparent,
      padding: const EdgeInsets.only(right: 4),
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WindowButton(
            tooltip: '最小化',
            icon: Icons.remove,
            onPressed: minimize,
          ),
          _WindowButton(
            tooltip: '关闭',
            icon: Icons.close,
            onPressed: onClose,
            closing: true,
          ),
        ],
      ),
    ),
  );
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.closing = false,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool closing;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    style: ButtonStyle(
      fixedSize: const WidgetStatePropertyAll(Size(40, 32)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? muted.withValues(alpha: 0.35)
            : closing && states.contains(WidgetState.hovered)
            ? Colors.white
            : states.contains(WidgetState.hovered)
            ? ink
            : muted,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => !states.contains(WidgetState.hovered)
            ? Colors.transparent
            : closing
            ? danger
            : const Color(0xffeef2f0),
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}

/// Slides its child up into place [index] steps after its step appears.
class Rise extends StatefulWidget {
  const Rise(this.index, this.child, {super.key});
  final int index;
  final Widget child;
  @override
  State<Rise> createState() => _RiseState();
}

class _RiseState extends State<Rise> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final curve = CurvedAnimation(parent: _controller, curve: _easeOut);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

/// Shakes its child sideways whenever [trigger] changes.
class Shake extends StatelessWidget {
  const Shake({super.key, required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(trigger),
    tween: Tween(begin: trigger == 0 ? 1.0 : 0.0, end: 1.0),
    duration: const Duration(milliseconds: 460),
    builder: (context, t, child) => Transform.translate(
      offset: Offset(math.sin(t * math.pi * 8) * 5 * (1 - t), 0),
      child: child,
    ),
    child: child,
  );
}

const heading = TextStyle(
  fontSize: 26,
  fontWeight: FontWeight.w700,
  height: 1.3,
);
const intro = TextStyle(fontSize: 14, height: 1.6, color: muted);
const note = TextStyle(fontSize: 12, height: 1.6, color: muted);

enum ActionStyle { primary, ink, danger, ghost }

/// A large rounded action that lifts on hover and dips when pressed.
class SetupButton extends StatefulWidget {
  const SetupButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.style = ActionStyle.primary,
    this.icon,
    this.trailing,
  });
  final String label;
  final VoidCallback? onPressed;
  final ActionStyle style;
  final IconData? icon;

  /// An icon after the label, such as an arrow.
  final IconData? trailing;
  @override
  State<SetupButton> createState() => _SetupButtonState();
}

class _SetupButtonState extends State<SetupButton> {
  bool _hovered = false, _pressed = false;

  @override
  Widget build(BuildContext context) {
    final (background, hover, foreground) = switch (widget.style) {
      ActionStyle.primary => (deep, const Color(0xff13745a), Colors.white),
      ActionStyle.ink => (ink, const Color(0xff1b2a26), Colors.white),
      ActionStyle.danger => (danger, const Color(0xffd33a4f), Colors.white),
      ActionStyle.ghost => (Colors.transparent, const Color(0xffeef2f0), ink),
    };
    final filled = widget.style != ActionStyle.ghost;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = _pressed = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 140),
          curve: _easeOut,
          child: AnimatedSlide(
            offset: Offset(0, _hovered && !_pressed ? -0.03 : 0),
            duration: const Duration(milliseconds: 140),
            curve: _easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 46,
              constraints: BoxConstraints(minWidth: filled ? 112 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: _hovered ? hover : background,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  if (filled)
                    BoxShadow(
                      color: background.withValues(alpha: 0.5),
                      blurRadius: _hovered ? 22 : 16,
                      spreadRadius: -7,
                      offset: Offset(0, _hovered ? 10 : 6),
                    ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon case final icon?) ...[
                    Icon(icon, size: 18, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: filled ? FontWeight.w700 : FontWeight.w400,
                      color: foreground,
                    ),
                  ),
                  if (widget.trailing case final icon?) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 18, color: foreground),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The big percentage, the bar with a passing sheen and the current task.
class ProgressBlock extends StatefulWidget {
  const ProgressBlock({
    super.key,
    required this.progress,
    required this.task,
    required this.colour,
  });
  final double progress;
  final String task;
  final Color colour;
  @override
  State<ProgressBlock> createState() => _ProgressBlockState();
}

class _ProgressBlockState extends State<ProgressBlock>
    with SingleTickerProviderStateMixin {
  late final _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${(widget.progress * 100).round()}',
              style: TextStyle(
                fontSize: 64,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -2,
                color: widget.colour,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '%',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: widget.colour,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: ColoredBox(
              color: const Color(0xffe1e8e3),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: widget.progress),
                  duration: Duration(milliseconds: still ? 0 : 280),
                  curve: _easeOut,
                  builder: (context, value, _) => FractionallySizedBox(
                    widthFactor: value,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: ColoredBox(
                        color: widget.colour,
                        child: still
                            ? const SizedBox.expand()
                            : AnimatedBuilder(
                                animation: _sheen,
                                builder: (context, _) => FractionallySizedBox(
                                  widthFactor: 0.4,
                                  alignment: Alignment(
                                    -3 + 6 * _sheen.value,
                                    0,
                                  ),
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0x00ffffff),
                                          Color(0x99ffffff),
                                          Color(0x00ffffff),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.task,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: note,
        ),
      ],
    );
  }
}

/// A rounded panel on the canvas tint, used for fields and choices.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.colour = canvas,
    this.ring,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 14, 14),
  });
  final Widget child;
  final Color colour;
  final Color? ring;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    padding: padding,
    decoration: BoxDecoration(
      color: colour,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: ring ?? colour, width: 1.5),
    ),
    child: child,
  );
}
