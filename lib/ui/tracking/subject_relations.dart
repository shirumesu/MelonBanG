import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/catalog.dart';
import '../../domain/community.dart';
import '../core/action_feedback.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/subject_cover.dart';
import '../core/theme.dart';

/// Related subjects grouped by relation, as a compact list.
class SubjectRelations extends StatefulWidget {
  const SubjectRelations({
    super.key,
    required this.client,
    required this.subjectId,
    required this.onOpenSubject,
  });
  final SubjectCommunitySource client;
  final int subjectId;
  final ValueChanged<Subject> onOpenSubject;

  @override
  State<SubjectRelations> createState() => _SubjectRelationsState();
}

class _SubjectRelationsState extends State<SubjectRelations> {
  static const _groups = ['前传', '续集', '番外', '总集篇', '其他'];
  final _feedback = ActionFeedback();
  List<Subject> _relations = [];
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) => _feedback.run(() async {
    final values = await widget.client.relations(
      widget.subjectId,
      refresh: refresh,
    );
    if (mounted) setState(() => _relations = values);
    return null;
  });

  String _group(Subject row) {
    final relation = '${row.relation}';
    if (relation.contains('前传')) return '前传';
    if (relation.contains('续集')) return '续集';
    if (relation.contains('番外') || relation.contains('外传')) return '番外';
    if (relation.contains('总集')) return '总集篇';
    return '其他';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ordered = [
      for (final group in _groups)
        ..._relations.where((row) => _group(row) == group),
    ];
    final shown = _expanded ? ordered : ordered.take(6).toList();
    return MelonPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('关联作品', style: text.titleSmall),
          const SizedBox(height: Gap.xs),
          FeedbackIssue(
            feedback: _feedback,
            onRetry: () => unawaited(_load(refresh: true)),
          ),
          ListenableBuilder(
            listenable: _feedback,
            builder: (context, _) =>
                _relations.isNotEmpty || _feedback.issue != null
                ? const SizedBox.shrink()
                : _feedback.busy
                ? const _RelationsSkeleton()
                : const EmptyState.compact(text: '暂无关联作品', center: false),
          ),
          for (final (index, row) in shown.indexed) ...[
            if (index == 0 || _group(shown[index - 1]) != _group(row))
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm, bottom: 2),
                child: Text(_group(row), style: text.bodySmall),
              ),
            InkWell(
              borderRadius: controlBorderRadius,
              onTap: () => widget.onOpenSubject(row),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 54,
                      child: CoverFrame(
                        radius: badgeBorderRadius,
                        child: SubjectCover(
                          url: row.coverUrl,
                          title: row.title,
                          id: row.id,
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: FontSize.body,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              if (row.relation != _group(row)) ?row.relation,
                              ?row.platform,
                              ?row.season?.year,
                            ].join('  '),
                            style: text.bodySmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (ordered.length > 6)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起' : '全部 ${ordered.length} 部'),
            ),
        ],
      ),
    );
  }
}

/// A group of rows in grey while the relations load, after [busyDelay].
class _RelationsSkeleton extends StatelessWidget {
  const _RelationsSkeleton();

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return DelayedBusy(
      busy: true,
      builder: (context, shown) => SkeletonGroup(
        label: '正在加载关联作品',
        shown: shown,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm, bottom: 2),
              child: SkeletonLine(style: small, width: 28),
            ),
            for (final share in const [.8, .55, .7])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Row(
                  children: [
                    const SkeletonBlock(
                      width: 40,
                      height: 54,
                      radius: badgeBorderRadius,
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonLine(
                            style: const TextStyle(fontSize: FontSize.body),
                            widthFactor: share,
                          ),
                          SkeletonLine(style: small, width: 64),
                        ],
                      ),
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
