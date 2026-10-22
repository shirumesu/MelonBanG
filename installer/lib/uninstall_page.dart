import 'dart:async';

import 'package:flutter/material.dart';

import 'bot.dart';
import 'install.dart';
import 'shell.dart';
import 'uninstall.dart';

enum _Step { confirm, waiting, removing, done, failed }

class UninstallPage extends StatefulWidget {
  const UninstallPage({super.key, required this.uninstaller});
  final Uninstaller uninstaller;
  @override
  State<UninstallPage> createState() => _UninstallPageState();
}

class _UninstallPageState extends State<UninstallPage> {
  var step = _Step.confirm;
  var wipe = false;
  int? dataSize;
  double progress = 0;
  String task = '';
  List<String> left = const [];
  Timer? waiting;

  Uninstaller get uninstaller => widget.uninstaller;

  @override
  void initState() {
    super.initState();
    uninstaller.dataSize.then((value) {
      if (mounted) setState(() => dataSize = value);
    });
  }

  @override
  void dispose() {
    waiting?.cancel();
    super.dispose();
  }

  Future<void> start() async {
    if (await isRunning(uninstaller.location)) {
      setState(() => step = _Step.waiting);
      // Continues by itself once the program has exited.
      waiting = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (!await isRunning(uninstaller.location)) {
          timer.cancel();
          if (step == _Step.waiting) remove();
        }
      });
      return;
    }
    remove();
  }

  void cancelWaiting() {
    waiting?.cancel();
    setState(() => step = _Step.confirm);
  }

  Future<void> remove() async {
    setState(() {
      step = _Step.removing;
      progress = 0;
    });
    final left = await uninstaller.uninstall(
      wipe: wipe,
      onProgress: (value, name) => setState(() {
        progress = value;
        task = name;
      }),
    );
    setState(() {
      this.left = left;
      step = left.isEmpty ? _Step.done : _Step.failed;
    });
  }

  @override
  Widget build(BuildContext context) => SetupShell(
    step: step,
    mode: switch (step) {
      _Step.confirm => wipe ? BotMode.error : BotMode.idle,
      _Step.waiting => BotMode.sleep,
      _Step.removing => BotMode.shrink,
      _Step.done => BotMode.hop,
      _Step.failed => BotMode.error,
    },
    tone: switch (step) {
      _Step.waiting => BotTone.muted,
      _Step.failed => BotTone.coral,
      _Step.done => BotTone.mint,
      _ => wipe ? BotTone.coral : BotTone.mint,
    },
    progress: progress,
    closable: step != _Step.removing,
    content: switch (step) {
      _Step.confirm => _confirm(),
      _Step.waiting => _waiting(),
      _Step.removing => _removing(),
      _Step.done => _done(),
      _Step.failed => _failed(),
    },
  );

  Widget _confirm() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Rise(0, Text('卸载 MelonBanG', style: heading)),
      const SizedBox(height: 10),
      const Rise(1, Text('程序文件和快捷方式会被删除。', style: intro)),
      const SizedBox(height: 22),
      Rise(
        2,
        _Choice(
          title: '保留我的数据',
          detail: '追番记录、设置和已下载的番剧留在电脑上，重新安装后接着用。',
          selected: !wipe,
          colour: mint,
          tint: const Color(0xffe1f4eb),
          onTap: () => setState(() => wipe = false),
        ),
      ),
      const SizedBox(height: 10),
      Rise(
        3,
        _Choice(
          title: '删除所有数据',
          detail: dataSize == null
              ? '追番记录、设置、登录信息和已下载的番剧一并删除，无法恢复。'
              : '追番记录、设置、登录信息和已下载的番剧（${_size(dataSize!)}）一并删除，无法恢复。',
          selected: wipe,
          colour: coral,
          tint: const Color(0xffffeef0),
          onTap: () => setState(() => wipe = true),
        ),
      ),
      const Spacer(),
      Rise(
        4,
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const SetupButton(
              '取消',
              onPressed: closeWindow,
              style: ActionStyle.ghost,
            ),
            const SizedBox(width: 10),
            SetupButton(
              wipe ? '卸载并删除数据' : '卸载',
              onPressed: start,
              style: wipe ? ActionStyle.danger : ActionStyle.ink,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _waiting() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Rise(0, Text('请先关闭 MelonBanG', style: heading)),
      const SizedBox(height: 10),
      const Rise(1, Text('它还在运行。关闭后会自动继续卸载。', style: intro)),
      const SizedBox(height: 26),
      const Rise(
        2,
        Panel(
          colour: Color(0xfffff4e0),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xff8a5a00),
                ),
              ),
              SizedBox(width: 12),
              Text(
                '正在等待 MelonBanG 退出',
                style: TextStyle(fontSize: 13, color: Color(0xff8a5a00)),
              ),
            ],
          ),
        ),
      ),
      const Spacer(),
      Rise(
        3,
        Align(
          alignment: Alignment.centerRight,
          child: SetupButton(
            '取消',
            onPressed: cancelWaiting,
            style: ActionStyle.ghost,
          ),
        ),
      ),
    ],
  );

  Widget _removing() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Rise(0, Text('正在卸载', style: heading)),
      const Spacer(),
      Rise(
        1,
        ProgressBlock(
          progress: progress,
          task: task,
          colour: wipe ? danger : ink,
        ),
      ),
    ],
  );

  Widget _done() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Rise(0, Text('已卸载', style: heading)),
      const SizedBox(height: 10),
      Rise(
        1,
        Text(
          wipe ? '程序和数据都已删除。感谢使用 MelonBanG。' : '感谢使用 MelonBanG。追番记录还在，随时可以回来。',
          style: intro,
        ),
      ),
      const Spacer(),
      const Rise(
        2,
        Align(
          alignment: Alignment.centerRight,
          child: SetupButton('完成', onPressed: closeWindow),
        ),
      ),
    ],
  );

  Widget _failed() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Rise(0, Text('还有文件没删掉', style: heading)),
      const SizedBox(height: 10),
      const Rise(1, Text('有些文件正被其他程序占用，可以稍后手动删除这些文件夹：', style: intro)),
      const SizedBox(height: 16),
      Rise(
        2,
        Panel(
          child: SelectableText(
            left.join('\n'),
            style: const TextStyle(fontSize: 13, height: 1.6, color: ink),
          ),
        ),
      ),
      const Spacer(),
      Rise(
        3,
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SetupButton(
              '打开文件夹',
              onPressed: () => openLink(left.first),
              style: ActionStyle.ghost,
            ),
            const SizedBox(width: 10),
            const SetupButton('完成', onPressed: closeWindow),
          ],
        ),
      ),
    ],
  );
}

String _size(int bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
    : '${(bytes / (1 << 20)).ceil()} MB';

/// One of the two data choices, drawn as a radio card.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.detail,
    required this.selected,
    required this.colour,
    required this.tint,
    required this.onTap,
  });
  final String title, detail;
  final bool selected;
  final Color colour, tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: selected,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Panel(
          colour: selected ? tint : canvas,
          ring: selected ? colour : null,
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: selected ? colour : const Color(0xffb6c2bd),
                    width: selected ? 5.5 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(detail, style: note),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
