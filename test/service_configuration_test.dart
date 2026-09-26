import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/service_configuration.dart';

void main() {
  late Directory directory;
  late File file;
  const compiledBangumi = bool.hasEnvironment('BANGUMI_CLIENT_ID');
  const compiledDandanplay = bool.hasEnvironment('DANDANPLAY_APP_ID');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('melonbang-config-');
    file = File('${directory.path}/.env.service.json');
    await file.writeAsString(
      jsonEncode({
        'BANGUMI_CLIENT_ID': 'local-bangumi',
        'BANGUMI_CLIENT_SECRET': 'local-bangumi-secret',
        'BANGUMI_REDIRECT_URI': 'http://127.0.0.1:14568/callback',
        'DANDANPLAY_APP_ID': 'local-dandanplay',
        'DANDANPLAY_APP_SECRET': 'local-dandanplay-secret',
      }),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test('local registrations reach both application services', () async {
    final configuration = await ServiceConfiguration.load(localFile: file);
    final services = AppServices(configuration: configuration);
    addTearDown(services.close);
    expect(services.configuration.bangumiClientId, 'local-bangumi');
    expect(services.configuration.bangumiClientSecret, 'local-bangumi-secret');
    expect(
      services.configuration.bangumiRedirectUri,
      'http://127.0.0.1:14568/callback',
    );
    expect(services.configuration.dandanplayAppId, 'local-dandanplay');
    expect(
      services.configuration.dandanplayAppSecret,
      'local-dandanplay-secret',
    );
  }, skip: !kDebugMode || compiledBangumi || compiledDandanplay);

  test('finds the local file from a checkout subdirectory', () async {
    final previous = Directory.current;
    await File('${directory.path}/pubspec.yaml')
        .writeAsString('name: melonbang');
    final child = await Directory('${directory.path}/nested').create();
    try {
      Directory.current = child;
      final configuration = await ServiceConfiguration.load();
      expect(configuration.bangumiClientId, 'local-bangumi');
      expect(configuration.dandanplayAppId, 'local-dandanplay');
    } finally {
      Directory.current = previous;
    }
  }, skip: !kDebugMode || compiledBangumi || compiledDandanplay);

  test('missing local file keeps compiled defaults', () async {
    await file.delete();
    final configuration = await ServiceConfiguration.load(localFile: file);
    const compiled = ServiceConfiguration();
    expect(configuration.bangumiClientId, compiled.bangumiClientId);
    expect(configuration.bangumiRedirectUri, compiled.bangumiRedirectUri);
    expect(configuration.dandanplayAppSecret, compiled.dandanplayAppSecret);
  });

  test('invalid JSON reports an error without exposing its contents', () async {
    await file.writeAsString('{"BANGUMI_CLIENT_SECRET": private-value}');
    await expectLater(
      ServiceConfiguration.load(localFile: file),
      throwsA(
        isA<FormatException>().having(
          (error) => error.toString(),
          'message',
          'FormatException: Service configuration must be a JSON object.',
        ),
      ),
    );
  }, skip: !kDebugMode || (compiledBangumi && compiledDandanplay));

  test('compiled Bangumi registration never borrows local values', () async {
    final configuration = await ServiceConfiguration.load(localFile: file);
    const compiled = ServiceConfiguration();
    expect(configuration.bangumiClientId, compiled.bangumiClientId);
    expect(configuration.bangumiClientSecret, compiled.bangumiClientSecret);
    expect(configuration.bangumiRedirectUri, compiled.bangumiRedirectUri);
    expect(configuration.hasBangumi, compiled.hasBangumi);
    expect(configuration.dandanplayAppId, 'local-dandanplay');
    expect(configuration.hasDandanplay, isTrue);
  }, skip: !kDebugMode || !compiledBangumi || compiledDandanplay);

  test('compiled registrations ignore local files, including explicit empty values', () async {
    await file.writeAsString('invalid JSON is never read');
    final configuration = await ServiceConfiguration.load(localFile: file);
    const compiled = ServiceConfiguration();
    expect(configuration.bangumiClientId, compiled.bangumiClientId);
    expect(configuration.bangumiClientSecret, compiled.bangumiClientSecret);
    expect(configuration.dandanplayAppId, compiled.dandanplayAppId);
    expect(configuration.dandanplayAppSecret, compiled.dandanplayAppSecret);
    expect(configuration.hasDandanplay, compiled.hasDandanplay);
  }, skip: !compiledBangumi || !compiledDandanplay);

  test('non-debug startup never reads local configuration', () async {
    await file.writeAsString('invalid JSON is never read');
    final configuration = await ServiceConfiguration.load(localFile: file);
    const compiled = ServiceConfiguration();
    expect(configuration.bangumiClientId, compiled.bangumiClientId);
    expect(configuration.bangumiClientSecret, compiled.bangumiClientSecret);
    expect(configuration.dandanplayAppId, compiled.dandanplayAppId);
    expect(configuration.dandanplayAppSecret, compiled.dandanplayAppSecret);
  }, skip: kDebugMode);
}
