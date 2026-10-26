import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../core/cached_image.dart';
import '../core/external_link.dart';
import '../core/motion.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'subject_people.dart';

/// The character or person [credit] over the page: profile, voice parts and
/// anime, each opening here; Bangumi keeps the full page.
Future<void> showCreditProfile(
  BuildContext context, {
  required Catalog catalog,
  required Credit credit,
  required bool character,
  required ValueChanged<Subject> onOpenSubject,
}) => showMelonDialog<void>(
  context: context,
  builder: (context) => _CreditProfileDialog(
    catalog: catalog,
    credit: credit,
    character: character,
    onOpenSubject: onOpenSubject,
  ),
);

class _CreditProfileDialog extends StatefulWidget {
  const _CreditProfileDialog({
    required this.catalog,
    required this.credit,
    required this.character,
    required this.onOpenSubject,
  });
  final Catalog catalog;
  final Credit credit;
  final bool character;
  final ValueChanged<Subject> onOpenSubject;

  @override
  State<_CreditProfileDialog> createState() => _CreditProfileDialogState();
}

class _CreditProfileDialogState extends State<_CreditProfileDialog> {
  late Future<CreditProfile> profile = _load();

  Future<CreditProfile> _load() =>
      widget.catalog.credit(widget.credit.id, character: widget.character);

  /// Leaves every dialog for [subject]'s page.
  void open(Subject subject) {
    Navigator.of(context).popUntil((route) => route is! PopupRoute);
    widget.onOpenSubject(subject);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: FutureBuilder(
          future: profile,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return CustomScrollView(
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
                      child: PartFailure(
                        message: '资料加载失败',
                        onRetry: () => setState(() => profile = _load()),
                      ),
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
                        child: SelectableText(
                          summary.trim(),
                          style: text.bodyMedium?.copyWith(height: 1.6),
                        ),
                      ),
                    ),
                  if (data.parts.isNotEmpty) ...[
                    _heading(
                      context,
                      widget.character ? '配音' : '配音角色',
                      data.parts.length,
                    ),
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
                  _heading(
                    context,
                    widget.character ? '出场动画' : '参与动画',
                    data.works.length,
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    sliver: data.works.isEmpty
                        ? SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                'Bangumi 上没有记录',
                                style: text.bodySmall,
                              ),
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
        ),
      ),
    );
  }

  Widget _header(BuildContext context, CreditProfile? data) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final credit = widget.credit;
    final name = data?.name ?? credit.name;
    final title = displayTitle([data?.nameCn, credit.nameCn, name]);
    final url = data?.imageUrl ?? credit.imageUrl;
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
              SelectableText(title, style: text.titleLarge),
              if (name != title) SelectableText(name, style: text.bodySmall),
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
            'https://bgm.tv/${widget.character ? 'character' : 'person'}/${credit.id}',
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
  /// their own page over this one.
  Widget _part(BuildContext context, Credit part) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final url = part.imageUrl;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: controlBorderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: part.id <= 0
            ? null
            : () => showCreditProfile(
                context,
                catalog: widget.catalog,
                credit: part,
                character: !widget.character,
                onOpenSubject: widget.onOpenSubject,
              ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: SizedBox.square(
                  dimension: 28,
                  child: url == null
                      ? ColoredBox(color: scheme.surfaceContainerHigh)
                      : CachedImage(
                          url: url,
                          cacheWidth: imageDecodeWidth(context, 28),
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: scheme.surfaceContainerHigh),
                        ),
                ),
              ),
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
      onTap: () => open(subject),
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
