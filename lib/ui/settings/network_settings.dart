import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/notices.dart';
import '../../core/proxy.dart';
import '../../features/network/connectivity.dart';
import '../core/motion.dart';
import '../core/page_widgets.dart';
import '../core/selection_controls.dart';
import '../core/theme.dart';
import '../core/tone.dart';
import 'setting_rows.dart';

SettingsSection networkSection({
  required NetworkProxy proxy,
  required ConnectivityCheck connectivity,
}) => SettingsSection(
  id: 'network',
  title: '网络',
  icon: Icons.lan_outlined,
  groups: [
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
                    '自动检测：有系统代理就用系统代理；没有时，检测到 TUN 模式就直接连接，'
                    '否则找 Clash、v2rayN 等软件常用的本机端口（7890、7897、10808 等）\n'
                    '作用于 Bangumi、资源站、弹幕、PikPak、更新和在线播放\n'
                    'BT 下载与做种不走这里的代理\n'
                    'TUN 模式会接管所有流量，BT 没速度时给 MelonBanG 加直连规则\n'
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
      SettingsItem(
        '直连 分流 记住 网站 自动切换 连不上 回退',
        ListenableBuilder(
          listenable: proxy.routes,
          builder: (context, _) {
            final sites = proxy.routes.direct.keys.toList().reversed.toList();
            return SettingRow(
              title: '改为直连的网站',
              subtitle: sites.isEmpty
                  ? '暂无'
                  : sites.length <= 4
                  ? sites.join('、')
                  : '${sites.take(4).join('、')} 等 ${sites.length} 个',
              help:
                  '使用代理时，请求默认经由代理，由代理软件自己的规则分流\n'
                  '某个网站经代理连不上、直连能连上时，自动改为直连并记在这台设备上；'
                  '之后直连连不上时会再试代理\n'
                  '代理软件没在运行时临时直连，不会记住\n'
                  '5 秒内连接没建立视为连不上',
              trailing: TextButton(
                onPressed: sites.isEmpty ? null : proxy.routes.clear,
                child: const Text('清空'),
              ),
            );
          },
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

  /// An address typed but not yet saved, when the row goes before the
  /// field loses focus, such as on leaving settings: saved when valid.
  @override
  void deactivate() {
    if (input.text.trim() != widget.proxy.address) {
      // An invalid one is dropped: the field that would say why is gone.
      unawaited(
        widget.proxy
            .setAddress(input.text)
            .catchError((Object _) {}, test: (e) => e is FormatException),
      );
    }
    super.deactivate();
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
    subtitle: saved ? '已保存' : null,
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

/// The connectivity test: a summary that filters the results, then one row
/// per group, open when the group has a problem or is opened by hand.
class _Connectivity extends StatefulWidget {
  const _Connectivity({required this.check});
  final ConnectivityCheck check;

  @override
  State<_Connectivity> createState() => _ConnectivityState();
}

enum _ProbeFilter { all, problems }

class _ConnectivityState extends State<_Connectivity> {
  _ProbeFilter _filter = _ProbeFilter.all;

  /// Groups opened or closed by hand; the rest follow their results.
  final _toggled = <String, bool>{};
  bool _wasRunning = false;

  ConnectivityCheck get check => widget.check;

  static bool _problem(ProbeResult? result) =>
      result?.state == ProbeState.failed || result?.state == ProbeState.limited;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: check,
    builder: (context, _) {
      final targets = check.targets;
      final results = check.results;
      // A finished test with problems shows only those first.
      if (_wasRunning && !check.running) {
        _filter = targets.any((t) => _problem(results[t.id]))
            ? _ProbeFilter.problems
            : _ProbeFilter.all;
        _toggled.clear();
      }
      _wasRunning = check.running;
      final done = targets
          .where(
            (t) => switch (results[t.id]?.state) {
              ProbeState.reachable ||
              ProbeState.limited ||
              ProbeState.failed => true,
              _ => false,
            },
          )
          .length;
      int count(ProbeState state) =>
          targets.where((t) => results[t.id]?.state == state).length;
      final route = check.proxy.describe();
      final failed = count(ProbeState.failed);
      final limited = count(ProbeState.limited);
      final groups = <String, List<ProbeTarget>>{};
      for (final target in targets) {
        if (_filter == _ProbeFilter.problems && !_problem(results[target.id])) {
          continue;
        }
        (groups[target.group] ??= []).add(target);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingRow(
            title: '检查各项服务能否连接',
            // Only a proxy in use is worth a line; the proxy row above says
            // the rest.
            subtitle: route.startsWith('经由') ? '当前$route' : null,
            trailing: FilledButton.icon(
              onPressed: check.running ? null : check.runAll,
              icon: check.running
                  ? const BusyIndicator()
                  : const Icon(Icons.network_check, size: 18),
              label: Text(
                check.running
                    ? '正在测试 $done/${targets.length}'
                    : results.isEmpty
                    ? '开始测试'
                    : '重新测试',
              ),
            ),
          ),
          if (results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ChoiceChip(
                        label: Text('全部 ${targets.length}'),
                        selected: _filter == _ProbeFilter.all,
                        onSelected: (_) =>
                            setState(() => _filter = _ProbeFilter.all),
                      ),
                      ChoiceChip(
                        label: Text('有问题 ${failed + limited}'),
                        selected: _filter == _ProbeFilter.problems,
                        onSelected: failed + limited == 0
                            ? null
                            : (_) => setState(
                                () => _filter = _ProbeFilter.problems,
                              ),
                      ),
                      const SizedBox(width: Gap.xs),
                      _Tally(
                        tone: NoticeTone.done,
                        count: count(ProbeState.reachable),
                        label: '正常',
                      ),
                      if (limited > 0)
                        _Tally(
                          tone: NoticeTone.warning,
                          count: limited,
                          label: '受限',
                        ),
                      if (failed > 0)
                        _Tally(
                          tone: NoticeTone.failed,
                          count: failed,
                          label: '失败',
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  // Grows with its open groups: the settings page scrolls,
                  // so opened results are never clipped into a nested list.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: insetSurface(context),
                      borderRadius: controlBorderRadius,
                    ),
                    child: groups.isEmpty
                        ? const EmptyState.compact(text: '没有需要关注的服务')
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: Gap.xs,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final MapEntry(key: name, value: members)
                                    in groups.entries)
                                  ..._group(context, name, members, results),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );

  List<Widget> _group(
    BuildContext context,
    String name,
    List<ProbeTarget> members,
    Map<String, ProbeResult> results,
  ) {
    final problems = members.where((t) => _problem(results[t.id])).length;
    final failing = members.any(
      (t) => results[t.id]?.state == ProbeState.failed,
    );
    final busy = members.any((t) => results[t.id]?.state == ProbeState.running);
    final open =
        _toggled[name] ?? (_filter == _ProbeFilter.problems || problems > 0);
    final small = Theme.of(context).textTheme.bodySmall;
    final ok = members
        .where((t) => results[t.id]?.state == ProbeState.reachable)
        .length;
    return [
      FoldHeader(
        title: name,
        count: members.length,
        open: open,
        onTap: () => setState(() => _toggled[name] = !open),
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
        trailing: busy
            ? const BusyIndicator(size: 12)
            : problems > 0
            ? Text(
                '$problems 项有问题',
                style: small?.copyWith(
                  color: toneColor(
                    context,
                    failing ? NoticeTone.failed : NoticeTone.warning,
                  ),
                ),
              )
            : ok == members.length
            ? Text(
                '全部正常',
                style: small?.copyWith(
                  color: toneColor(context, NoticeTone.done),
                ),
              )
            : null,
      ),
      MotionReveal(
        visible: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final target in members)
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, Gap.md, 0),
                child: _ProbeRow(target: target, result: results[target.id]),
              ),
          ],
        ),
      ),
    ];
  }
}

class _Tally extends StatelessWidget {
  const _Tally({required this.tone, required this.count, required this.label});
  final NoticeTone tone;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(toneIcon(tone), size: 16, color: toneColor(context, tone)),
      const SizedBox(width: Gap.xs),
      Text(
        '$label $count',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    ],
  );
}

