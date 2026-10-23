import 'package:flutter/material.dart';

import '../../core/proxy.dart';
import '../../features/network/connectivity.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import 'settings_page.dart';

SettingsSection networkSection({
  required NetworkProxy? proxy,
  required ConnectivityCheck connectivity,
}) => SettingsSection(
  id: 'network',
  title: '网络',
  icon: Icons.lan_outlined,
  groups: [
    if (proxy != null)
      SettingsGroup([
        SettingsItem(
          '代理 proxy 系统代理 http vpn 翻墙 梯子 代理地址 端口 自定义',
          ListenableBuilder(
            listenable: proxy,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingRow(
                  title: '网络代理',
                  subtitle: proxy.describe(),
                  help:
                      '作用于 Bangumi、资源站、弹幕、PikPak、更新和在线播放\n'
                      'BT 下载与做种不走代理\n'
                      '系统代理只读手动设置的地址，不支持 PAC',
                  trailing: MelonChoiceMenu<ProxyMode>(
                    options: {
                      for (final mode in ProxyMode.values) mode: mode.label,
                    },
                    value: proxy.mode,
                    onSelected: proxy.setMode,
                  ),
                ),
                if (proxy.mode == ProxyMode.custom) ...[
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  _ProxyAddress(proxy: proxy),
                ],
              ],
            ),
          ),
        ),
      ], title: '代理'),
    SettingsGroup([
      SettingsItem(
        '连通性 测试 网络 诊断 延迟 bangumi 资源 弹幕',
        _Connectivity(check: connectivity),
      ),
    ], title: '连通性测试'),
  ],
);

class _ProxyAddress extends StatefulWidget {
  const _ProxyAddress({required this.proxy});
  final NetworkProxy proxy;
  @override
  State<_ProxyAddress> createState() => _ProxyAddressState();
}

class _ProxyAddressState extends State<_ProxyAddress> {
  late final input = TextEditingController(text: widget.proxy.address);
  final focus = FocusNode();
  String? error;
  bool saved = false;

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) save();
    });
  }

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (input.text.trim() == widget.proxy.address && error == null) return;
    try {
      await widget.proxy.setAddress(input.text);
      if (mounted) {
        setState(() {
          error = null;
          saved = true;
        });
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          saved = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SettingRow(
    title: '代理地址',
    subtitle: saved ? '已保存，新的连接会使用这个地址' : null,
    trailing: SizedBox(
      width: 300,
      child: TextField(
        controller: input,
        focusNode: focus,
        decoration: InputDecoration(
          hintText: '127.0.0.1:7890',
          errorText: error,
          errorMaxLines: 2,
        ),
        onChanged: (_) {
          if (saved || error != null) {
            setState(() {
              saved = false;
              error = null;
            });
          }
        },
        onSubmitted: (_) => save(),
      ),
    ),
  );
}

class _Connectivity extends StatelessWidget {
  const _Connectivity({required this.check});
  final ConnectivityCheck check;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: check,
    builder: (context, _) {
      final targets = check.targets;
      final text = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingRow(
            title: '检查各项服务能否连接',
            subtitle: check.proxy == null
                ? null
                : '当前${check.proxy!.describe()}',
            trailing: FilledButton.icon(
              onPressed: check.running ? null : check.runAll,
              icon: check.running
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check, size: 18),
              label: Text(check.running ? '正在测试…' : '开始测试'),
            ),
          ),
          if (check.results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Column(
                children: [
                  for (final target in targets)
                    _ProbeRow(
                      target: target,
                      result: check.results[target.id],
                      style: text.bodySmall,
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _ProbeRow extends StatelessWidget {
  const _ProbeRow({required this.target, required this.result, this.style});
  final ProbeTarget target;
  final ProbeResult? result;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = result;
    final (Widget status, Color? color) = switch (value?.state) {
      null || ProbeState.waiting => (const Text('—'), null),
      ProbeState.running => (
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        null,
      ),
      // Probes hit bare hosts without a token, so 401 or 404 still means the
      // service answered; only the limited codes are worth showing.
      ProbeState.reachable => (
        Text('${value!.elapsed!.inMilliseconds} ms'),
        accentOf(context).accent,
      ),
      ProbeState.limited => (
        Text('${value!.elapsed!.inMilliseconds} ms · HTTP ${value.status}'),
        gold,
      ),
      ProbeState.failed => (Text(value!.error ?? '无法连接'), coral),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Align(
              alignment: Alignment.centerLeft,
              child: MelonBadge(target.group, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Tooltip(
              message: '${target.url}',
              child: Text(
                target.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (color != null) ...[
            Icon(
              value?.state == ProbeState.failed
                  ? Icons.error_outline
                  : value?.state == ProbeState.limited
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline,
              size: 16,
              color: color,
            ),
            const SizedBox(width: Gap.xs),
          ],
          DefaultTextStyle.merge(
            style: style?.copyWith(
              color: color == coral || color == gold ? color : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: status,
          ),
        ],
      ),
    );
  }
}
