import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Application registrations supplied by build definitions or local development.
class ServiceConfiguration {
  const ServiceConfiguration({
    this.bangumiClientId = const String.fromEnvironment('BANGUMI_CLIENT_ID'),
    this.bangumiClientSecret = const String.fromEnvironment(
      'BANGUMI_CLIENT_SECRET',
    ),
    this.bangumiRedirectUri = const String.fromEnvironment(
      'BANGUMI_REDIRECT_URI',
      defaultValue: 'http://127.0.0.1:14567/callback',
    ),
    this.dandanplayAppId = const String.fromEnvironment('DANDANPLAY_APP_ID'),
    this.dandanplayAppSecret = const String.fromEnvironment(
      'DANDANPLAY_APP_SECRET',
    ),
  });

  final String bangumiClientId;
  final String bangumiClientSecret;
  final String bangumiRedirectUri;
  final String dandanplayAppId;
  final String dandanplayAppSecret;

  static Future<ServiceConfiguration> load({File? localFile}) async {
    const compiled = ServiceConfiguration();
    if (!kDebugMode) return compiled;

    const compiledBangumi =
        bool.hasEnvironment('BANGUMI_CLIENT_ID') ||
        bool.hasEnvironment('BANGUMI_CLIENT_SECRET') ||
        bool.hasEnvironment('BANGUMI_REDIRECT_URI');
    const compiledDandanplay =
        bool.hasEnvironment('DANDANPLAY_APP_ID') ||
        bool.hasEnvironment('DANDANPLAY_APP_SECRET');
    if (compiledBangumi && compiledDandanplay) return compiled;

    final file = localFile ?? _developmentFile();
    if (file == null || !await file.exists()) return compiled;
    final Map<String, dynamic> values;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      values = decoded;
    } on FormatException {
      // JSON parser errors can include registration secrets from the input.
      throw const FormatException(
        'Service configuration must be a JSON object.',
      );
    }
    String value(String key, [String fallback = '']) {
      final entry = values[key];
      if (entry == null) return fallback;
      if (entry is! String) {
        throw FormatException('Service configuration $key must be a string.');
      }
      return entry;
    }

    return ServiceConfiguration(
      bangumiClientId: compiledBangumi
          ? compiled.bangumiClientId
          : value('BANGUMI_CLIENT_ID'),
      bangumiClientSecret: compiledBangumi
          ? compiled.bangumiClientSecret
          : value('BANGUMI_CLIENT_SECRET'),
      bangumiRedirectUri: compiledBangumi
          ? compiled.bangumiRedirectUri
          : value('BANGUMI_REDIRECT_URI', compiled.bangumiRedirectUri),
      dandanplayAppId: compiledDandanplay
          ? compiled.dandanplayAppId
          : value('DANDANPLAY_APP_ID'),
      dandanplayAppSecret: compiledDandanplay
          ? compiled.dandanplayAppSecret
          : value('DANDANPLAY_APP_SECRET'),
    );
  }

  static File? _developmentFile() {
    final override = Platform.environment['MELONBANG_CONFIGURATION_FILE'];
    if (override != null && override.isNotEmpty) return File(override);
    // Desktop IDE launches may start outside the checkout's working directory.
    for (var directory in [
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ]) {
      while (true) {
        if (File.fromUri(directory.uri.resolve('pubspec.yaml')).existsSync()) {
          return File.fromUri(directory.uri.resolve('.env.service.json'));
        }
        final parent = directory.parent;
        if (parent.path == directory.path) break;
        directory = parent;
      }
    }
    return null;
  }

  bool get hasBangumi =>
      bangumiClientId.trim().isNotEmpty &&
      bangumiClientSecret.trim().isNotEmpty;
  bool get hasDandanplay =>
      dandanplayAppId.trim().isNotEmpty &&
      dandanplayAppSecret.trim().isNotEmpty;
}
