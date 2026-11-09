import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error_message.dart';
import 'action_feedback.dart';

/// Opens [url] in the system browser; a failure shows in a snackbar. Only
/// web addresses open: links come from posts, source rules and release
/// pages, and another scheme would hand them to whatever program claims it.
Future<void> openExternal(BuildContext context, String url) async {
  final messages = ScaffoldMessenger.of(context);
  try {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      throw StateError('不是网页链接');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('没有可以打开链接的程序');
    }
  } catch (error) {
    showMessage(messages, '打开失败：${errorMessage(error)}');
  }
}
