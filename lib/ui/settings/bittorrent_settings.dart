import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/bittorrent_settings.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'settings_page.dart';

/// Words the BT settings search matches.
const bitTorrentKeywords =
    'bt 下载 做种 上传 限速 不限速 限制速度 下载速度 上传速度 同时下载 '
    '启动时继续任务 做种方案 适量分享 停止分享 持续分享 目标分享率 累计分享时间 '
    '同时分享 每任务连接上限 监听端口 dht 节点发现 upnp nat 自动端口映射 ipv6 '
    '仅连接加密用户 恢复推荐值';

/// BT downloading and seeding; its settings show once cache tasks are
/// restored.
SettingsSection downloadsSection({
  required ValueListenable<bool> available,
  required ValueListenable<String?> issue,
  required BitTorrentSettings settings,
  required Future<void> Function(BitTorrentSettings) onSave,
}) => SettingsSection(
  id: 'downloads',
  title: '下载与做种',
  icon: Icons.swap_vert,
  groups: [
    SettingsGroup([
      SettingsItem(
        bitTorrentKeywords,
        ListenableBuilder(
          listenable: Listenable.merge([available, issue]),
          builder: (context, _) => available.value
              ? BitTorrentSettingsPanel(settings: settings, onSave: onSave)
              : DownloadsUnavailable(issue: issue.value),
        ),
      ),
    ]),
  ],
);

/// BT download and sharing settings. Switches, menus and sliders apply at
/// once; a number applies when its field is submitted or left, after
/// validation.
class BitTorrentSettingsPanel extends StatefulWidget {
  const BitTorrentSettingsPanel({
    super.key,
    required this.settings,
    required this.onSave,
  });
  final BitTorrentSettings settings;
  final Future<void> Function(BitTorrentSettings) onSave;
  @override
  State<BitTorrentSettingsPanel> createState() =>
      _BitTorrentSettingsPanelState();
}

