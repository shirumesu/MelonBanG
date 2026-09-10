import 'package:flutter/material.dart';

import '../../data/bittorrent_settings.dart';
import '../../data/downloads.dart';
import '../core/page_widgets.dart';

class BitTorrentSettingsPanel extends StatefulWidget {
  const BitTorrentSettingsPanel({super.key, required this.downloads});
  final DownloadRepository downloads;

  @override
  State<BitTorrentSettingsPanel> createState() =>
      _BitTorrentSettingsPanelState();
}

class _BitTorrentSettingsPanelState extends State<BitTorrentSettingsPanel> {
  final fields = <String, TextEditingController>{};
  late Map<String, dynamic> draft;
  String? error;
  bool saving = false, saved = false;

  @override
  void initState() {
    super.initState();
    load(widget.downloads.settings);
  }

  void load(BitTorrentSettings settings) {
    draft = settings.toJson();
    for (final key in labels.keys) {
      (fields[key] ??= TextEditingController()).text = '${draft[key]}';
    }
    saved = false;
  }

  static const labels = {
    'seedRatio': '目标分享率（0 = 不限制，最高 1000）',
    'seedMinutes': '累计做种分钟（0 = 不限制，最高 525600）',
    'downloadKiB': '下载限速 KiB/s（0 = 不限速）',
    'uploadKiB': '上传限速 KiB/s（0 = 不限速）',
    'activeDownloads': '同时下载任务（1–20）',
    'activeSeeds': '同时做种任务（1–20）',
    'connectionsPerTask': '每任务连接上限（5–500）',
    'listenPort': '监听端口（0 = 自动，1–65535 = 固定）',
  };

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
      saved = false;
    });
    try {
      final values = {...draft};
      for (final entry in fields.entries) {
        if (draft['seedMode'] != 'limited' &&
            ['seedRatio', 'seedMinutes'].contains(entry.key)) {
          continue;
        }
        final text = entry.value.text.trim();
        values[entry.key] = entry.key == 'seedRatio'
            ? double.parse(text)
            : int.parse(text);
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

  Widget field(String key) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: fields[key],
      enabled: !saving,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: labels[key]),
      onChanged: (_) => setState(() => saved = false),
    ),
  );

  Widget toggle(String key, String title, String subtitle) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    value: draft[key] as bool,
    onChanged: saving
        ? null
        : (v) => setState(() {
            draft[key] = v;
            saved = false;
          }),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('下载完成后可继续上传给其他用户。做种只在应用运行时进行，退出后停止；重新打开会保留累计分享量、做种时间及手动暂停状态。'),
      const SectionTitle(title: '完成后的做种'),
      MelonPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: draft['seedMode'] as String,
              key: ValueKey(draft['seedMode']),
              decoration: const InputDecoration(labelText: '做种模式'),
              items: const [
                DropdownMenuItem(value: 'off', child: Text('下载完成后停止')),
                DropdownMenuItem(value: 'limited', child: Text('限量做种（推荐）')),
                DropdownMenuItem(
                  value: 'unlimited',
                  child: Text('持续做种，直到手动暂停'),
                ),
              ],
              onChanged: saving
                  ? null
                  : (v) => setState(() {
                      draft['seedMode'] = v!;
                      saved = false;
                    }),
            ),
            const SizedBox(height: 16),
            if (draft['seedMode'] == 'limited') ...[
              field('seedRatio'),
              field('seedMinutes'),
              const Text(
                '任一条件达到即停止做种并保留文件。分享率 = 累计上传量 ÷ 文件总量；做种时间只计算实际运行时间，重启不清零。',
              ),
            ],
            if (draft['seedMode'] == 'off')
              const Text('停止完成任务的连接；下载过程中仍会向其他用户上传。'),
            const SizedBox(height: 8),
            const Text('保存后重新评估现有任务；放宽停止条件可恢复自动做种，手动暂停的任务保持暂停。'),
          ],
        ),
      ),
      const SectionTitle(title: '速度与队列'),
      MelonPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            field('downloadKiB'),
            field('uploadKiB'),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('限速为全部任务合计，1024 KiB/s = 1 MiB/s；最大可设 1048576 KiB/s。'),
            ),
            field('activeDownloads'),
            field('activeSeeds'),
            toggle('resumeOnStartup', '启动时继续任务', '关闭后，重启时所有任务保持暂停，可手动继续。'),
          ],
        ),
      ),
      const SectionTitle(title: '连接'),
      MelonPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            field('connectionsPerTask'),
            field('listenPort'),
            Text('全局连接上限为每任务上限的 4 倍，最低 200。缓存目录：${widget.downloads.directory}'),
            toggle('dht', 'DHT 节点发现', '帮助公共种子发现用户；私有种子遵循其自身限制。'),
            toggle('upnp', '自动端口映射', '通过 UPnP / NAT-PMP 尝试接收入站连接。'),
            toggle('ipv6', 'IPv6', '同时监听 IPv4 和 IPv6。'),
            toggle('forceEncryption', '仅连接加密用户', '默认允许协商加密；强制开启可能减少可连接用户。'),
          ],
        ),
      ),
      const SizedBox(height: 20),
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
