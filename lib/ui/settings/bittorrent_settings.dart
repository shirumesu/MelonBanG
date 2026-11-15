import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/bittorrent_settings.dart';
import '../../features/appearance/appearance.dart';
import '../core/action_feedback.dart';
import '../core/byte_units.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'settings_page.dart';

/// Words the BT settings search matches while they wait for cache tasks.
const bitTorrentKeywords =
    'bt 下载 做种 上传 限速 不限速 限制速度 下载速度 上传速度 同时下载 '
    '启动时继续任务 做种方案 适量分享 停止分享 持续分享 目标分享率 累计分享时间 '
    '同时分享 每任务连接上限 监听端口 dht 节点发现 upnp nat 自动端口映射 ipv6 '
    '仅连接加密用户 恢复推荐值';

/// BT downloading and seeding; its settings show once cache tasks are
/// restored, in groups like the other sections, a row each so the search
/// finds one row.
SettingsSection downloadsSection({
  required ValueListenable<bool> available,
  required ValueListenable<String?> issue,
  required BitTorrentSettings settings,
  required Future<void> Function(BitTorrentSettings) onSave,
}) {
  SettingsItem item(String keywords, _FormRowBuilder builder) => SettingsItem(
    'bt $keywords',
    _BitTorrentRow(settings: settings, onSave: onSave, builder: builder),
  );
  return SettingsSection.watching(
    id: 'downloads',
    title: '下载与做种',
    icon: Icons.swap_vert,
    listenable: Listenable.merge([available, issue]),
    groups: () => available.value
        ? [
            SettingsGroup([
              item(
                '下载速度 下载 限速 不限速 限制速度',
                (context, form) => form.speed(context, 'downloadKiB', '下载速度'),
              ),
              item(
                '上传速度 上传 限速 不限速 限制速度',
                (context, form) => form.speed(context, 'uploadKiB', '上传速度'),
              ),
              item(
                '同时下载 任务',
                (context, form) => SettingRow(
                  title: '同时下载',
                  trailing: form.taskSlider(context, 'activeDownloads', 5),
                ),
              ),
              item(
                '启动时继续任务 下载',
                (context, form) => form.toggle('resumeOnStartup', '启动时继续任务'),
              ),
            ], title: '下载'),
            SettingsGroup([
              item(
                '做种 做种方案 分享 适量分享 停止分享 持续分享 目标分享率 分享率 '
                '累计分享时间 分享时间 上传',
                (context, form) => form.seeding(),
              ),
              item(
                '同时分享 做种 任务',
                (context, form) => SettingRow(
                  title: '同时分享',
                  trailing: form.taskSlider(context, 'activeSeeds', 3),
                ),
              ),
            ], title: '分享'),
            SettingsGroup([
              item(
                '每任务连接上限 连接 用户',
                (context, form) => SettingRow(
                  title: '每任务连接上限',
                  help: '每个任务 5–500 位用户\n总数随运行中的任务增加',
                  trailing: form.numberField('connectionsPerTask'),
                ),
              ),
              item(
                '监听端口 端口',
                (context, form) => SettingRow(
                  title: '监听端口',
                  help: '0 为自动，固定端口 1–65535',
                  trailing: form.numberField('listenPort'),
                ),
              ),
              item(
                'dht 节点发现',
                (context, form) => form.toggle(
                  'dht',
                  'DHT 节点发现',
                  help: '帮公共种子找到更多用户\n私有种子按自身规则',
                ),
              ),
              item(
                '自动端口映射 upnp nat 端口',
                (context, form) =>
                    form.toggle('upnp', '自动端口映射', help: '让路由器自动转发端口，可连接更多用户'),
              ),
              item('ipv6', (context, form) => form.toggle('ipv6', 'IPv6')),
              item(
                '仅连接加密用户 加密',
                (context, form) => form.toggle(
                  'forceEncryption',
                  '仅连接加密用户',
                  help: '开启后可连接的用户会变少',
                ),
              ),
              item('恢复推荐值 恢复 默认 重置', (context, form) => form.reset(context)),
            ], title: '连接'),
          ]
        : [
            SettingsGroup([
              SettingsItem(
                bitTorrentKeywords,
                DownloadsUnavailable(issue: issue.value),
              ),
            ]),
          ],
  );
}

