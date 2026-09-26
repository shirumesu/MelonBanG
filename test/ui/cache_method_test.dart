import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/data/cache_method.dart';
import 'package:melonbang/data/json.dart';
import 'package:melonbang/data/pikpak.dart';
import 'package:melonbang/ui/acquisition/download_dialogs.dart';
import 'package:melonbang/ui/acquisition/downloads_page.dart';
import 'package:melonbang/ui/acquisition/resources_page.dart';
import 'package:melonbang/ui/core/theme.dart';
import 'package:melonbang/ui/settings/cache_settings.dart';
import 'package:melonbang/ui/settings/settings_page.dart';

void main() {
  for (final width in [1200.0, 680.0]) {
    testWidgets(
      'resource actions select independent cache methods at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final query = TextEditingController();
        addTearDown(query.dispose);
        final calls = <CacheMethod>[];
        final gate = Completer<void>();
        var preferred = CacheMethod.bt;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(false),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return ResourcesPage(
                    subject: const {'name': 'Anime'},
                    resourceSearch: query,
                    resourceEpisode: null,
                    providers: const [],
                    candidates: const [
                      {
                        'candidateId': 'one',
                        'title': '[Group] Anime [01][1080p]',
                      },
                    ],
                    busy: false,
                    defaultMethod: preferred,
                    onSearch: (_, _) async {},
                    onDownload: (_) async => fail(
                      'Legacy callback must not bypass the selected method',
                    ),
                    onDownloadWithMethod: (candidate, method) async {
                      expect(candidate['candidateId'], 'one');
                      calls.add(method);
                      if (calls.length == 1) await gate.future;
                    },
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('下载 · 默认 BT'));
        await tester.pump();
        expect(calls, [CacheMethod.bt]);
        expect(
          tester
              .widget<PopupMenuButton<CacheMethod>>(
                find.byType(PopupMenuButton<CacheMethod>),
              )
              .enabled,
          isFalse,
        );
        gate.complete();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('其他缓存方式 · 默认 BT'));
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<CacheMethod>), findsOneWidget);
        expect(find.text('PikPak 下载'), findsOneWidget);
        await tester.tap(find.text('PikPak 下载'));
        await tester.pumpAndSettle();
        expect(calls, [CacheMethod.bt, CacheMethod.pikpak]);
        update(() => preferred = CacheMethod.pikpak);
        await tester.pumpAndSettle();
        expect(find.byTooltip('已加入下载'), findsOneWidget);
        await tester.tap(find.byTooltip('其他缓存方式 · 默认 PikPak'));
        await tester.pumpAndSettle();
        expect(find.text('BT 下载 · 已加入'), findsOneWidget);
        expect(
          tester
              .widget<PopupMenuItem<CacheMethod>>(
                find.byType(PopupMenuItem<CacheMethod>),
              )
              .enabled,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'settings saves preference and supports failed login retry and logout',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var method = CacheMethod.bt;
      Json? account;
      final credentials = <(String, String)>[];
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return SettingsPage(
                  account: null,
                  sync: const {},
                  dark: false,
                  dataDirectory: null,
                  bitTorrentSettings: const Text('BT controls'),
                  onAccountAction: () {},
                  onCancelSignIn: () {},
                  onThemeChanged: (_) {},
                  cacheSettings: CacheSettings(
                    defaultMethod: method,
                    account: account,
                    onMethodChanged: (value) async =>
                        update(() => method = value),
                    onLogin: (name, password) async {
                      credentials.add((name, password));
                      if (credentials.length == 1) throw StateError('账号或密码有误');
                      update(() => account = {'username': name});
                    },
                    onLogout: () async => update(() => account = null),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('缓存方式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PikPak'));
      await tester.pumpAndSettle();
      expect(method, CacheMethod.pikpak);
      await tester.enterText(
        find.byKey(const ValueKey('pikpak-username')),
        ' reader@example.com ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pikpak-password')),
        'test-password',
      );
      await tester.tap(find.text('登录 PikPak'));
      await tester.pumpAndSettle();
      expect(find.text('账号或密码有误'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('pikpak-password')))
            .controller!
            .text,
        'test-password',
      );
      await tester.tap(find.text('登录 PikPak'));
      await tester.pumpAndSettle();
      expect(credentials, [
        ('reader@example.com', 'test-password'),
        ('reader@example.com', 'test-password'),
      ]);
      expect(find.text('reader@example.com'), findsOneWidget);
      await tester.tap(find.text('退出 PikPak'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('pikpak-password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('登录 PikPak'), findsOneWidget);
      expect(method, CacheMethod.pikpak);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PikPak cache exposes local pause and removal without seeding controls',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
            body: DownloadsPage(
              downloads: const {
                'tasks': [
                  {
                    'id': 'pending',
                    'title': 'Cloud preparing',
                    'provider': 'pikpak',
                    'status': 'metadata',
                    'progress': 0,
                  },
                  {
                    'id': 'done',
                    'title': 'Local cached',
                    'provider': 'pikpak',
                    'status': 'completed',
                    'progress': 1,
                  },
                ],
                'files': [
                  {
                    'id': 'file',
                    'downloadId': 'done',
                    'name': 'episode.mkv',
                    'mediaKind': 'video',
                    'progress': 1,
                  },
                ],
              },
              onAddMagnet: () {},
              onAddTorrent: () {},
              onOpenVideo: () {},
              onExplore: () {},
              onTogglePause: (task) => actions.add('pause:${task['id']}'),
              onRemove: (task) => actions.add('remove:${task['id']}'),
              onStopSeeding: (_) => fail('Cloud downloads do not seed'),
              onPlay: (id, _) => actions.add('play:$id'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('云端准备中'), findsOneWidget);
      expect(find.text('PikPak'), findsNWidgets(2));
      await tester.tap(find.byTooltip('暂停 / 继续本机缓存'));
      await tester.tap(find.text('播放'));
      for (final button in find.byTooltip('任务详情').evaluate().toList()) {
        await tester.tap(find.byWidget(button.widget));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('分享率'), findsNothing);
      expect(find.textContaining('继续做种'), findsNothing);
      expect(find.textContaining('已按做种设置停止'), findsNothing);
      expect(find.text('移除本机任务与缓存'), findsNWidgets(2));
      await tester.tap(find.text('移除本机任务与缓存').last);
      expect(actions, ['pause:pending', 'play:done', 'remove:done']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('PikPak account challenges preserve login fields for retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(false),
        home: Scaffold(
          body: CacheSettings(
            defaultMethod: CacheMethod.bt,
            onMethodChanged: (_) async {},
            onLogin: (_, _) async => throw PikPakCaptchaRequired(
              Uri.parse('https://mypikpak.com/verification'),
            ),
            onLogout: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('pikpak-username')),
      'reader@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('pikpak-password')),
      'test-password',
    );
    await tester.tap(find.text('登录 PikPak'));
    await tester.pumpAndSettle();
    expect(find.text('打开 PikPak 验证'), findsOneWidget);
    expect(find.textContaining('再点击「登录 PikPak」重试'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('pikpak-password')))
          .controller!
          .text,
      'test-password',
    );
  });

  testWidgets(
    'PikPak saved credentials unlock explicitly and show drive verification',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var unlocked = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CacheSettings(
                defaultMethod: CacheMethod.pikpak,
                account: const {'username': 'reader@example.com'},
                needsAuthorization: !unlocked,
                verificationUrl: unlocked
                    ? Uri.parse('https://mypikpak.com/verification')
                    : null,
                onMethodChanged: (_) async {},
                onLogin: (_, _) async {},
                onLogout: () async {},
                onUnlock: () async => setState(() => unlocked = true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(unlocked, isFalse);
      await tester.tap(find.text('解锁 PikPak'));
      await tester.pumpAndSettle();
      expect(unlocked, isTrue);
      expect(find.text('reader@example.com'), findsOneWidget);
      expect(find.text('打开 PikPak 验证'), findsOneWidget);
      expect(find.textContaining('回到缓存页面继续下载任务'), findsOneWidget);
    },
  );

  testWidgets('cloud removal explains remote preservation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RemoveDownloadDialog(title: 'Anime', cloud: true)),
      ),
    );
    expect(find.textContaining('PikPak 云端文件会保留'), findsOneWidget);
  });
}
