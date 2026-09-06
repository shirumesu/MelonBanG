import 'package:flutter/material.dart';

import '../../data/json.dart';
import '../core/page_widgets.dart';
import '../core/subject_posters.dart';
import 'collection_labels.dart';

class TrackingPage extends StatelessWidget {
  const TrackingPage({
    super.key,
    required this.collection,
    required this.collectionFilter,
    required this.sync,
    required this.onFilterChanged,
    required this.onSync,
    required this.onOpenSubject,
  });
  final List<Json> collection;
  final String collectionFilter;
  final Json sync;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onSync;
  final ValueChanged<Json> onOpenSubject;
  @override
  Widget build(BuildContext context) => PageScroll(
    children: [
      Wrap(
        spacing: 8,
        children: collectionLabels.entries
            .map(
              (entry) => ChoiceChip(
                label: Text(
                  '${entry.value} ${collection.where((item) => item['status'] == entry.key).length}',
                ),
                selected: collectionFilter == entry.key,
                onSelected: (_) => onFilterChanged(entry.key),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 18),
      if (number(sync['pendingMutationCount']) > 0)
        Text('${sync['pendingMutationCount']} 项修改等待同步'),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onSync,
          icon: const Icon(Icons.sync),
          label: const Text('同步收藏'),
        ),
      ),
      SubjectPosters(
        onOpen: onOpenSubject,
        items: collection
            .where((item) => item['status'] == collectionFilter)
            .toList(),
      ),
    ],
  );
}
