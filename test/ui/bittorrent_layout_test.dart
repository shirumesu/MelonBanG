import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/bittorrent_settings.dart';
import 'package:melonbang/data/downloads.dart';
import 'package:melonbang/data/store.dart';
import 'package:melonbang/ui/core/theme.dart';
import 'package:melonbang/ui/settings/bittorrent_settings.dart';

class _SettingsRepository extends DownloadRepository {
  _SettingsRepository(super.store, super.directory);

  @override
  Future<void> saveSettings(BitTorrentSettings value) async {
    value.validate();
    settings = value;
  }
}

void main() {
  late Directory directory;
  late AppStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('melon-settings-ui-');
    store = await AppStore.open('${directory.path}/test.sqlite');
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  testWidgets(
    'compact settings preserve advanced values and convert fractional MiB limits',
    (tester) async {
      final downloads = _SettingsRepository(
        store,
        '${directory.path}/downloads',
      );
      downloads.settings = const BitTorrentSettings(
        downloadKiB: 128,
        uploadKiB: 512,
        connectionsPerTask: 87,
        seedMinutes: 120,
      );
      addTearDown(() async {
        await downloads.close();
      });
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(850, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: BitTorrentSettingsPanel(downloads: downloads),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final upload = find.byKey(
        const PageStorageKey('bittorrent-field:uploadKiB'),
      );
      final advanced = find.byKey(
        const PageStorageKey('bittorrent-field:connectionsPerTask'),
      );
      expect(advanced, findsNothing);
      expect(tester.widget<TextField>(upload).controller!.text, '0.5');
      await tester.enterText(upload, '0.25');
      await tester.ensureVisible(find.text('保存并应用'));
      await tester.tap(find.text('保存并应用'));
      await tester.pumpAndSettle();
      expect(downloads.settings.uploadKiB, 256);
      expect(downloads.settings.downloadKiB, 128);
      expect(downloads.settings.connectionsPerTask, 87);
      expect(downloads.settings.seedMinutes, 120);
      await tester.ensureVisible(find.text('高级设置'));
      await tester.tap(find.text('高级设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(advanced);
      await tester.enterText(advanced, '96');
      await tester.ensureVisible(find.text('高级设置'));
      await tester.tap(find.text('高级设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存并应用'));
      await tester.tap(find.text('保存并应用'));
      await tester.pumpAndSettle();
      expect(downloads.settings.connectionsPerTask, 96);
      tester.view.physicalSize = const Size(340, 1000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Checkbox), findsNothing);
    },
  );
}