class _ProbeRow extends StatelessWidget {
  const _ProbeRow({required this.target, required this.result});
  final ProbeTarget target;
  final ProbeResult? result;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: Row(
      children: [
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
        const SizedBox(width: Gap.sm),
        ProbeStatus(result),
      ],
    ),
  );
}

/// A probe's outcome: latency when the service answered, otherwise why not.
/// Probes go without a token, mostly to bare hosts, so 401 or 404 still
/// means the service answered; only the limited codes are worth showing.
class ProbeStatus extends StatelessWidget {
  const ProbeStatus(this.result, {super.key});
  final ProbeResult? result;

  @override
  Widget build(BuildContext context) {
    final value = result;
    final (String? text, NoticeTone? tone) = switch (value?.state) {
      null || ProbeState.waiting => ('—', null),
      ProbeState.running => (null, null),
      ProbeState.reachable => (
        '${value!.elapsed!.inMilliseconds} ms',
        NoticeTone.done,
      ),
      ProbeState.limited => ('HTTP ${value!.status}', NoticeTone.warning),
      ProbeState.failed => (value!.error!, NoticeTone.failed),
    };
    if (text == null) return const BusyIndicator(size: 12);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tone != null) ...[
          Icon(toneIcon(tone), size: 16, color: toneColor(context, tone)),
          const SizedBox(width: Gap.xs),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
    // A limited service still answered; how fast shows on hover.
    return switch (value) {
      ProbeResult(state: ProbeState.limited, :final elapsed?) => Tooltip(
        message: '${elapsed.inMilliseconds} ms',
        child: row,
      ),
      _ => row,
    };
  }
}