typedef _FormRowBuilder = Widget Function(
  BuildContext context,
  _BitTorrentForm form,
);

/// One row of the BT settings, editing the form the rows on the page share.
class _BitTorrentRow extends StatefulWidget {
  const _BitTorrentRow({
    required this.settings,
    required this.onSave,
    required this.builder,
  });
  final BitTorrentSettings settings;
  final Future<void> Function(BitTorrentSettings) onSave;
  final _FormRowBuilder builder;

  @override
  State<_BitTorrentRow> createState() => _BitTorrentRowState();
}

class _BitTorrentRowState extends State<_BitTorrentRow> {
  late final form = _BitTorrentForm.acquire(widget.settings, widget.onSave);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    form.useUnits(ByteUnitsScope.of(context));
  }

  @override
  void dispose() {
    form.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: form,
    builder: (context, _) => widget.builder(context, form),
  );
}

/// The BT download and sharing settings being edited, shared by their rows
/// while any of them shows. Switches, menus and sliders apply at once; a
/// number applies when its field is submitted or left, after validation.
class _BitTorrentForm extends ChangeNotifier {
  _BitTorrentForm._(BitTorrentSettings settings, this.onSave) {
    for (final key in numericKeys) {
      fields[key] = TextEditingController();
      focusNodes[key] = FocusNode()
        ..addListener(() {
          if (!focusNodes[key]!.hasFocus) commit();
        });
    }
    load(settings);
  }

  static _BitTorrentForm? _shared;
  static int _users = 0;

  /// The settings the page last handed a form, and what forms saved since:
  /// a form made again before the page is rebuilt, such as when the search
  /// brings the rows back, starts from what was saved, not the older copy.
  static BitTorrentSettings? _seen, _saved;

  static _BitTorrentForm acquire(
    BitTorrentSettings settings,
    Future<void> Function(BitTorrentSettings) onSave,
  ) {
    _users++;
    if (!identical(settings, _seen)) {
      _seen = settings;
      _saved = null;
    }
    return _shared ??= _BitTorrentForm._(_saved ?? settings, onSave);
  }

  /// When the last row goes, such as on leaving settings, a number typed
  /// but not yet committed is saved when valid.
  void release() {
    if (--_users > 0) return;
    _shared = null;
    final (:values, :errors) = _check();
    if (errors.isEmpty && !mapEquals(values, draft)) _save(values);
    _disposed = true;
    dispose();
  }

  final Future<void> Function(BitTorrentSettings) onSave;
  final fields = <String, TextEditingController>{};
  final focusNodes = <String, FocusNode>{};
  final fieldErrors = <String, String>{};
  final limited = <String, bool>{};
  late Map<String, dynamic> draft;
  String? error;
  bool _disposed = false;
  Future<void> _saving = Future.value();
  static const numericKeys = [
    'downloadKiB',
    'uploadKiB',
    'seedRatio',
    'seedMinutes',
    'connectionsPerTask',
    'listenPort',
  ];

  /// Speeds are typed in the megabytes the app shows: MB or MiB.
  ByteUnits units = ByteUnits.binary;
  int get _mega => units.base * units.base;

  void useUnits(ByteUnits next) {
    if (next == units) return;
    units = next;
    for (final key in numericKeys.where((key) => key.endsWith('KiB'))) {
      if (limited[key] == true) fields[key]!.text = _speed(draft[key] as int);
    }
  }

  /// A limit stored in KiB/s, in [units]' megabytes.
  String _speed(int kib) =>
      double.parse((kib * 1024 / _mega).toStringAsFixed(2))
          .toString()
          .replaceFirst(RegExp(r'\.0$'), '');

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

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void load(BitTorrentSettings settings) {
    draft = settings.toJson();
    for (final key in numericKeys) {
      var value = '${draft[key]}';
      if (key.endsWith('KiB')) {
        limited[key] = (draft[key] as int) > 0;
        value = _speed(draft[key] as int);
      }
      fields[key]!.text = value;
    }
    fieldErrors.clear();
  }

  /// Validates the draft with the typed numbers and saves it when valid.
  void commit() {
    if (_disposed) return;
    final (:values, :errors) = _check();
    fieldErrors
      ..clear()
      ..addAll(errors);
    error = null;
    _changed();
    if (errors.isEmpty) _save(values);
  }

