import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/app_services.dart';
import 'package:melonbang/data/credentials.dart';
import 'package:melonbang/data/store.dart';
import 'package:path/path.dart' as p;

class UnavailableCredentials implements Credentials {
  @override
  Future<String?> read(String key, {bool allowInteraction = true}) async =>
      throw StateError('Unavailable');
  @override
  Future<void> write(String key, String? value) async {}
}

void main() {
  test(
    'failed startup releases the opened database and closes idempotently',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'melonbang-start-',
      );
      final services = AppServices(
        directory: directory.path,
        credentials: UnavailableCredentials(),
      );
      try {
        await expectLater(services.start(), throwsStateError);
        await services.close();
        await services.close();
        await expectLater(services.start(), throwsStateError);
        final reopened = await AppStore.open(
          p.join(directory.path, 'melonbang.sqlite'),
        );
        await reopened.put('test', 'reopened', {'value': true});
        expect((await reopened.get('test', 'reopened'))?['value'], isTrue);
        await reopened.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
