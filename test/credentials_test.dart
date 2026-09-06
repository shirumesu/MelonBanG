import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/credentials.dart';

void main() {
  test(
    'overlapping credential saves and sign-out persist the last operation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-credentials-',
      );
      try {
        final credentials = WindowsCredentials(directory.path);
        await Future.wait([
          credentials.write('account', 'first-token' * 1000),
          credentials.write('account', 'refreshed-token'),
          credentials.write('account', null),
        ]);
        expect(await credentials.read('account'), isNull);
        await Future.wait([
          credentials.write('account', 'another-token'),
          credentials.write('account', 'latest-token'),
        ]);
        expect(await credentials.read('account'), 'latest-token');
        expect(
          await File('${directory.path}/account.bin.pending').exists(),
          isFalse,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}
