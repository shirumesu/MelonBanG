import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/storage_locations.dart';
import 'package:melonbang/ui/core/theme.dart';
import 'package:melonbang/ui/settings/storage_settings.dart';

class _MemoryLocations extends StorageLocations {
  _MemoryLocations() : super(File('unused-bootstrap'), '/data');
  Json? plan;
  @override
  Json? get pending => plan;
  @override
  Future<void> schedule({String? dataPath, String? mediaPath}) async {
    plan = {'data': dataPath ?? data, 'media': mediaPath ?? media};
  }

  @override
  Future<void> cancel() async => plan = null;
}

void main() {
  testWidgets(
    'location changes require confirmation and pending migration can be cancelled',
    (tester) async {
      final locations = _MemoryLocations();
      const destination = '/new-data';
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'getDirectoryPath');
        return destination;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StorageSettings(
                storage: locations,
                dataDirectory: locations.data,
                mediaDirectory: locations.media,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('更改位置').first);
      await tester.pumpAndSettle();
      expect(find.text('迁移应用数据？'), findsOneWidget);
      expect(find.text(destination), findsOneWidget);
      expect(locations.pending, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(locations.pending, isNull);
      await tester.tap(find.text('更改位置').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认迁移'));
      await tester.pumpAndSettle();
      expect(locations.pending?['data'], destination);
      expect(locations.data, '/data');
      expect(find.text('迁移已安排 · 重启后生效'), findsOneWidget);
      await tester.ensureVisible(find.text('取消迁移'));
      await tester.tap(find.text('取消迁移'));
      await tester.pumpAndSettle();
      expect(locations.pending, isNull);
      expect(find.text('迁移已安排 · 重启后生效'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
