import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/catalog.dart';
import '../core/bbcode.dart';
import '../core/cached_image.dart';
import '../core/external_link.dart';
import '../core/motion.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'subject_people.dart';

/// The character or person [credit] over the page: profile, voice parts and
/// anime. A character or person opened from it, by a voice part or a link in
/// the profile, takes its place in the same dialog, and the pages passed
/// through fold into spines on the left to go back to.
Future<void> showCreditProfile(
  BuildContext context, {
  required Catalog catalog,
  required Credit credit,
  required bool character,
  required ValueChanged<Subject> onOpenSubject,
}) => showMelonDialog<void>(
  context: context,
  builder: (context) => _CreditBrowser(
    catalog: catalog,
    first: _Page(credit, character: character),
    onOpenSubject: onOpenSubject,
  ),
);

/// One character or person in the dialog's path.
class _Page {
  _Page(this.credit, {required this.character});
  final Credit credit;
  final bool character;
  late Future<CreditProfile> profile;

  /// [profile] once loaded.
  CreditProfile? data;

  String get name => data?.name ?? credit.name;
  String get title => displayTitle([data?.nameCn, credit.nameCn, name]);
  String? get imageUrl => data?.imageUrl ?? credit.imageUrl;
}

class _CreditBrowser extends StatefulWidget {
  const _CreditBrowser({
    required this.catalog,
    required this.first,
    required this.onOpenSubject,
  });
  final Catalog catalog;
  final _Page first;
  final ValueChanged<Subject> onOpenSubject;

  @override
  State<_CreditBrowser> createState() => _CreditBrowserState();
}

class _CreditBrowserState extends State<_CreditBrowser> {
  /// Spines shown at most; past that the oldest pages share the first one.
  static const _spineSlots = 4;
  static const _spineWidth = 44.0;
  static const _bangumiHosts = {'bgm.tv', 'bangumi.tv', 'chii.in'};
  static final _creditPath = RegExp(r'^/(character|person)/(\d+)$');

  /// The path from the first page to the one shown.
  late final pages = [_load(widget.first)];

  /// Whether the last move went deeper: the new page comes in from the
  /// right, and from the left going back.
  var forward = true;

  _Page _load(_Page page) {
    page.profile = widget.catalog.credit(
      page.credit.id,
      character: page.character,
    );
    unawaited(
      page.profile.then((data) {
        if (mounted) setState(() => page.data = data);
      }, onError: (Object _) {}),
    );
    return page;
  }

  /// Shows [credit] next; one already on the path is gone back to, so
  /// going round in circles does not grow it.
  void openCredit(Credit credit, {required bool character}) {
    final index = pages.indexWhere(
      (page) => page.credit.id == credit.id && page.character == character,
    );
    if (index >= 0) return goBack(index);
    setState(() {
      forward = true;
      pages.add(_load(_Page(credit, character: character)));
    });
  }

  /// Back to the page at [index], by default the one before; from the
  /// first page this closes the dialog.
  void goBack([int? index]) {
    final target = index ?? pages.length - 2;
    if (target < 0) return Navigator.pop(context);
    if (target == pages.length - 1) return;
    setState(() {
      forward = false;
      pages.removeRange(target + 1, pages.length);
    });
  }

  /// Leaves every dialog for [subject]'s page.
  void openSubject(Subject subject) {
    Navigator.of(context).popUntil((route) => route is! PopupRoute);
    widget.onOpenSubject(subject);
  }

