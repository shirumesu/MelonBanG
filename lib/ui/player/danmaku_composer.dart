import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/error_message.dart';
import '../../domain/danmaku.dart';
import '../../features/danmaku/danmaku_preferences.dart';
import '../../features/playback/playback.dart';
import '../core/theme.dart';
import 'player_popovers.dart';

/// The comment field: its look on the left, sending on the right. Enter
/// sends, an empty Enter or Escape gives the keys back to the video.
class DanmakuComposer extends StatefulWidget {
  const DanmakuComposer({
    super.key,
    required this.playback,
    required this.draft,
    required this.focusNode,
    required this.onPopupChanged,
    required this.onFeedback,
    required this.onDone,
    required this.hint,
  });
  final Playback playback;
  final TextEditingController draft;
  final FocusNode focusNode;
  final ValueChanged<bool> onPopupChanged;
  final ValueChanged<String> onFeedback;
  final VoidCallback onDone;

  /// The empty field's line while it can send.
  final String hint;

  /// The narrowest it is shown at; the field keeps about eight characters.
  static const minWidth = 220.0;

  @override
  State<DanmakuComposer> createState() => _DanmakuComposerState();
}

class _DanmakuComposerState extends State<DanmakuComposer> {
  bool _sending = false;

  /// Counts down the wait between comments.
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Whole seconds until the next comment may go.
  int get _wait {
    final after = widget.playback.danmaku.sendAfter;
    if (after == null) return 0;
    final left = after.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  void _countDown() {
    _tick?.cancel();
    if (_wait == 0) return;
    _tick = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {});
      if (_wait == 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    final text = widget.draft.text.trim();
    if (text.isEmpty) {
      widget.onDone();
      return;
    }
    if (_wait case final wait when wait > 0) {
      widget.onFeedback('$wait 秒后才能再发送');
      return;
    }
    if (_sending) return;
    setState(() => _sending = true);
    final player = widget.playback.player;
    try {
      await widget.playback.danmaku.send(
        player.state.position.inMilliseconds / 1000,
        text,
      );
      widget.draft.clear();
      widget.onDone();
    } catch (e) {
      widget.onFeedback(
        e is StateError ? errorMessage(e) : '弹幕发送失败：${errorMessage(e)}',
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _countDown();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final danmaku = widget.playback.danmaku;
    final blocked = danmaku.sendBlocked;
    final wait = _wait;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: DanmakuComposer.minWidth,
        maxWidth: 400,
      ),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(
          children: [
            _SendStyleMenu(
              preferences: danmaku.preferences,
              onPopupChanged: widget.onPopupChanged,
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.draft,
                builder: (context, _) => TextField(
                  controller: widget.draft,
                  focusNode: widget.focusNode,
                  enabled: blocked == null,
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  inputFormatters: [LengthLimitingTextInputFormatter(100)],
                  onSubmitted: (_) => unawaited(_send()),
                  cursorColor: Colors.white,
                  cursorHeight: 15,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintText: blocked ?? widget.hint,
                    hintMaxLines: 1,
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Colors.white38,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(3),
              child: ListenableBuilder(
                listenable: widget.draft,
                builder: (context, _) => FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xff15181d),
                    disabledBackgroundColor: Colors.white.withValues(
                      alpha: .12,
                    ),
                    disabledForegroundColor: Colors.white38,
                    minimumSize: const Size(52, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed:
                      blocked == null &&
                          !_sending &&
                          wait == 0 &&
                          widget.draft.text.trim().isNotEmpty
                      ? () => unawaited(_send())
                      : null,
                  child: Text(
                    wait > 0 ? '$wait 秒' : '发送',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How a sent comment looks: where it runs and its colour. The A shows the
/// colour chosen.
class _SendStyleMenu extends StatelessWidget {
  const _SendStyleMenu({
    required this.preferences,
    required this.onPopupChanged,
  });
  final DanmakuPreferences preferences;
  final ValueChanged<bool> onPopupChanged;

  /// Bilibili's palette for sending.
  static const colors = [
    0xfe0302, 0xff7204, 0xffaa02, 0xffd302, 0xffff00, 0xa0ee00, 0x00cd00, //
    0x019899, 0x4266be, 0x89d5ff, 0xcc0273, 0x222222, 0x9b9b9b, 0xffffff,
  ];
  static const modes = {
    DanmakuMode.scroll: '滚动',
    DanmakuMode.top: '顶部',
    DanmakuMode.bottom: '底部',
  };
  static const _ink = Color(0xff15181d);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: preferences.sendStyle,
    builder: (context, style, _) => HoverPopover(
      onPopupChanged: onPopupChanged,
      anchor: (popover) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          overlayColor: const WidgetStatePropertyAll(Colors.white12),
          onTap: popover.toggle,
          child: SizedBox(
            width: 34,
            height: 30,
            child: Center(
              child: Text(
                'A',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff000000 | style.color),
                  shadows: const [Shadow(blurRadius: 2)],
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white54,
                ),
              ),
            ),
          ),
        ),
      ),
      popover: (popover) => Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: SizedBox(
          width: 7 * 26 + 6 * 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 28,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: badgeBorderRadius,
                ),
                child: Row(
                  children: [
                    for (final MapEntry(key: mode, value: label)
                        in modes.entries)
                      Expanded(
                        child: Material(
                          color: mode == style.mode
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => preferences.sendStyle.value = (
                              mode: mode,
                              color: style.color,
                            ),
                            child: Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: mode == style.mode
                                      ? _ink
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final color in colors)
                    Semantics(
                      selected: color == style.color,
                      label: '#${color.toRadixString(16).padLeft(6, '0')}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => preferences.sendStyle.value = (
                          mode: style.mode,
                          color: color,
                        ),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Color(0xff000000 | color),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: color == style.color
                                  ? Colors.white
                                  : Colors.white24,
                              width: color == style.color ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
