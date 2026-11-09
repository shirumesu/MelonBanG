import 'package:flutter/material.dart';

/// Confirms deleting cached files: [message] says which. The files cannot
/// be restored, so the confirming button is red.
class RemoveDownloadDialog extends StatelessWidget {
  const RemoveDownloadDialog({
    super.key,
    required this.message,
    this.title = '移除缓存？',
    this.action = '移除',
  });
  final String title, message, action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(width: 420, child: Text(message)),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    );
  }
}
