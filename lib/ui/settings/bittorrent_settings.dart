import 'package:flutter/material.dart';

import '../../data/bittorrent_settings.dart';
import '../../data/downloads.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';

class BitTorrentSettingsPanel extends StatefulWidget {
  const BitTorrentSettingsPanel({super.key, required this.downloads});
  final DownloadRepository downloads;
  @override
  State<BitTorrentSettingsPanel> createState() =>
      _BitTorrentSettingsPanelState();
}

class _BitTorrentSettingsPanelState extends State<BitTorrentSettingsPanel> {
  final fields = <String, TextEditingController>{};
  final limited = <String, bool>{};
  final fieldKeys = <String, GlobalKey>{};
  final focusNodes = <String, FocusNode>{};
  final fieldErrors = <String, String>{};
  final advancedController = ExpansibleController();
  late Map<String, dynamic> draft;
  String? error;
  bool saving = false, saved = false;
  static const numericKeys = [
    'downloadKiB',
    'uploadKiB',
    'seedRatio',
    'seedMinutes',
    'connectionsPerTask',
    'listenPort',
  ];

  @override
  void initState() {
    super.initState();
    load(widget.downloads.settings);
  }

  void load(BitTorrentSettings settings) {
    draft = settings.toJson();
    for (final key in numericKeys) {
      var value = '${draft[key]}';
      if (key.endsWith('KiB')) {
        limited[key] = (draft[key] as int) > 0;
        value = ((draft[key] as int) / 1024).toString().replaceFirst(
          RegExp(r'\.0$'),
          '',
        );
      }
      (fields[key] ??= TextEditingController()).text = value;
    }
    saved = false;
    fieldErrors.clear();
  }

  void change(VoidCallback update) => setState(() {
    update();
    saved = false;
  });

