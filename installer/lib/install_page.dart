import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bot.dart';
import 'install.dart';
import 'shell.dart';

enum _Step { options, installing, done }

class InstallPage extends StatefulWidget {
  const InstallPage({super.key, required this.installer});
  final Installer installer;
  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  final location = TextEditingController();
  var step = _Step.options;
  var desktop = true, startMenu = true;
  bool updating = false;
  double progress = 0;
  String current = '';
  String? error;
  int errors = 0;
  int? bytes;

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
    installer.contents.then((value) => setState(() => bytes = value.bytes));
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
      fail(e.message);
    } on PlatformException catch (e) {
      fail(e.message ?? e.code);
    }
  }

  void fail(String message) => setState(() {
    step = _Step.options;
    error = message;
    errors++;
  });

  Future<void> launch() async {
    await installer.launch(location.text.trim());
    await closeWindow();
  }

  @override
  Widget build(BuildContext context) => SetupShell(
    step: step,
    mode: switch (step) {
      _Step.options => error == null ? BotMode.idle : BotMode.error,
      _Step.installing => BotMode.spin,
      _Step.done => BotMode.cheer,
    },
    tone: error == null ? BotTone.mint : BotTone.coral,
    closable: step != _Step.installing,
    content: switch (step) {
      _Step.options => _options(),
      _Step.installing => _installing(),
      _Step.done => _done(),
    },
  );

  Widget _options() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Rise(0, Text(updating ? '更新 MelonBanG' : '安装 MelonBanG', style: heading)),
      const SizedBox(height: 10),
      Rise(
        1,
        Text(
          updating ? '会覆盖这里的旧版本，追番记录和设置都会保留。' : '追番、找资源、看番，一个应用就够了。',
          style: intro,
        ),
      ),
      const SizedBox(height: 30),
      Rise(
        2,
        Shake(
          trigger: errors,
          child: Panel(
            ring: error == null ? null : coral,
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 20, color: deep),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('安装位置', style: note),
                      TextField(
                        controller: location,
                        // Wraps so that a long path shows its end.
                        maxLines: null,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(fontSize: 13, color: ink),
                        decoration: const InputDecoration.collapsed(
                          hintText: '',
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: browse,
                  style: TextButton.styleFrom(
                    foregroundColor: deep,
                    textStyle: const TextStyle(fontSize: 13),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                  ),
                  child: const Text('更改'),
                ),
              ],
            ),
          ),
        ),
      ),
      if (error case final message?) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.error_outline, size: 15, color: danger),
            const SizedBox(width: 8),
            Text(message, style: const TextStyle(fontSize: 12, color: danger)),
          ],
        ),
      ],
      const SizedBox(height: 14),
      Rise(
        3,
        Row(
          children: [
            _Toggle(
              label: '桌面快捷方式',
              value: desktop,
              onChanged: (value) => setState(() => desktop = value),
            ),
            const SizedBox(width: 10),
            _Toggle(
              label: '开始菜单',
              value: startMenu,
              onChanged: (value) => setState(() => startMenu = value),
            ),
          ],
        ),
      ),
      const Spacer(),
      Rise(
        4,
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bytes == null
                        ? '不需要管理员权限'
                        : '需要 ${(bytes! / 1024 / 1024).ceil()} MB，不需要管理员权限',
                    style: note,
                  ),
                  Row(
                    children: [
                      const Text('安装即表示同意 ', style: note),
                      InkWell(
                        onTap: () => openLink(
                          'https://www.gnu.org/licenses/gpl-3.0.html',
                        ),
                        child: const Text(
                          'GPL-3.0 许可',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: deep,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SetupButton(
              updating ? '更新' : '安装',
              onPressed: install,
              trailing: Icons.arrow_forward_rounded,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _installing() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Rise(0, Text(updating ? '正在更新' : '正在安装', style: heading)),
      const Spacer(),
      Rise(1, ProgressBlock(progress: progress, task: current, colour: deep)),
    ],
  );

  Widget _done() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Rise(0, Text(updating ? '更新完成' : '安装完成', style: heading)),
      const SizedBox(height: 10),
      const Rise(1, Text('MelonBanG $appVersion 已经准备好了，开始追番吧。', style: intro)),
      const Spacer(),
      Rise(
        2,
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const SetupButton(
              '关闭',
              onPressed: closeWindow,
              style: ActionStyle.ghost,
            ),
            const SizedBox(width: 10),
            SetupButton(
              '启动 MelonBanG',
              onPressed: launch,
              icon: Icons.play_arrow_rounded,
            ),
          ],
        ),
      ),
    ],
  );
}

/// A pill that toggles one option, with a tick when on.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: value,
    child: Material(
      color: value ? const Color(0xffe1f4eb) : canvas,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 17,
                color: value ? deep : muted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(fontSize: 13, color: value ? deep : muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
