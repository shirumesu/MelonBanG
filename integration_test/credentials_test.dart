import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:melonbang/data/credentials.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native credentials persist, isolate profiles, and delete', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'melonbang-secrets-',
    );
    final first = platformCredentials('${directory.path}/first');
    final second = platformCredentials('${directory.path}/second');
    try {
      expect(await first.read('account'), isNull);
      await first.write('account', '测试 token');
      expect(
        await platformCredentials('${directory.path}/first').read('account'),
        '测试 token',
      );
      expect(await second.read('account'), isNull);
      await Future.wait([
        first.write('account', 'refreshed'),
        first.write('account', 'latest'),
      ]);
      expect(await first.read('account'), 'latest');
      await first.write('account', null);
      expect(await first.read('account'), isNull);
      await first.write('account', null);
    } finally {
      await first.write('account', null);
      await second.write('account', null);
      await directory.delete(recursive: true);
    }
  });
}
