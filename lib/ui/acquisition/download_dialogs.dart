import 'package:flutter/material.dart';

class RemoveDownloadDialog extends StatelessWidget {
  const RemoveDownloadDialog({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('移除缓存？'),
    content: Text('将移除下载任务及缓存文件：$title'),
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

class AddMagnetDialog extends StatefulWidget {
  const AddMagnetDialog({super.key});

  @override
  State<AddMagnetDialog> createState() => _AddMagnetDialogState();
}

class _AddMagnetDialogState extends State<AddMagnetDialog> {
  String draft = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加磁力链接'),
    content: SizedBox(
      width: 460,
      child: TextField(
        onChanged: (value) => draft = value,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'magnet:?xt=urn:btih:…'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, draft),
        child: const Text('确定'),
      ),
    ],
  );
}
