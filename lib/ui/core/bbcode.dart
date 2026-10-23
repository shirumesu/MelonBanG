import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cached_image.dart';
import 'subject_posters.dart' show imageDecodeWidth;
import 'theme.dart';

/// Bangumi BBCode as Bangumi shows it: stickers and images inline, spoilers
/// blacked out until hovered or tapped, quotes, code, alignment, colour,
/// size and links, selectable as text. Parsing follows bangumi/frontend's `packages/utils/bbcode`:
/// a tag that does not close or fails its check stays as plain text.
class BBCode extends StatefulWidget {
  const BBCode(this.source, {super.key, this.style});
  final String source;
  final TextStyle? style;

  @override
  State<BBCode> createState() => _BBCodeState();
}

String _normalized(String source) => source.replaceAll('\r\n', '\n').trim();

class _BBCodeState extends State<BBCode> {
  late List<_Node> _nodes = _Parser(_normalized(widget.source)).parse();

  /// Spoilers shown, by their order in the text.
  final _revealed = <int>{};

  /// Tap handlers by the order of their links and spoilers; kept across
  /// rebuilds so revealing a spoiler does not drop a tap in progress.
  final _taps = <TapGestureRecognizer>[];

  @override
  void didUpdateWidget(BBCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source == widget.source) return;
    _nodes = _Parser(_normalized(widget.source)).parse();
    _revealed.clear();
    _disposeTaps();
  }

  @override
  void dispose() {
    _disposeTaps();
    super.dispose();
  }

  void _reveal(int spoiler, bool value) {
    if (value == _revealed.contains(spoiler)) return;
    setState(() => value ? _revealed.add(spoiler) : _revealed.remove(spoiler));
  }

  void _disposeTaps() {
    for (final tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
  }

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(widget.style);
    final blocks = _Renderer(this, context, base).blocks(_nodes, base);
    return SelectionArea(
      child: DefaultTextStyle.merge(
        style: widget.style,
        child: blocks.length == 1
            ? blocks.single
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: blocks,
              ),
      ),
    );
  }
}

/// Builds one pass of widgets; links and spoilers are numbered in the order
/// they appear, so their state survives the next pass.
class _Renderer {
  _Renderer(this.state, this.context, this.base);
  final _BBCodeState state;
  final BuildContext context;
  final TextStyle base;
  int _tap = 0, _mask = 0;

  ColorScheme get scheme => Theme.of(context).colorScheme;

  TapGestureRecognizer _recognizer(VoidCallback onTap) {
    final taps = state._taps;
    if (_tap == taps.length) taps.add(TapGestureRecognizer());
    return taps[_tap++]..onTap = onTap;
  }

  static const _blockTags = {
    'quote',
    'code',
    'left',
    'right',
    'center',
    'align',
    'indent',
  };

  /// Paragraphs and block tags, top to bottom. The line breaks around a
  /// block belong to it.
  List<Widget> blocks(List<_Node> nodes, TextStyle style) {
    final result = <Widget>[];
    var inline = <_Node>[];
    void flush() {
      final spans = this.inline(_trimBreaks(inline), style);
      if (spans.isNotEmpty) {
        result.add(Text.rich(TextSpan(style: style, children: spans)));
      }
      inline = [];
    }

    for (final node in nodes) {
      if (node is _Code || node is _Tag && _blockTags.contains(node.name)) {
        flush();
        result.add(_block(node, style));
      } else {
        inline.add(node);
      }
    }
    flush();
    return result;
  }

  /// [nodes] without the line breaks at their ends.
  static List<_Node> _trimBreaks(List<_Node> nodes) {
    final result = [...nodes];
    if (result.firstOrNull case _Text(:final text)) {
      final trimmed = text.replaceFirst(RegExp(r'^\n+'), '');
      if (trimmed.isEmpty) {
        result.removeAt(0);
      } else {
        result[0] = _Text(trimmed);
      }
    }
    if (result.lastOrNull case _Text(:final text)) {
      final trimmed = text.replaceFirst(RegExp(r'\n+$'), '');
      if (trimmed.isEmpty) {
        result.removeLast();
      } else {
        result[result.length - 1] = _Text(trimmed);
      }
    }
    return result;
  }