class _BitTorrentSettingsPanelState extends State<BitTorrentSettingsPanel> {
  final fields = <String, TextEditingController>{};
  final focusNodes = <String, FocusNode>{};
  final fieldErrors = <String, String>{};
  final limited = <String, bool>{};
  late Map<String, dynamic> draft;
  String? error;
  Future<void> _saving = Future.value();
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
    for (final key in numericKeys) {
      fields[key] = TextEditingController();
      focusNodes[key] = FocusNode()
        ..addListener(() {
          if (!focusNodes[key]!.hasFocus) commit();
        });
    }
    load(widget.settings);
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    for (final node in focusNodes.values) {
      node.dispose();
    }
    super.dispose();
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
      fields[key]!.text = value;
    }
    fieldErrors.clear();
  }

  /// Validates the draft with the typed numbers and saves it when valid.
  void commit() {
    if (!mounted) return;
    final values = {...draft};
    final errors = <String, String>{};
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
        _ => (1 / 1024, 1024, '请输入大于 0、不超过 1024 的速度'),
      };
      if (value == null ||
          !value.isFinite ||
          value < minimum ||
          value > maximum) {
        errors[key] = message;
      } else {
        values[key] = key.endsWith('KiB') ? (value * 1024).round() : value;
      }
    }
    if (draft['seedMode'] == 'limited' &&
        !errors.containsKey('seedRatio') &&
        !errors.containsKey('seedMinutes') &&
        values['seedRatio'] == 0 &&
        values['seedMinutes'] == 0) {
      errors['seedRatio'] = '分享率和分享时间至少一项大于 0';
    }
    setState(() {
      fieldErrors
        ..clear()
        ..addAll(errors);
      error = null;
    });
    if (errors.isNotEmpty) return;
    final settings = BitTorrentSettings.fromJson(values);
    // Saves apply in order, so a later change never lands before an
    // earlier one.
    _saving = _saving.then((_) async {
      try {
        await widget.onSave(settings);
      } catch (_) {
        if (mounted) setState(() => error = '暂时无法保存设置，请重试。');
      }
    });
  }

  void change(VoidCallback update) {
    setState(update);
    commit();
  }

  Widget numberField(String key, {String? unit, String? hint}) => SizedBox(
    width: 220,
    child: TextField(
      controller: fields[key],
      focusNode: focusNodes[key],
      keyboardType: TextInputType.numberWithOptions(
        decimal: key == 'seedRatio' || key.endsWith('KiB'),
      ),
      decoration: InputDecoration(
        suffixText: unit,
        hintText: hint,
        errorText: fieldErrors[key],
        errorMaxLines: 2,
      ),
      onChanged: (_) {
        if (fieldErrors.containsKey(key)) {
          setState(() => fieldErrors.remove(key));
        }
      },
      onSubmitted: (_) => commit(),
    ),
  );

  Widget taskSlider(String key, int maximum) {
    final count = draft[key] as int;
    final value = count == 0 ? maximum + 1 : count;
    return SizedBox(
      width: 260,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          showValueIndicator: ShowValueIndicator.onlyForDiscrete,
          tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Slider(
              min: 1,
              max: maximum + 1.0,
              divisions: maximum,
              value: value.toDouble(),
              label: count == 0 ? '无上限' : '$count',
              semanticFormatterCallback: (value) =>
                  value > maximum ? '无上限' : '${value.round()} 个任务',
              onChanged: (value) => setState(
                () => draft[key] = value > maximum ? 0 : value.round(),
              ),
              onChangeEnd: (_) => commit(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('1', style: Theme.of(context).textTheme.bodySmall),
                  Text('无上限', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget toggle(String key, String title, {String? help}) => SettingRow(
    title: title,
    help: help,
    onTap: () => change(() => draft[key] = !(draft[key] as bool)),
    trailing: Switch(
      value: draft[key] as bool,
      onChanged: (value) => change(() => draft[key] = value),
    ),
  );

  Widget speed(String key, String title) => SettingRow(
    title: title,
    trailing: Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (limited[key]!) numberField(key, unit: 'MiB/s'),
        MelonChoiceMenu<bool>(
          value: limited[key]!,
          options: const {false: '不限速', true: '限制速度'},
          onSelected: (value) => change(() {
            limited[key] = value;
            if (value && (double.tryParse(fields[key]!.text) ?? 0) <= 0) {
              fields[key]!.text = key == 'downloadKiB' ? '10' : '1';
            }
          }),
        ),
      ],
    ),
  );

  Widget caption(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, Gap.lg, 20, Gap.xs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const divider = Divider(height: 1, indent: 20, endIndent: 20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        speed('downloadKiB', '下载速度'),
        divider,
        speed('uploadKiB', '上传速度'),
        divider,
        SettingRow(title: '同时下载', trailing: taskSlider('activeDownloads', 5)),
        divider,
        toggle('resumeOnStartup', '启动时继续任务'),
        caption('分享'),
        SettingRow(
          title: '做种方案',
          help: '把已下载的内容分享给其他用户，推荐开启\n只在应用运行时做种',
          trailing: MelonChoiceMenu<String>(
            value: draft['seedMode'] as String,
            options: const {
              'limited': '适量分享（推荐）',
              'off': '停止分享',
              'unlimited': '持续分享',
            },
            onSelected: (value) => change(() => draft['seedMode'] = value),
          ),
        ),
        if (draft['seedMode'] == 'limited') ...[
          divider,
          SettingRow(
            title: '目标分享率',
            help: '上传量 ÷ 文件大小，0 为不限，最高 1000\n与分享时间任一达到即停止',
            trailing: numberField('seedRatio', hint: '0 表示不限'),
          ),
          divider,
          SettingRow(
            title: '累计分享时间',
            help: '只计实际做种时间，重启不清零，最多 1440 分钟\n与分享率任一达到即停止',
            trailing: numberField('seedMinutes', unit: '分钟', hint: '0 表示不限'),
          ),
        ],
        divider,
        SettingRow(title: '同时分享', trailing: taskSlider('activeSeeds', 3)),
        caption('连接'),
        SettingRow(
          title: '每任务连接上限',
          help: '每个任务 5–500 位用户\n总数随运行中的任务增加',
          trailing: numberField('connectionsPerTask'),
        ),
        divider,
        SettingRow(
          title: '监听端口',
          help: '0 为自动，固定端口 1–65535',
          trailing: numberField('listenPort'),
        ),
        divider,
        toggle('dht', 'DHT 节点发现', help: '帮公共种子找到更多用户\n私有种子按自身规则'),
        divider,
        toggle('upnp', '自动端口映射', help: '用 UPnP / NAT-PMP 接收入站连接'),
        divider,
        toggle('ipv6', 'IPv6'),
        divider,
        toggle('forceEncryption', '仅连接加密用户', help: '默认允许加密，开启后可连接的用户会变少'),
        divider,
        SettingRow(
          title: '恢复推荐值',
          subtitle: error,
          subtitleColor: error == null ? null : coral,
          trailing: TextButton(
            onPressed: () {
              setState(() => load(const BitTorrentSettings()));
              commit();
            },
            child: const Text('恢复推荐值'),
          ),
        ),
      ],
    );
  }
}

/// Shown instead of the BT settings until download tasks are restored.
class DownloadsUnavailable extends StatelessWidget {
  const DownloadsUnavailable({super.key, this.issue});
  final String? issue;

  @override
  Widget build(BuildContext context) => SettingRow(
    leading: issue == null
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.error_outline, color: coral),
    title: issue == null ? '正在恢复缓存任务…' : '缓存任务恢复失败',
    subtitle: issue,
  );
}
