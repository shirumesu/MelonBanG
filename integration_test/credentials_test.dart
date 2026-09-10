import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:melonbang/data/credentials.dart';
import 'package:melonbang/data/account.dart';
import 'package:melonbang/data/network.dart';

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
      expect(await first.read('account', allowInteraction: false), isNull);
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
  testWidgets('login-keychain ACL denial is deferred without a password dialog', (
    tester,
  ) async {
    if (!Platform.isMacOS) return;
    final directory = await Directory.systemTemp.createTemp(
      'melonbang-quiet-credentials-',
    );
    final service =
        'org.melonbang.credentials.${sha256.convert(utf8.encode(p.normalize(p.absolute(directory.path))))}';
    try {
      final created = await Process.run('/usr/bin/security', [
        'add-generic-password',
        '-a',
        'account',
        '-s',
        service,
        '-w',
        'test-only-secret',
        '-T',
        '',
      ]);
      expect(created.exitCode, 0, reason: created.stderr.toString());
      await expectLater(
        MacOSCredentials(directory.path)
            .read('account', allowInteraction: false),
        throwsA(isA<CredentialInteractionRequired>()),
      );
      final api = ApiClient();
      final account = AccountRepository(
        api,
        platformCredentials(directory.path),
      );
      try {
        await account.initialize();
        expect(account.session, isNull);
      } finally {
        await account.close();
        api.close();
      }
    } finally {
      await Process.run('/usr/bin/security', [
        'delete-generic-password',
        '-a',
        'account',
        '-s',
        service,
      ]);
      await directory.delete(recursive: true);
    }
  });
}