  Widget _block(_Node node, TextStyle style) {
    const gap = EdgeInsets.symmetric(vertical: 4);
    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    switch (node) {
      case _Code(:final text):
        return Container(
          margin: gap,
          padding: const EdgeInsets.all(Gap.sm),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: badgeBorderRadius,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              text.replaceFirst(RegExp(r'^\n'), ''),
              style: style.copyWith(
                fontSize: (style.fontSize ?? 13) - 1,
                height: 1.45,
                fontFamily: 'Menlo',
                fontFamilyFallback: const ['Consolas', 'monospace'],
              ),
            ),
          ),
        );
      case _Tag(name: 'quote', :final children):
        final quoted = style.copyWith(color: scheme.onSurfaceVariant);
        return Container(
          margin: gap,
          padding: const EdgeInsets.fromLTRB(Gap.md, 6, Gap.sm, 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: badgeBorderRadius,
            border: Border(
              left: BorderSide(color: scheme.outlineVariant, width: 3),
            ),
          ),
          child: DefaultTextStyle.merge(
            style: quoted,
            child: column(blocks(children, quoted)),
          ),
        );
      case _Tag(name: 'indent', :final children):
        return Padding(
          padding: const EdgeInsets.only(left: Gap.xl),
          child: column(blocks(children, style)),
        );
      case _Tag(:final name, :final value, :final children):
        final align = switch (name == 'align' ? value : name) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          _ => TextAlign.left,
        };
        final spans = inline(_trimBreaks(children), style);
        return Text.rich(
          TextSpan(style: style, children: spans),
          textAlign: align,
        );
      case _Text() || _Sticker():
        return Text.rich(
          TextSpan(style: style, children: inline([node], style)),
        );
    }
  }

  /// [nodes] as spans in [style]; [mask] is the spoiler they sit in.
  List<InlineSpan> inline(List<_Node> nodes, TextStyle style, {int? mask}) {
    final spans = <InlineSpan>[];
    final hidden = mask != null && !state._revealed.contains(mask);
    for (final node in nodes) {
      switch (node) {
        case _Text(:final text):
          spans.add(TextSpan(text: text, style: style));
        case _Code(:final text):
          spans.add(TextSpan(text: text, style: style));
        case _Sticker():
          spans.add(_sticker(node, hidden: hidden));
        case _Tag(:final name, :final value, :final children):
          spans.addAll(switch (name) {
            'b' => inline(
              children,
              style.copyWith(fontWeight: FontWeight.w700),
              mask: mask,
            ),
            'i' => inline(
              children,
              style.copyWith(fontStyle: FontStyle.italic),
              mask: mask,
            ),
            'u' => inline(
              children,
              _decorated(style, TextDecoration.underline),
              mask: mask,
            ),
            's' => inline(
              children,
              _decorated(style, TextDecoration.lineThrough),
              mask: mask,
            ),
            'color' => inline(children, switch (_cssColor(value)) {
              final color? when !hidden => style.copyWith(color: color),
              _ => style,
            }, mask: mask),
            'size' => inline(
              children,
              style.copyWith(
                fontSize:
                    (double.tryParse(
                              RegExp(r'\d+').firstMatch(value)?[0] ?? '',
                            ) ??
                            style.fontSize ??
                            13)
                        .clamp(10, 32)
                        .toDouble(),
              ),
              mask: mask,
            ),
            'mask' => _spoiler(children, style),
            'url' => _link(
              value.isEmpty ? _stringChild(node)! : value,
              children,
              style,
              mask: mask,
            ),
            'user' => _link(
              'https://bgm.tv/user/${value.isEmpty ? _stringChild(node) : value}',
              [_Text('@${_stringChild(node) ?? value}')],
              style,
              mask: mask,
            ),
            'subject' => _link(
              'https://bgm.tv/subject/$value',
              children,
              style,
              mask: mask,
            ),
            'img' => [_image(_stringChild(node)!, hidden: hidden)],
            // Blocks inside inline markup read on in the line.
            _ => inline(children, style, mask: mask),
          });
      }
    }
    return spans;
  }

  static TextStyle _decorated(TextStyle style, TextDecoration decoration) =>
      style.copyWith(
        decoration: TextDecoration.combine([?style.decoration, decoration]),
      );

  static String? _stringChild(_Tag node) => switch (node.children) {
    [_Text(:final text)] => text,
    _ => null,
  };

  /// A spoiler is a dark bar in the text colour until the pointer rests on
  /// it or it is tapped, as Bangumi's `text_mask`.
  List<InlineSpan> _spoiler(List<_Node> children, TextStyle style) {
    final id = _mask++;
    final revealed = state._revealed.contains(id);
    final cover = scheme.onSurface;
    void reveal(bool value) => state._reveal(id, value);

    final tap = _recognizer(() => reveal(!state._revealed.contains(id)));
    return [
      for (final span in inline(
        children,
        style.copyWith(
          color: revealed ? scheme.surface : cover,
          backgroundColor: cover,
          decorationColor: revealed ? scheme.surface : cover,
        ),
        mask: id,
      ))
        switch (span) {
          TextSpan(:final text, :final style, recognizer: null) => TextSpan(
            text: text,
            style: style,
            recognizer: tap,
            mouseCursor: SystemMouseCursors.click,
            onEnter: (_) => reveal(true),
            onExit: (_) => reveal(false),
          ),
          WidgetSpan(:final child, :final alignment) => WidgetSpan(
            alignment: alignment,
            child: MouseRegion(
              onEnter: (_) => reveal(true),
              onExit: (_) => reveal(false),
              child: GestureDetector(
                onTap: () => reveal(!state._revealed.contains(id)),
                child: child,
              ),
            ),
          ),
          _ => span,
        },
    ];
  }

  List<InlineSpan> _link(
    String address,
    List<_Node> children,
    TextStyle style, {
    int? mask,
  }) {
    final uri = Uri.tryParse(address);
    void open() {
      if (uri != null) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    final hidden = mask != null && !state._revealed.contains(mask);
    final tap = _recognizer(open);
    return [
      for (final span in inline(
        children,
        hidden
            ? style
            : style.copyWith(
                color: scheme.primary,
                decorationColor: scheme.primary,
              ),
        mask: mask,
      ))
        switch (span) {
          // A link inside a spoiler opens only once the spoiler shows.
          TextSpan(:final text, :final style) when !hidden => TextSpan(
            text: text,
            style: style,
            recognizer: tap,
            mouseCursor: SystemMouseCursors.click,
          ),
          WidgetSpan(:final child, :final alignment) when !hidden => WidgetSpan(
            alignment: alignment,
            child: Tooltip(
              message: address,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(onTap: open, child: child),
              ),
            ),
          ),
          _ => span,
        },
    ];
  }

  InlineSpan _sticker(_Sticker sticker, {required bool hidden}) {
    final image = SizedBox(
      width: sticker.width,
      height: sticker.height,
      child: hidden
          ? ColoredBox(color: scheme.onSurface)
          : CachedImage(
              url: sticker.url,
              cacheWidth: sticker.width > 40
                  ? imageDecodeWidth(context, sticker.width)
                  : null,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Tooltip(
        message: sticker.name,
        waitDuration: const Duration(milliseconds: 600),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: image,
        ),
      ),
    );
  }

  /// A picture at most 360×240, opened full size on a click.
  InlineSpan _image(String address, {required bool hidden}) {
    const maxWidth = 360.0, maxHeight = 240.0;
    Widget frame(Widget child) =>
        ClipRRect(borderRadius: badgeBorderRadius, child: child);
    final placeholder = Container(
      width: 120,
      height: 80,
      color: scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
    );
    if (hidden) {
      return WidgetSpan(
        child: frame(
          Container(width: 120, height: 80, color: scheme.onSurface),
        ),
      );
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.bottom,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _viewImage(context, address),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: frame(
                CachedImage(
                  url: address,
                  cacheWidth: imageDecodeWidth(context, maxWidth),
                  fit: BoxFit.contain,
                  frameBuilder: (_, child, frame, synchronous) =>
                      frame == null && !synchronous ? placeholder : child,
                  errorBuilder: (_, _, _) =>
                      Tooltip(message: '图片加载失败：$address', child: placeholder),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _viewImage(BuildContext context, String address) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(address),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('在浏览器打开'),
                ),
                IconButton(
                  tooltip: '关闭图片',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Flexible(
              child: InteractiveViewer(
                child: CachedImage(
                  url: address,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Text('图片加载失败')),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// CSS colours Bangumi posts use: `#rgb`, `#rrggbb` and the common names.
Color? _cssColor(String value) {
  final text = value.trim().toLowerCase();
  final hex = RegExp(r'^#?([0-9a-f]{3}|[0-9a-f]{6})$').firstMatch(text);
  if (hex != null) {
    var digits = hex[1]!;
    if (digits.length == 3) digits = digits.split('').map((c) => c * 2).join();
    return Color(0xff000000 | int.parse(digits, radix: 16));
  }
  final named = _colorNames[text];
  return named == null ? null : Color(0xff000000 | named);
}

const _colorNames = {
  'black': 0x000000,
  'white': 0xffffff,
  'red': 0xff0000,
  'green': 0x008000,
  'blue': 0x0000ff,
  'yellow': 0xffff00,
  'orange': 0xffa500,
  'purple': 0x800080,
  'pink': 0xffc0cb,
  'hotpink': 0xff69b4,
  'deeppink': 0xff1493,
  'gray': 0x808080,
  'grey': 0x808080,
  'silver': 0xc0c0c0,
  'brown': 0xa52a2a,
  'cyan': 0x00ffff,
  'aqua': 0x00ffff,
  'magenta': 0xff00ff,
  'fuchsia': 0xff00ff,
  'navy': 0x000080,
  'teal': 0x008080,
  'olive': 0x808000,
  'maroon': 0x800000,
  'lime': 0x00ff00,
  'gold': 0xffd700,
  'skyblue': 0x87ceeb,
  'violet': 0xee82ee,
  'crimson': 0xdc143c,
  'indigo': 0x4b0082,
  'darkred': 0x8b0000,
  'darkblue': 0x00008b,
  'darkgreen': 0x006400,
  'darkorange': 0xff8c00,
  'orangered': 0xff4500,
  'tomato': 0xff6347,
  'coral': 0xff7f50,
  'salmon': 0xfa8072,
  'royalblue': 0x4169e1,
  'dodgerblue': 0x1e90ff,
  'steelblue': 0x4682b4,
  'seagreen': 0x2e8b57,
  'limegreen': 0x32cd32,
  'chocolate': 0xd2691e,
  'tan': 0xd2b48c,
};

sealed class _Node {
  const _Node();
}

class _Text extends _Node {
  const _Text(this.text);
  final String text;
}

/// `[code]`, whose content is never parsed.
class _Code extends _Node {
  const _Code(this.text);
  final String text;
}

class _Tag extends _Node {
  const _Tag(this.name, this.value, this.children);
  final String name;

  /// What follows `=` in the opening tag, or empty.
  final String value;
  final List<_Node> children;
}

class _Sticker extends _Node {
  const _Sticker(this.url, this.width, this.height, this.name);
  final String url;
  final double width, height;
  final String name;
}

class _Invalid implements Exception {
  const _Invalid();
}

/// A port of bangumi/frontend's BBCode parser: stickers in parentheses,
/// tags in brackets, and anything that does not parse kept as text.
class _Parser {
  _Parser(this.input);
  final String input;
  int pos = 0;
  int _depth = 0;

  static const _tags = {
    'b', 'i', 's', 'u', 'mask', 'color', 'size', 'url', 'img', //
    'left', 'right', 'center', 'indent', 'float', 'code', 'quote',
    'subject', 'user', 'align',
  };

  bool get _eof => pos >= input.length;
  bool _startsWith(String pattern) => input.startsWith(pattern, pos);

  List<_Node> parse() {
    final nodes = <_Node>[];
    while (!_eof && !(_depth > 0 && _startsWith('[/'))) {
      final start = pos;
      _Node node;
      try {
        node = switch (input[pos]) {
          '(' => _sticker(),
          '[' => _tag(),
          _ => _text(),
        };
      } on _Invalid {
        node = _Text(input.substring(start, math.min(pos, input.length)));
      }
      // Adjacent text merges, so spans and line breaks stay simple.
      if (node is _Text && nodes.lastOrNull is _Text) {
        nodes.last = _Text((nodes.last as _Text).text + node.text);
      } else {
        nodes.add(node);
      }
    }
    return nodes;
  }

  _Node _text() {
    final start = pos;
    while (!_eof && input[pos] != '(' && input[pos] != '[') {
      pos++;
    }
    return _Text(input.substring(start, pos));
  }

  _Node _sticker() {
    final rest = input.substring(pos);
    final match =
        RegExp(r'^\(bgm(\d+)\)').firstMatch(rest) ??
        RegExp(r'^\((musume|blake)_(\d{2,3})\)').firstMatch(rest);
    final sticker = match == null
        ? _kaomoji(rest)
        : match.groupCount == 1
        ? _numbered(int.parse(match[1]!))
        : _character(match[1]!, match[2]!);
    if (sticker == null) {
      pos++;
      throw const _Invalid();
    }
    pos += match?[0]!.length ?? sticker.name.length;
    return sticker;
  }

  static const _stickerHost = 'https://lain.bgm.tv';

  /// `(bgm01)`–`(bgm125)`, `(bgm200)`–`(bgm238)` and `(bgm500)`–`(bgm529)`.
  static _Sticker? _numbered(int n) {
    String pad(int value) => value.toString().padLeft(2, '0');
    final (path, size) = switch (n) {
      >= 1 && <= 23 => (
        '/img/smiles/bgm/${pad(n)}.${n == 11 || n == 23 ? 'gif' : 'png'}',
        20.0,
      ),
      >= 24 && <= 125 => ('/img/smiles/tv/${pad(n - 23)}.gif', 21.0),
      >= 200 && <= 238 => ('/img/smiles/tv_vs/bgm_$n.png', 21.0),
      >= 500 && <= 529 => (
        '/img/smiles/tv_500/bgm_$n.${_tv500Gifs.contains(n) ? 'gif' : 'png'}',
        21.0,
      ),
      _ => (null, 0.0),
    };
    if (path == null) return null;
    return _Sticker('$_stickerHost$path', size, size, '(bgm$n)');
  }

  static const _tv500Gifs = {
    500, 501, 505, 515, 516, 517, 518, 519, 521, 522, 523, //
  };

  /// Bangumi 娘 and Blake 娘, 1–118; 97 and 98 are Blake's alone. Shown at
  /// 55 px like Bangumi.
  static _Sticker? _character(String set, String digits) {
    final n = int.parse(digits);
    final canonical = n < 100 ? n.toString().padLeft(2, '0') : '$n';
    if (digits != canonical || n < 1 || n > 118) return null;
    if (set == 'musume' && (n == 97 || n == 98)) return null;
    return _Sticker(
      '$_stickerHost/img/smiles/$set/${set}_$canonical.gif',
      55,
      55,
      '(${set}_$canonical)',
    );
  }

  static const _kaomojis = [
    ('(=A=)', 23, 19),
    ('(=w=)', 23, 11),
    ('(-w=)', 23, 9),
    ('(S_S)', 29, 16),
    ('(=v=)', 25, 16),
    ('(@_@)', 27, 14),
    ('(=W=)', 27, 19),
    ('(TAT)', 33, 17),
    ('(T_T)', 23, 16),
    ("(='=)", 26, 14),
    ('(=3=)', 25, 15),
    ("(= =')", 24, 27),
    ('(=///=)', 21, 10),
    ('(=.,=)', 20, 11),
    ('(:P)', 28, 17),
    ('(LOL)', 27, 21),
  ];

  static _Sticker? _kaomoji(String rest) {
    for (final (index, (code, width, height)) in _kaomojis.indexed) {
      if (rest.startsWith(code)) {
        return _Sticker(
          '$_stickerHost/img/smiles/${index + 1}.gif',
          width.toDouble(),
          height.toDouble(),
          code,
        );
      }
    }
    return null;
  }

  String _tagName() {
    final start = pos;
    while (!_eof && RegExp(r'[a-zA-Z]').hasMatch(input[pos])) {
      pos++;
    }
    if (pos == start) throw const _Invalid();
    return input.substring(start, pos).toLowerCase();
  }

  void _expect(String text) {
    if (!_startsWith(text)) {
      pos = math.min(pos + 1, input.length);
      throw const _Invalid();
    }
    pos += text.length;
  }

  _Node _tag() {
    final start = pos;
    pos++;
    final name = _tagName();
    if (_eof) throw const _Invalid();
    var c = input[pos++];
    if (c != ']' && c != '=') throw const _Invalid();
    var value = '';
    if (c == '=') {
      final end = input.indexOf(']', pos);
      if (end < 0) {
        pos = input.length;
        throw const _Invalid();
      }
      value = input.substring(pos, end);
      pos = end + 1;
    }
    // An unknown tag is text, and its closing tag pairs with nothing.
    if (!_tags.contains(name)) return _Text(input.substring(start, pos));
    if (name == 'code') {
      final end = input.indexOf('[/code]', pos);
      if (end < 0) throw const _Invalid();
      final text = input.substring(pos, end);
      pos = end + '[/code]'.length;
      return _Code(text);
    }
    _depth++;
    final children = parse();
    _depth--;
    _expect('[/');
    if (_tagName() != name) throw const _Invalid();
    _expect(']');
    final node = _Tag(name, value, children);
    if (!_valid(node)) throw const _Invalid();
    return node;
  }

  static bool _web(String? address) {
    final uri = Uri.tryParse(address?.trim() ?? '');
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static bool _valid(_Tag node) {
    final child = switch (node.children) {
      [_Text(:final text)] => text,
      _ => null,
    };
    return switch (node.name) {
      'color' => node.value.isNotEmpty,
      'size' => RegExp(r'\d').hasMatch(node.value),
      'url' => _web(node.value.isEmpty ? child : node.value),
      'img' => _web(child),
      'subject' => RegExp(r'^[1-9]\d*$').hasMatch(node.value),
      'user' => (node.value.isEmpty ? child ?? '' : node.value).isNotEmpty,
      'align' => const ['left', 'right', 'center'].contains(node.value),
      _ => true,
    };
  }
}