  /// The draft with the typed numbers, and the fields whose numbers are
  /// out of range.
  ({Map<String, dynamic> values, Map<String, String> errors}) _check() {
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
        'seedRatio' => (0, 1000, '请输入 0–1000'),
        'seedMinutes' => (0, 1440, '请输入 0–1440 分钟'),
        'connectionsPerTask' => (5, 500, '请输入 5–500 个连接'),
        'listenPort' => (0, 65535, '请输入 0–65535'),
        _ => (1 / 1024, 1024, '请输入大于 0、不超过 1024 的速度'),
      };
      if (value == null ||
          !value.isFinite ||
          value < minimum ||
          value > maximum) {
        errors[key] = message;
      } else {
        values[key] = key.endsWith('KiB')
            ? math.max(1, (value * _mega / 1024).round())
            : value;
      }
    }
    if (draft['seedMode'] == 'limited' &&
        !errors.containsKey('seedRatio') &&
        !errors.containsKey('seedMinutes') &&
        values['seedRatio'] == 0 &&
        values['seedMinutes'] == 0) {
      errors['seedRatio'] = '分享率和分享时间至少一项大于 0';
    }
    return (values: values, errors: errors);
  }

  void _save(Map<String, dynamic> values) {
    // Typed numbers join the draft, which a change of byte units shows
    // again and the next commit starts from.
    draft = values;
    final settings = BitTorrentSettings.fromJson(values);
    _saved = settings;
    // Saves apply in order, so a later change never lands before an
    // earlier one.
    _saving = _saving.then((_) async {
      try {
        await onSave(settings);
      } catch (_) {
        error = '暂时无法保存设置，请重试';
        _changed();
      }
    });
  }

  void change(VoidCallback update) {
    update();
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
        if (fieldErrors.remove(key) != null) _changed();
      },
      onSubmitted: (_) => commit(),
    ),
  );

  Widget taskSlider(BuildContext context, String key, int maximum) {
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
              onChanged: (value) {
                draft[key] = value > maximum ? 0 : value.round();
                _changed();
              },
              onChangeEnd: (_) => commit(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
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

  Widget toggle(String key, String title, {String? help}) => SettingSwitch(
    title: title,
    help: help,
    value: draft[key] as bool,
    onChanged: (value) => change(() => draft[key] = value),
  );

  Widget speed(BuildContext context, String key, String title) => SettingRow(
    title: title,
    trailing: Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (limited[key]!) numberField(key, unit: '${units.names[1]}/s'),
        SizedBox(
          width: 180,
          child: MelonSegmentedControl<bool>(
            options: const {false: '不限速', true: '限制速度'},
            value: limited[key]!,
            onChanged: (value) => change(() {
              limited[key] = value;
              if (value && (double.tryParse(fields[key]!.text) ?? 0) <= 0) {
                fields[key]!.text = key == 'downloadKiB' ? '10' : '1';
              }
            }),
          ),
        ),
      ],
    ),
  );

  /// The seeding plan, with its targets when it stops by itself.
  Widget seeding() {
    const divider = Divider(height: 1, indent: 20, endIndent: 20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            help: '上传量 ÷ 文件大小，最高 1000\n与分享时间任一达到即停止',
            trailing: numberField('seedRatio', hint: '0 表示不限'),
          ),
          divider,
          SettingRow(
            title: '累计分享时间',
            help: '只计实际做种时间，重启不清零，最多 1440 分钟\n与分享率任一达到即停止',
            trailing: numberField('seedMinutes', unit: '分钟', hint: '0 表示不限'),
          ),
        ],
      ],
    );
  }

  Widget reset(BuildContext context) => SettingRow(
    title: '恢复推荐值',
    subtitle: error,
    subtitleColor: error == null ? null : Theme.of(context).colorScheme.error,
    trailing: TextButton(
      onPressed: () {
        final previous = BitTorrentSettings.fromJson({...draft});
        load(const BitTorrentSettings());
        commit();
        showMessage(
          ScaffoldMessenger.maybeOf(context),
          '已恢复推荐值',
          actionLabel: '撤销',
          onAction: () {
            if (_disposed) return;
            load(previous);
            commit();
          },
        );
      },
      child: const Text('恢复'),
    ),
  );
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
        : Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
    title: issue == null ? '正在恢复缓存任务…' : '缓存任务恢复失败',
    subtitle: issue,
  );
}
