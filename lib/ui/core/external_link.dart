import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error_message.dart';
import 'action_feedback.dart';

/// Opens [url] in the system browser; a failure shows in a snackbar.
Future<void> openExternal(BuildContext context, String url) async {
  final messages = ScaffoldMessenger.of(context);
  try {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('没有可以打开链接的程序');
    }
  } catch (error) {
    showMessage(messages, '打开失败：${errorMessage(error)}');
  }
}