  Future<void> save() async {
    final values = {...draft};
    fieldErrors.clear();
    for (final key in numericKeys) {
      if (draft['seedMode'] != 'limited' &&
          ['seedRatio', 'seedMinutes'].contains(key)) {
        continue;
      }
      if (key.endsWith('KiB') && limited[key] != true) {
        values[key] = 0;
        continue;
      }
      final text = fields[key]!.text.trim();
      final value = key == 'seedRatio' || key.endsWith('KiB')
          ? double.tryParse(text)
          : int.tryParse(text);
      final (minimum, maximum, message) = switch (key) {
        'seedRatio' => (0, 1000, '请输入 0–1000；0 表示不限'),
        'seedMinutes' => (0, 1440, '请输入 0–1440 分钟；0 表示不限'),
        'connectionsPerTask' => (5, 500, '请输入 5–500 个连接'),
        'listenPort' => (0, 65535, '请输入 0–65535；0 表示自动选择'),
        _ => (1 / 1024, 1024, '请输入大于 0、不超过 1024 MiB/s 的速度'),
      };
      if (value == null ||
          !value.isFinite ||
          value < minimum ||
          value > maximum) {
        fieldErrors[key] = message;
      } else {
        values[key] = key.endsWith('KiB') ? (value * 1024).round() : value;
      }
    }
    if (draft['seedMode'] == 'limited' &&
        values['seedRatio'] == 0 &&
        values['seedMinutes'] == 0) {
      fieldErrors['seedRatio'] = '请设置分享率或分享时间，至少一项大于 0';
    }
    if (fieldErrors.isNotEmpty) {
      setState(() {
        error = null;
        saved = false;
      });
      final key = fieldErrors.keys.first;
      if (!key.endsWith('KiB')) advancedController.expand();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      focusNodes[key]?.requestFocus();
      // Wait for the expanding section before locating its final position.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final target = fieldKeys[key]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: .35,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
        );
      }
      return;
    }
    setState(() {
      saving = true;
      error = null;
      saved = false;
    });
    try {
      final settings = BitTorrentSettings.fromJson(values);
      settings.validate();
      await widget.downloads.saveSettings(settings);
      if (mounted) setState(() => saved = true);
    } catch (_) {
      if (mounted) setState(() => error = '暂时无法保存设置，请重试。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget numberField(String key, String label, {String? unit, String? hint}) =>
      SizedBox(
        key: fieldKeys.putIfAbsent(key, GlobalKey.new),
        child: TextField(
          key: PageStorageKey('bittorrent-field:$key'),
          controller: fields[key],
          focusNode: focusNodes.putIfAbsent(key, FocusNode.new),
          enabled: !saving,
          keyboardType: TextInputType.numberWithOptions(
            decimal: key == 'seedRatio' || key.endsWith('KiB'),
          ),
          decoration: InputDecoration(
            suffixText: unit,
            hintText: label,
            helperText: hint,
            errorText: fieldErrors[key],
            errorMaxLines: 2,
          ),
          onChanged: (_) => change(() {
            fieldErrors.remove(key);
          }),
        ),
      );

  Widget taskSlider(String key, int maximum) {
    final count = draft[key] as int;
    final value = count == 0 ? maximum + 1 : count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(count == 0 ? '无上限' : '$count 个任务', textAlign: TextAlign.end),
        Slider(
          key: ValueKey('bittorrent-slider:$key'),
          min: 1,
          max: maximum + 1.0,
          divisions: maximum,
          value: value.toDouble(),
          label: count == 0 ? '无上限' : '$count 个任务',
          semanticFormatterCallback: (value) =>
              value > maximum ? '无上限' : '${value.round()} 个任务',
          onChanged: saving
              ? null
              : (value) => change(() {
                  draft[key] = value > maximum ? 0 : value.round();
                }),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: 20,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i <= maximum; i++)
                    Positioned(
                      left: constraints.maxWidth * i / maximum - 24,
                      width: 48,
                      child: Text(
                        i == maximum ? '无上限' : '${i + 1}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget row(String title, Widget control, {String? help, String? note}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final label = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium!
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (help != null) ...[
                      const SizedBox(width: 4),
                      _HelpHint(message: help),
                    ],
                  ],
                ),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text(note, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            );
            if (constraints.maxWidth < 620) {
              return SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    const SizedBox(height: 12),
                    SizedBox(width: 260, child: control),
                  ],
                ),
              );
            }
            return Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 24),
                SizedBox(width: 260, child: control),
              ],
            );
          },
        ),
      );

  Widget toggle(String key, String title, {String? help, String? note}) => row(
    title,
    Align(
      alignment: Alignment.centerRight,
      child: Switch(
        key: ValueKey('bittorrent-toggle:$key'),
        value: draft[key] as bool,
        onChanged: saving ? null : (value) => change(() => draft[key] = value),
      ),
    ),
    help: help,
    note: note,
  );

  Widget speed(String key, String title) => row(
    title,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MelonChoiceMenu<bool>(
          value: limited[key]!,
          options: const {false: '不限速', true: '限制速度'},
          onSelected: saving
              ? null
              : (value) => change(() {
                  limited[key] = value;
                  if (value && (double.tryParse(fields[key]!.text) ?? 0) <= 0) {
                    fields[key]!.text = key == 'downloadKiB' ? '10' : '1';
                  }
                }),
        ),
        if (limited[key]!) ...[
          const SizedBox(height: 8),
          numberField(key, title, unit: 'MiB/s'),
        ],
      ],
    ),
  );

  List<Widget> separated(List<Widget> children) => [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) const Divider(height: 1),
      children[i],
    ],
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('控制传输速度，以及下载完成后如何分享。'),
      const SizedBox(height: 16),
      MelonPanel(
        child: Column(
          children: separated([
            speed('downloadKiB', '下载速度'),
            speed('uploadKiB', '上传速度'),
            row('同时下载', taskSlider('activeDownloads', 5)),
            toggle('resumeOnStartup', '启动时继续任务', note: '关闭后，重新打开应用时任务保持暂停。'),
            row(
              '做种',
              MelonChoiceMenu<String>(
                value: draft['seedMode'] as String,
                options: const {
                  'limited': '适量分享（推荐）',
                  'off': '停止分享',
                  'unlimited': '持续分享',
                },
                onSelected: saving
                    ? null
                    : (value) => change(() => draft['seedMode'] = value),
              ),
              help: '将已下载的内容上传给其他用户，推荐启用维护 BT 网络社区；做种只会在应用运行时进行。',
            ),
          ]),
        ),
      ),
      const SizedBox(height: 20),
      Card(
        child: ExpansionTile(
          key: const PageStorageKey('bittorrent-advanced'),
          controller: advancedController,
          title: Text('高级设置', style: Theme.of(context).textTheme.titleSmall),
          subtitle: const Text('分享条件、队列与网络连接'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          shape: const RoundedRectangleBorder(borderRadius: panelBorderRadius),
          collapsedShape: const RoundedRectangleBorder(
            borderRadius: panelBorderRadius,
          ),
          children: separated([
            if (draft['seedMode'] == 'limited') ...[
              row(
                '目标分享率',
                numberField('seedRatio', '目标分享率', hint: '0 表示不限'),
                help: '累计上传量 ÷ 文件总量。0 表示不限，最高 1000；与做种时间任一条件达到即停止。',
              ),
              row(
                '累计分享时间',
                numberField(
                  'seedMinutes',
                  '累计分享时间',
                  unit: '分钟',
                  hint: '0 表示不限，最多 1440 分钟（1 天）',
                ),
                help: '仅计算实际做种时间，重启不清零。达到分享率或累计时间任一条件即停止。',
              ),
            ],
            row('同时分享', taskSlider('activeSeeds', 3)),
            row(
              '每任务连接上限',
              numberField('connectionsPerTask', '连接数'),
              help: '每个下载或做种任务可连接 5–500 位用户。总连接数随实际运行任务数增加，仍受系统可用资源限制。',
            ),
            row(
              '监听端口',
              numberField('listenPort', '监听端口'),
              help: '0 表示自动选择；固定端口范围 1–65535。',
            ),
            toggle('dht', 'DHT 节点发现', help: '帮助公共种子发现其他用户；私有种子遵循自身限制。'),
            toggle('upnp', '自动端口映射', help: '通过 UPnP / NAT-PMP 尝试接收入站连接。'),
            toggle('ipv6', 'IPv6'),
            toggle(
              'forceEncryption',
              '仅连接加密用户',
              help: '默认允许协商加密；强制开启可能减少可连接用户。',
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '保存后应用于现有任务，手动暂停的任务保持暂停。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: saving ? null : save,
            icon: Icon(saved ? Icons.check : Icons.save_outlined, size: 18),
            label: Text(
              saving
                  ? '正在保存…'
                  : saved
                  ? '已保存并应用'
                  : '保存并应用',
            ),
          ),
          TextButton(
            onPressed: saving
                ? null
                : () => setState(() {
                    load(const BitTorrentSettings());
                    error = null;
                  }),
            child: const Text('恢复推荐值'),
          ),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    for (final node in focusNodes.values) {
      node.dispose();
    }
    advancedController.dispose();
    super.dispose();
  }
}

class _HelpHint extends StatefulWidget {
  const _HelpHint({required this.message});
  final String message;
  @override
  State<_HelpHint> createState() => _HelpHintState();
}

class _HelpHintState extends State<_HelpHint> {
  final tooltip = GlobalKey<TooltipState>();
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      key: tooltip,
      message: widget.message,
      child: IconButton(
        onPressed: () => tooltip.currentState?.ensureTooltipVisible(),
        icon: const Icon(Icons.help_outline_rounded),
        iconSize: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
