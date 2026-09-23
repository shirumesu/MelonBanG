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
  late Map<String, dynamic> draft;
  String? error;
  bool saving = false, saved = false;
  static const numericKeys = [
    'seedRatio',
    'seedMinutes',
    'downloadKiB',
    'uploadKiB',
    'activeDownloads',
    'activeSeeds',
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
  }

  void change(VoidCallback update) => setState(() {
    update();
    saved = false;
  });

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
      saved = false;
    });
    try {
      final values = {...draft};
      for (final entry in fields.entries) {
        final key = entry.key;
        if (draft['seedMode'] != 'limited' &&
            ['seedRatio', 'seedMinutes'].contains(key)) {
          continue;
        }
        final text = entry.value.text.trim();
        if (key.endsWith('KiB')) {
          if (limited[key] != true) {
            values[key] = 0;
            continue;
          }
          final speed = double.parse(text);
          if (!speed.isFinite ||
              speed <= 0 ||
              speed > 1024 ||
              (speed * 1024).round() < 1) {
            throw const FormatException('限速请输入大于 0、不超过 1024 MiB/s 的数值');
          }
          values[key] = (speed * 1024).round();
        } else {
          values[key] = key == 'seedRatio'
              ? double.parse(text)
              : int.parse(text);
        }
      }
      final settings = BitTorrentSettings.fromJson(values);
      settings.validate();
      await widget.downloads.saveSettings(settings);
      if (mounted) setState(() => saved = true);
    } catch (e) {
      if (mounted) setState(() => error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget numberField(String key, String label, {String? unit}) => TextField(
    key: PageStorageKey('bittorrent-field:$key'),
    controller: fields[key],
    enabled: !saving,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(suffixText: unit, hintText: label),
    onChanged: (_) => change(() {}),
  );

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
    help: '所有任务合计的速度上限。1 MiB/s = 1024 KiB/s；不限速会使用当前可用带宽。',
    note: key == 'downloadKiB' ? '正在观看的视频优先下载' : null,
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
            row(
              '同时下载',
              MelonChoiceMenu<int>(
                value: int.tryParse(fields['activeDownloads']!.text) ?? 3,
                options: {for (var i = 1; i <= 20; i++) i: '$i 个任务'},
                onSelected: saving
                    ? null
                    : (value) => change(
                        () => fields['activeDownloads']!.text = '$value',
                      ),
              ),
              help: '超过数量的任务会排队。边下边看仍遵守这个上限。',
            ),
            toggle('resumeOnStartup', '启动时继续任务', note: '关闭后，重新打开应用时任务保持暂停。'),
            row(
              '下载完成后',
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
              help: '分享也称做种，即把已下载的内容上传给其他用户。只在应用运行时进行。',
              note: switch (draft['seedMode']) {
                'limited' =>
                  '达到分享率 ${fields['seedRatio']!.text} 或 ${fields['seedMinutes']!.text} 分钟即停止（0 表示不限）。',
                'off' => '下载完成后停止连接，文件保留。',
                _ => '持续上传，直到手动停止或退出应用。',
              },
            ),
          ]),
        ),
      ),
      const SizedBox(height: 20),
      Card(
        child: ExpansionTile(
          key: const PageStorageKey('bittorrent-advanced'),
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
                numberField('seedRatio', '目标分享率'),
                help: '累计上传量 ÷ 文件总量。0 表示不限，最高 1000；与做种时间任一条件达到即停止。',
              ),
              row(
                '累计分享时间',
                numberField('seedMinutes', '累计分享时间', unit: '分钟'),
                help: '仅计算实际做种时间，重启不清零。0 表示不限，最高 525600 分钟。',
              ),
            ],
            row(
              '同时分享',
              numberField('activeSeeds', '同时分享', unit: '个任务'),
              help: '最多同时做种的任务数，范围 1–20。',
            ),
            row(
              '每任务连接上限',
              numberField('connectionsPerTask', '连接数'),
              help: '范围 5–500。全局连接上限为此值的 4 倍，最低 200。',
            ),
            row(
              '监听端口',
              numberField('listenPort', '监听端口'),
              help: '0 表示自动选择；固定端口范围 1–65535。',
            ),
            toggle('dht', 'DHT 节点发现', help: '帮助公共种子发现其他用户；私有种子遵循自身限制。'),
            toggle('upnp', '自动端口映射', help: '通过 UPnP / NAT-PMP 尝试接收入站连接。'),
            toggle('ipv6', 'IPv6', help: '同时监听 IPv4 和 IPv6。'),
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
    super.dispose();
  }
}

class _HelpHint extends StatelessWidget {
  const _HelpHint({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final tooltip = GlobalKey<TooltipState>();
    return Tooltip(
      key: tooltip,
      message: message,
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
