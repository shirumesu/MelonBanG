import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/storage_usage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('storage-usage-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('nested media is not counted as application data', () async {
    File(p.join(root.path, 'records')).writeAsBytesSync(List.filled(65536, 1));
    final before = await StorageUsage.measure(
      root.path,
      p.join(root.path, 'downloads'),
    );
    final media = Directory(p.join(root.path, 'downloads'))..createSync();
    File(p.join(media.path, 'video')).writeAsBytesSync(List.filled(262144, 2));
    final after = await StorageUsage.measure(root.path, media.path);
    expect(after.dataBytes, before.dataBytes);
    expect(after.mediaBytes, greaterThanOrEqualTo(262144));
    expect(before.mediaBytes, 0);
  });

  test(
    'separate directories and failed locations remain independent',
    () async {
      final data = Directory(p.join(root.path, 'data'))..createSync();
      final media = Directory(p.join(root.path, 'media'))..createSync();
      File(p.join(data.path, 'records'))
          .writeAsBytesSync(List.filled(65536, 1));
      File(p.join(media.path, 'video'))
          .writeAsBytesSync(List.filled(131072, 2));
      final usage = await StorageUsage.measure(data.path, media.path);
      expect(usage.dataBytes, greaterThanOrEqualTo(65536));
      expect(usage.mediaBytes, greaterThanOrEqualTo(131072));
      final invalid = File(p.join(root.path, 'not-a-directory'))
        ..writeAsStringSync('x');
      final unavailable = await StorageUsage.measure(invalid.path, media.path);
      expect(unavailable.dataBytes, isNull);
      expect(unavailable.mediaBytes, usage.mediaBytes);
    },
  );

  test(
    'sparse media uses allocated space and directory links are not followed',
    () async {
      final media = Directory(p.join(root.path, 'media'))..createSync();
      final sparse = File(p.join(media.path, 'partial-video'))
          .openSync(mode: FileMode.write);
      sparse.setPositionSync(1024 * 1024 * 1024);
      sparse.writeByteSync(1);
      sparse.closeSync();
      final outside = Directory(p.join(root.path, 'outside'))..createSync();
      File(p.join(outside.path, 'external'))
          .writeAsBytesSync(List.filled(1048576, 1));
      Link(p.join(media.path, 'external-link')).createSync(outside.path);
      final usage = await StorageUsage.measure(
        p.join(root.path, 'missing'),
        media.path,
      );
      expect(usage.dataBytes, 0);
      expect(usage.mediaBytes, greaterThan(0));
      expect(usage.mediaBytes, lessThan(1048576));
    },
    skip: !Platform.isMacOS,
  );
}
