import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'install.dart';

// Melonbang's palette, from the app's ui/core/theme.dart.
const _mint = Color(0xff22b388);
const _primary = Color(0xff168364);
const _coral = Color(0xffff6b81);
const _brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xff65cfad), Color(0xff8bddbf)],
);

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SetupApp(installer: Installer.fromArguments(arguments)));
}

class SetupApp extends StatelessWidget {
  const SetupApp({super.key, required this.installer});
  final Installer installer;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '安装 MelonBanG',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _mint)
          .copyWith(primary: _primary, surface: const Color(0xfffbfcfb)),
      scaffoldBackgroundColor: const Color(0xfffbfcfb),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Color(0xfff3f5f4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(112, 44),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
    ),
    home: SetupPage(installer: installer),
  );
}

enum _Step { options, installing, done }

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.installer});
  final Installer installer;
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final location = TextEditingController();
  var step = _Step.options;
  var desktop = true, startMenu = true, launchAfter = true;
  bool updating = false;
  double progress = 0;
  String current = '';
  String? error;

  Installer get installer => widget.installer;

  @override
  void initState() {
    super.initState();
    location.addListener(() async {
      final installed = await installer.isInstalled(location.text.trim());
      if (mounted && installed != updating) {
        setState(() => updating = installed);
      }
    });
    installer.defaultLocation().then((value) => location.text = value);
  }

  Future<void> browse() async {
    final picked = await installer.pick(location.text.trim());
    if (picked != null) location.text = picked;
  }

  Future<void> install() async {
    location.text = await installer.target(location.text.trim());
    setState(() {
      step = _Step.installing;
      error = null;
      progress = 0;
    });
    try {
      await installer.install(
        location.text.trim(),
        desktop: desktop,
        startMenu: startMenu,
        onProgress: (value, file) => setState(() {
          progress = value;
          current = file;
        }),
      );
      setState(() => step = _Step.done);
    } on InstallError catch (e) {
      setState(() {
        step = _Step.options;
        error = e.message;
      });
    } on PlatformException catch (e) {
      setState(() {
        step = _Step.options;
        error = e.message;
      });
    }
  }

  Future<void> finish() async {
    if (launchAfter) await installer.launch(location.text.trim());
    await closeWindow();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onPanStart: (_) => startDrag(),
          child: const _BrandPanel(),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TitleBar(closable: step != _Step.installing),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 4, 40, 32),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: switch (step) {
                      _Step.options => _options(context),
                      _Step.installing => _installing(context),
                      _Step.done => _done(context),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _options(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      key: const ValueKey('options'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          updating ? '更新 MelonBanG' : '安装 MelonBanG',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          updating ? '将覆盖这里的旧版本，追番记录和设置都会保留。' : '选择安装位置和要创建的快捷方式。',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 28),
        const Text('安装位置', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: TextField(controller: location)),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: browse,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              child: const Text('浏览…'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          error ??
              '需要约 ${(installedSize / 1024 / 1024).ceil()} MB 空间，'
                  '不需要管理员权限。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: error == null ? muted : _coral,
          ),
        ),
        const SizedBox(height: 20),
        _Check(
          label: '创建桌面快捷方式',
          value: desktop,
          onChanged: (value) => setState(() => desktop = value),
        ),
        _Check(
          label: '添加到开始菜单',
          value: startMenu,
          onChanged: (value) => setState(() => startMenu = value),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '安装即表示同意 ',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  InkWell(
                    onTap: () =>
                        openLink('https://www.gnu.org/licenses/gpl-3.0.html'),
                    child: Text(
                      'GPL-3.0 许可',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: install,
              child: Text(updating ? '更新' : '安装'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _installing(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('installing'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          updating ? '正在更新…' : '正在安装…',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 28),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: progress, minHeight: 10),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                current,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text('${(progress * 100).round()}%'),
          ],
        ),
      ],
    );
  }

  Widget _done(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('done'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        const Icon(Icons.check_circle, color: _mint, size: 56),
        const SizedBox(height: 16),
        Text(
          updating ? '更新完成' : '安装完成',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'MelonBanG $appVersion 已安装到 ${location.text.trim()}',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: _Check(
                label: '立即启动 MelonBanG',
                value: launchAfter,
                onChanged: (value) => setState(() => launchAfter = value),
              ),
            ),
            FilledButton(onPressed: finish, child: const Text('完成')),
          ],
        ),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: () => onChanged(!value),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: (value) => onChanged(value!)),
        Text(label),
        const SizedBox(width: 8),
      ],
    ),
  );
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.closable});
  final bool closable;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanStart: (_) => startDrag(),
    child: Container(
      height: 44,
      color: Colors.transparent,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '最小化',
            onPressed: minimize,
            icon: const Icon(Icons.remove, size: 16),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: closable ? closeWindow : null,
            icon: const Icon(Icons.close, size: 17),
          ),
        ],
      ),
    ),
  );
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) => Container(
    width: 260,
    decoration: const BoxDecoration(gradient: _brandGradient),
    padding: const EdgeInsets.fromLTRB(32, 48, 32, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33164d39),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/akkarin.png', fit: BoxFit.cover),
        ),
        const SizedBox(height: 28),
        const Text(
          'MelonBanG',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .28),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            appVersion,
            style: TextStyle(
              color: Color(0xff164d39),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          '追番、找资源、看番\n一个应用就够了',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            height: 1.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '开源软件 · GPL-3.0',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .85),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}
