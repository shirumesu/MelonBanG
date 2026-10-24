import 'package:flutter/material.dart';

/// Confirms deleting cached files: [message] says which.
class RemoveDownloadDialog extends StatelessWidget {
  const RemoveDownloadDialog({
    super.key,
    required this.message,
    this.title = '移除缓存？',
  });
  final String title, message;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('移除'),
      ),
    ],
  );
}