  /// A Bangumi character or person link opens here.
  VoidCallback? inAppLink(Uri address, String text) {
    final match = _creditPath.firstMatch(address.path);
    if (!_bangumiHosts.contains(address.host) || match == null) return null;
    return () => openCredit(
      Credit(id: int.parse(match[2]!), name: text.trim()),
      character: match[1] == 'character',
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = pages.last;
    final passed = pages.length - 1;
    final folded = passed > _spineSlots ? passed - (_spineSlots - 1) : 0;
    final spines = [
      if (folded > 0) _foldedSpine(context, folded),
      for (var index = folded; index < passed; index++)
        _spine(context, index, nearest: index == passed - 1),
    ];
    final left = spines.length * _spineWidth;
    final duration = motionDuration(context, 240);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): goBack,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): goBack,
      },
      child: Focus(
        autofocus: true,
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons & kBackMouseButton != 0) goBack();
          },
          child: Dialog(
            clipBehavior: Clip.antiAlias,
            child: AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 640 + left,
                  maxHeight: 720,
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: left),
                      child: AnimatedSwitcher(
                        duration: duration,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (shown, leaving) => Stack(
                          alignment: Alignment.topLeft,
                          children: [...leaving, ?shown],
                        ),
                        transitionBuilder: (child, animation) {
                          final incoming = child.key == ObjectKey(current);
                          final side = incoming == forward ? .06 : -.06;
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: animation.drive(
                                Tween(begin: Offset(side, 0), end: Offset.zero),
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: _ProfileView(
                          key: ObjectKey(current),
                          page: current,
                          onOpenCredit: openCredit,
                          onOpenSubject: openSubject,
                          inAppLink: inAppLink,
                          onRetry: () => setState(() => _load(current)),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Row(children: spines),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A page passed through, standing on its edge: its portrait and name
  /// set vertically, one character a line, and a click goes back to it. The [nearest] one is the
  /// way back.
  Widget _spine(BuildContext context, int index, {required bool nearest}) {
    final page = pages[index];
    final scheme = Theme.of(context).colorScheme;
    return _spineFrame(
      context,
      tooltip: '返回${page.title}',
      onTap: () => goBack(index),
      children: [
        SizedBox(
          height: 24,
          child: nearest
              ? Icon(
                  Icons.chevron_left_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                )
              : null,
        ),
        _portrait(context, page.imageUrl, 28),
        const SizedBox(height: Gap.sm),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const size = 12.0, height = 1.25;
              final lines = (constraints.maxHeight / (size * height)).floor();
              final glyphs = page.title.trim().characters.toList();
              final shown = glyphs.length <= lines
                  ? glyphs
                  : [...glyphs.take((lines - 1).clamp(0, lines)), '︙'];
              return Text(
                shown.join('\n'),
                maxLines: lines,
                textAlign: TextAlign.center,
                strutStyle: const StrutStyle(
                  fontSize: size,
                  height: height,
                  forceStrutHeight: true,
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: size,
                  height: height,
                  color: nearest ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The [count] oldest pages as one spine, listed on a click.
  Widget _foldedSpine(BuildContext context, int count) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      menuChildren: [
        for (var index = 0; index < count; index++)
          MenuItemButton(
            leadingIcon: _portrait(context, pages[index].imageUrl, 24),
            onPressed: () => goBack(index),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                pages[index].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      builder: (context, menu, _) => _spineFrame(
        context,
        tooltip: '更早的 $count 层',
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        children: [
          const SizedBox(height: 24),
          Icon(Icons.layers_outlined, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            '+$count',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _spineFrame(
    BuildContext context, {
    required String tooltip,
    required VoidCallback onTap,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: scheme.surfaceContainerLow,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: _spineWidth,
            padding: const EdgeInsets.only(bottom: Gap.lg),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Column(children: children),
          ),
        ),
      ),
    );
  }
}

Widget _portrait(BuildContext context, String? url, double size) {
  final scheme = Theme.of(context).colorScheme;
  return ClipOval(
    child: SizedBox.square(
      dimension: size,
      child: url == null
          ? ColoredBox(color: scheme.surfaceContainerHigh)
          : CachedImage(
              url: url,
              cacheWidth: imageDecodeWidth(context, size),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, _, _) =>
                  ColoredBox(color: scheme.surfaceContainerHigh),
            ),
    ),
  );
}

/// One character's or person's profile, voice parts and anime.
class _ProfileView extends StatelessWidget {
  const _ProfileView({
    super.key,
    required this.page,
    required this.onOpenCredit,
    required this.onOpenSubject,
    required this.inAppLink,
    required this.onRetry,
  });
  final _Page page;
  final void Function(Credit credit, {required bool character}) onOpenCredit;
  final ValueChanged<Subject> onOpenSubject;
  final VoidCallback? Function(Uri address, String text) inAppLink;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final character = page.character;
    return FutureBuilder(
      future: page.profile,
      // A page gone back to shows at once.
      initialData: page.data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return CustomScrollView(
          // Going back finds the page where it was left.
          key: PageStorageKey(page),
          shrinkWrap: true,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
              sliver: SliverToBoxAdapter(child: _header(context, data)),
            ),
            if (snapshot.hasError)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                sliver: SliverToBoxAdapter(
                  child: PartFailure(message: '资料加载失败', onRetry: onRetry),
                ),
              )
            else if (data == null)
              const SliverPadding(
                padding: EdgeInsets.all(32),
                sliver: SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else ...[
              if (data.summary case final summary?)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  sliver: SliverToBoxAdapter(
                    child: BBCode(
                      summary,
                      style: text.bodyMedium?.copyWith(height: 1.6),
                      inAppLink: inAppLink,
                    ),
                  ),
                ),
              if (data.parts.isNotEmpty) ...[
                _heading(context, character ? '配音' : '配音角色', data.parts.length),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: Wrap(
                      spacing: Gap.sm,
                      runSpacing: Gap.sm,
                      children: [
                        for (final part in data.parts) _part(context, part),
                      ],
                    ),
                  ),
                ),
              ],
              _heading(context, character ? '出场动画' : '参与动画', data.works.length),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                sliver: data.works.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Bangumi 上没有记录', style: text.bodySmall),
                        ),
                      )
                    : SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 300,
                              mainAxisExtent: 68,
                            ),
                        itemCount: data.works.length,
                        itemBuilder: (context, index) =>
                            _work(context, data.works[index]),
                      ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, CreditProfile? data) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final url = page.imageUrl;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: controlBorderRadius,
          child: SizedBox(
            width: 96,
            height: 128,
            child: url == null
                ? ColoredBox(color: scheme.surfaceContainerHigh)
                : CachedImage(
                    url: url,
                    cacheWidth: imageDecodeWidth(context, 96),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, _, _) =>
                        ColoredBox(color: scheme.surfaceContainerHigh),
                  ),
          ),
        ),
        const SizedBox(width: Gap.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              SelectableText(page.title, style: text.titleLarge),
              if (page.name != page.title)
                SelectableText(page.name, style: text.bodySmall),
              const SizedBox(height: Gap.sm),
              for (final fact in [...?data?.facts.take(6)])
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          fact.key,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          fact.value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: '在 Bangumi 打开',
          onPressed: () => openExternal(
            context,
            'https://bgm.tv/${page.character ? 'character' : 'person'}/${page.credit.id}',
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _heading(BuildContext context, String label, int count) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, Gap.sm),
        sliver: SliverToBoxAdapter(
          child: Text(
            '$label  $count',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      );

  /// An actor of the character, or a character the person voices; opens
  /// their own page in this dialog.
  Widget _part(BuildContext context, Credit part) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: controlBorderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: part.id <= 0
            ? null
            : () => onOpenCredit(part, character: !page.character),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _portrait(context, part.imageUrl, 28),
              const SizedBox(width: Gap.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      part.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (part.role case final role?)
                      Text(
                        role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small?.copyWith(fontSize: 11),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _work(BuildContext context, Subject subject) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final url = subject.coverUrl;
    return InkWell(
      borderRadius: controlBorderRadius,
      onTap: () => onOpenSubject(subject),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: badgeBorderRadius,
              child: SizedBox(
                width: 40,
                height: 56,
                child: url == null
                    ? ColoredBox(color: scheme.surfaceContainerHigh)
                    : CachedImage(
                        url: url,
                        cacheWidth: imageDecodeWidth(context, 40),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            ColoredBox(color: scheme.surfaceContainerHigh),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (subject.relation case final role? when role.isNotEmpty)
                    Text(
                      role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small?.copyWith(fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
