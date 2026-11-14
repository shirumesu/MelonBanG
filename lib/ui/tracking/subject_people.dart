import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../core/cached_image.dart';
import '../core/external_link.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import '../core/theme.dart';
import 'credit_profile.dart';

/// A subject's characters with their voice actors, or its staff with one
/// row per person holding all their positions; the first few show here and
/// the rest in a dialog. A person opens their own page in the app.
class SubjectPeoplePanel extends StatelessWidget {
  const SubjectPeoplePanel({
    super.key,
    required this.subject,
    required this.characters,
    required this.loading,
    required this.onRetry,
    required this.catalog,
    required this.onOpenSubject,
  });
  final Subject subject;
  final Catalog catalog;
  final ValueChanged<Subject> onOpenSubject;

  /// Characters, else staff.
  final bool characters;

  /// Still loading; with no people and not loading, the load failed.
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final people = _people(subject, characters);
    final heading = characters ? '角色与配音' : '制作团队';
    final limit = characters ? 8 : 12;
    return MelonPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  heading,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (people.length > limit)
                TextButton(
                  onPressed: () => _allPeople(context, heading, people),
                  child: Text('全部 ${people.length} 位'),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          if (people.isEmpty && !loading)
            PartFailure(message: '$heading加载失败', onRetry: onRetry)
          else if (people.isEmpty)
            _PeopleSkeleton(characters: characters)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    (constraints.maxWidth / (characters ? 210 : 230))
                        .floor()
                        .clamp(1, 4);
                final gap = characters ? Gap.md : Gap.xl;
                final width =
                    (constraints.maxWidth - (columns - 1) * gap) / columns -
                    .01;
                return Wrap(
                  spacing: gap,
                  runSpacing: characters ? Gap.md : 0,
                  children: [
                    for (final person in people.take(limit))
                      SizedBox(
                        width: width,
                        child: characters
                            ? _credit(context, person, character: true)
                            : _staffRow(context, person),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  void _allPeople(BuildContext context, String heading, List<Credit> people) =>
      showMelonDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 660,
            height: 600,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$heading（${people.length}）',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭人物列表',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: people.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) => characters
                          ? _credit(context, people[index], character: true)
                          : _staffRow(context, people[index]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  static List<Credit> _people(Subject item, bool characters) {
    if (characters) {
      return [
        ...item.characters.where((p) => p.role == '主角'),
        ...item.characters.where((p) => p.role != '主角'),
      ];
    }
    const roles = ['原作', '导演', '系列构成', '人物设定', '音乐', '动画制作', '总作画监督', '脚本'];
    int priority(String role) =>
        roles.contains(role) ? roles.indexOf(role) : roles.length;
    // One row per person, listing every position they hold.
    final positions = <String, List<String>>{};
    final people = <String, Credit>{};
    String keyOf(Credit person) =>
        person.id > 0 ? '${person.id}' : person.title;
    for (final person in item.staff) {
      final key = keyOf(person);
      final role = person.role ?? '';
      final held = positions.putIfAbsent(key, () => []);
      if (role.isNotEmpty && !held.contains(role)) held.add(role);
      final old = people[key];
      people[key] = old == null
          ? person
          : old.withRole(old.role, imageUrl: old.imageUrl ?? person.imageUrl);
    }
    final result = [
      for (final MapEntry(:key, value: person) in people.entries)
        person.withRole(
          (positions[key]!..sort((a, b) => priority(a).compareTo(priority(b))))
              .join('、'),
        ),
    ];
    int rank(Credit person) =>
        priority(positions[keyOf(person)]!.firstOrNull ?? '');
    result.sort((a, b) => rank(a).compareTo(rank(b)));
    return result;
  }

  /// [person]'s page; one Bangumi gives no id for is only on the subject's
  /// list there.
  void _open(BuildContext context, Credit person, {required bool character}) =>
      person.id > 0
      ? showCreditProfile(
          context,
          catalog: catalog,
          credit: person,
          character: character,
          onOpenSubject: onOpenSubject,
        )
      : openExternal(
          context,
          'https://bgm.tv/subject/${subject.id}/${character ? 'characters' : 'persons'}',
        );

  Widget _avatar(
    BuildContext context,
    Credit person, {
    bool character = false,
    double size = 42,
  }) {
    final url = person.imageUrl;
    final width = character ? 44.0 : size, height = character ? 60.0 : size;
    Widget placeholder(String label) => Tooltip(
      message: label,
      child: character
          ? MouseRegion(
              cursor: SystemMouseCursors.basic,
              child: GestureDetector(
                // Consume the tap instead of opening the surrounding card.
                onTap: () {},
                excludeFromSemantics: true,
                child: ArtPlaceholder(label: label),
              ),
            )
          : ArtPlaceholder(label: label),
    );
    Widget preview(Widget image) {
      if (!character || url == null) return image;
      return Tooltip(
        message: '查看${person.title}完整立绘',
        child: InkWell(
          borderRadius: badgeBorderRadius,
          onTap: () => showMelonDialog<void>(
            context: context,
            builder: (context) => Dialog(
              child: SizedBox(
                width: 520,
                height: 620,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              person.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭图片',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: InteractiveViewer(
                          child: CachedImage(
                            url: url,
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
          ),
          child: image,
        ),
      );
    }

    return Semantics(
      label: '${person.title}${character ? '角色头像' : '人物头像'}',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(character ? 8 : size / 2),
        child: SizedBox(
          width: width,
          height: height,
          child: url == null
              ? placeholder('暂无头像')
              : CachedImage(
                  url: url,
                  cacheWidth: imageDecodeWidth(context, width),
                  // Filled without distortion; tall portraits keep the face.
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  frameBuilder: (_, child, frame, synchronous) => ImageFadeIn(
                    frame: frame,
                    synchronous: synchronous,
                    placeholder: placeholder('正在加载头像'),
                    child: preview(child),
                  ),
                  errorBuilder: (_, _, _) => placeholder('头像加载失败'),
                ),
        ),
      ),
    );
  }

  Widget _credit(
    BuildContext context,
    Credit person, {
    required bool character,
  }) {
    final actors = person.actors;
    final role = person.role ?? '';
    final small = Theme.of(context).textTheme.bodySmall;
    final actorName = actors.map((actor) => actor.title).join('、');
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: controlBorderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, person, character: character),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(context, person, character: character),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      role.isEmpty ? '角色' : role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                    if (actorName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _avatar(context, actors.first, size: 18),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              actorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: small,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _staffRow(BuildContext context, Credit person) {
    final role = person.role ?? '';
    return InkWell(
      borderRadius: badgeBorderRadius,
      onTap: () => _open(context, person, character: false),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                role.isEmpty ? '制作人员' : role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                person.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The panel's people in grey while they load, once the wait has lasted
/// [busyDelay], in its columns: two rows of character cards (portrait,
/// name, role, voice actor), or three of staff rows (position, name).
class _PeopleSkeleton extends StatelessWidget {
  const _PeopleSkeleton({required this.characters});
  final bool characters;

  @override
  Widget build(BuildContext context) => DelayedBusy(
    busy: true,
    builder: (context, shown) => !shown
        ? const SizedBox.shrink()
        : Semantics(
            label: characters ? '正在加载角色' : '正在加载制作团队',
            child: ExcludeSemantics(
              child: MotionAppear(
                offset: 0,
                milliseconds: 200,
                child: MotionPulse(child: LayoutBuilder(builder: _people)),
              ),
            ),
          ),
  );

  Widget _people(BuildContext context, BoxConstraints constraints) {
    final text = Theme.of(context).textTheme;
    final columns = (constraints.maxWidth / (characters ? 210 : 230))
        .floor()
        .clamp(1, 4);
    final gap = characters ? Gap.md : Gap.xl;
    final width = (constraints.maxWidth - (columns - 1) * gap) / columns - .01;
    const shares = [.62, .48, .7, .55];
    return Wrap(
      spacing: gap,
      runSpacing: characters ? Gap.md : 0,
      children: [
        for (var i = 0; i < columns * (characters ? 2 : 3); i++)
          SizedBox(
            width: width,
            child: characters
                ? _card(context, text, shares[i % 4])
                : _staff(context, text, shares[(i + 1) % 4]),
          ),
      ],
    );
  }

  Widget _card(BuildContext context, TextTheme text, double share) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: controlBorderRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBlock(
                width: 44,
                height: 60,
                radius: BorderRadius.all(Radius.circular(8)),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(style: text.titleSmall, widthFactor: share),
                    SkeletonLine(style: text.bodySmall, width: 28),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const SkeletonBlock(
                          width: 18,
                          height: 18,
                          radius: BorderRadius.all(Radius.circular(9)),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: SkeletonLine(
                            style: text.bodySmall,
                            widthFactor: share * .8,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _staff(BuildContext context, TextTheme text, double share) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: SkeletonLine(style: text.bodySmall, width: 40),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: SkeletonLine(
                style: const TextStyle(fontSize: 13),
                widthFactor: share,
              ),
            ),
          ],
        ),
      );
}

/// A part of a page that failed to load, with retrying it.
class PartFailure extends StatelessWidget {
  const PartFailure({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(message, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(width: Gap.sm),
      TextButton(onPressed: onRetry, child: const Text('重试')),
    ],
  );
}
