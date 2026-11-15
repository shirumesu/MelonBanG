import 'package:flutter/material.dart';

import '../../features/sync/settings_sync.dart';
import '../core/motion.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';

/// Asks which side each conflicting setting keeps, then lets sync carry on.
/// Closing it with 稍后 leaves the choice waiting in Settings › 账户与同步.
Future<void> showSyncConflicts(BuildContext context, SettingsSync sync) async {
  if (sync.conflicts.isEmpty) return;
  final useRemote = await showMelonDialog<Set<String>>(
    context: context,
    builder: (context) => _ConflictDialog(sync: sync),
  );
  if (useRemote != null) await sync.resolve(useRemote);
}

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({required this.sync});
  final SettingsSync sync;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  /// Conflicts that take the cloud's value; the rest keep this device's.
  final remote = <String>{};

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    final conflicts = sync.conflicts;
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('设置同步冲突'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('选择每项要保留的版本，其余设置已合并', style: theme.textTheme.bodySmall),
            const SizedBox(height: Gap.lg),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final (index, conflict) in conflicts.indexed) ...[
                      if (index > 0) const Divider(height: Gap.xl),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sync.labelOf(conflict),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: Gap.lg),
                          SizedBox(
                            width: 300,
                            child: MelonSegmentedControl<bool>(
                              semanticLabel: sync.labelOf(conflict),
                              options: {
                                false:
                                    '本机：${sync.describe(conflict, conflict.local)}',
                                true:
                                    '云端：${sync.describe(conflict, conflict.remote)}',
                              },
                              value: remote.contains(conflict.id),
                              onChanged: (cloud) => setState(
                                () => cloud
                                    ? remote.add(conflict.id)
                                    : remote.remove(conflict.id),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('稍后'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, {
            for (final conflict in conflicts) conflict.id,
          }),
          child: const Text('全部用云端'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, {...remote}),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
