import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../features/update/app_update.dart';
import '../../features/update/uninstall.dart';
import '../../integrations/github/app_releases.dart';
import '../core/external_link.dart';
import '../core/selection_controls.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import 'settings_page.dart';

/// Version, update state and preferences, the license and uninstalling.
SettingsSection aboutSection({
  required AppUpdate update,
  required VoidCallback onRestart,
  required AppUninstall? uninstall,
  required Future<void> Function(bool wipe) onUninstall,
}) => SettingsSection(
  id: 'about',
  title: '更新与关于',
  icon: Icons.info_outline,
  groups: [
    SettingsGroup([
      SettingsItem(
        '版本 更新 检查更新 下载更新 重启',
        _UpdateStatus(update: update, onRestart: onRestart),
      ),
      if (update.unavailable == null) ...[
        SettingsItem(
          '更新渠道 稳定版 测试版 beta alpha 预发布',
          ListenableBuilder(
            listenable: update,
            builder: (context, _) => SettingRow(
              title: '更新渠道',
              subtitle: update.beta
                  ? '测试版能更早用上新功能，但问题可能更多'
                  : '只更新到稳定版；正在用测试版时，等下一个稳定版发布再更新',
              trailing: MelonChoiceMenu(
                options: const {false: '稳定版', true: '测试版'},
                value: update.beta,
                onSelected: update.setBeta,
              ),
            ),
          ),
        ),
        SettingsItem(
          '自动检查更新 启动',
          ListenableBuilder(
            listenable: update,
            builder: (context, _) => SettingSwitch(
              title: '自动检查更新',
              subtitle: '每次启动时检查 GitHub 上的新版本',
              value: update.autoCheck,
              onChanged: update.setAutoCheck,
            ),
          ),
        ),
        SettingsItem(
          '自动下载更新 后台',
          ListenableBuilder(
            listenable: update,
            builder: (context, _) => SettingSwitch(
              title: '自动下载更新',
              subtitle: '在后台下载，下次重启或退出时安装',
              value: update.autoDownload,
              onChanged: update.setAutoDownload,
            ),
          ),
        ),
      ],
    ], title: '版本'),
    SettingsGroup([
      SettingsItem(
        '开源 许可 gpl 源代码 github',
        SettingRow(
          title: '开源许可',
          subtitle: 'MelonBanG 以 GNU GPL 3.0 许可发布',
          trailing: Builder(
            builder: (context) => OutlinedButton.icon(
              onPressed: () => openExternal(
                context,
                'https://github.com/$releaseRepository',
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('源代码'),
            ),
          ),
        ),
      ),
      if (uninstall != null)
        SettingsItem(
          '卸载 删除 移除 uninstall 清除数据',
          _UninstallRow(uninstall: uninstall, onUninstall: onUninstall),
        ),
    ], title: '关于'),
  ],
);

class _UpdateStatus extends StatelessWidget {
  const _UpdateStatus({required this.update, required this.onRestart});
  final AppUpdate update;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: update,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          title: AppUpdate.version.isEmpty
              ? 'MelonBanG 开发版本'
              : 'MelonBanG ${AppUpdate.version}',
          subtitle: _status(),
          subtitleColor: update.phase == UpdatePhase.failed ? coral : null,
          trailing: _action(context),
        ),
        if (update.phase == UpdatePhase.downloading)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.lg),
            child: LinearProgressIndicator(value: update.progress),
          ),
        if (update.release case final release?
            when release.notes.isNotEmpty &&
                update.phase != UpdatePhase.idle) ...[
          const Divider(height: 1, indent: 20, endIndent: 20),
          Padding(
            padding: const EdgeInsets.all(20),
            child: _ReleaseNotes(release.notes),
          ),
        ],
      ],
    ),
  );

  String _status() {
    if (update.unavailable case final reason?) return reason;
    return switch (update.phase) {
      UpdatePhase.idle => update.checkedAt == null ? '尚未检查更新' : '已是最新版本',
      UpdatePhase.checking => '正在检查更新…',
      UpdatePhase.available => '发现新版本 ${update.release!.version}',
      UpdatePhase.downloading =>
        '正在下载 ${update.release!.version}（${(update.progress * 100).round()}%）',
      UpdatePhase.ready => '新版本 ${update.readyVersion} 已准备好，重启后生效',
      UpdatePhase.failed => update.error!,
    };
  }

  Widget _action(BuildContext context) {
    if (update.unavailable != null) {
      return OutlinedButton.icon(
        onPressed: () => openExternal(context, '$releasePage'),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: const Text('发行页'),
      );
    }
    return switch (update.phase) {
      UpdatePhase.available => FilledButton.icon(
        onPressed: update.download,
        icon: const Icon(Icons.download, size: 18),
        label: const Text('下载更新'),
      ),
      UpdatePhase.ready => FilledButton.icon(
        onPressed: onRestart,
        icon: const Icon(Icons.restart_alt, size: 18),
        label: const Text('重启并更新'),
      ),
      UpdatePhase.failed when update.release != null => OutlinedButton.icon(
        onPressed: update.download,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('重试'),
      ),
      _ => OutlinedButton.icon(
        onPressed:
            update.phase == UpdatePhase.checking ||
                update.phase == UpdatePhase.downloading
            ? null
            : update.check,
        icon: const Icon(Icons.sync, size: 18),
        label: const Text('检查更新'),
      ),
    };
  }
}

/// The release's CHANGELOG.md up to its download table, which is of no use
/// to an app that updates itself: `##` headings, `-` items and paragraphs,
/// with links and emphasis reduced to their text.
class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes(this.notes);
  final String notes;

  static String _plain(String text) => text
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'\*\*|`'), '');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lines = notes.split('## 下载安装').first.split('\n');
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final raw in lines)
            if (raw.trim() case final line
                when line.isNotEmpty && !line.startsWith('> [!'))
              if (line.startsWith('## '))
                Padding(
                  padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.xs),
                  child: Text(line.substring(3), style: text.titleSmall),
                )
              else if (line.startsWith('- '))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '•  ${_plain(line.substring(2))}',
                    style: text.bodySmall,
                  ),
                )
              else
                Text(
                  _plain(line.replaceFirst(RegExp(r'^>\s?'), '')),
                  style: text.bodySmall,
                ),
        ],
      ),
    );
  }
}

class _UninstallRow extends StatelessWidget {
  const _UninstallRow({required this.uninstall, required this.onUninstall});
  final AppUninstall uninstall;
  final Future<void> Function(bool wipe) onUninstall;

  @override
  Widget build(BuildContext context) => switch (uninstall.kind) {
    UninstallKind.windowsInstaller => SettingRow(
      title: '卸载 MelonBanG',
      subtitle: '关闭应用并打开卸载程序，可以选择保留或删除数据',
      trailing: OutlinedButton.icon(
        onPressed: () => _confirmWindows(context),
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('卸载…'),
      ),
    ),
    UninstallKind.macOSBundle => SettingRow(
      title: '卸载 MelonBanG',
      subtitle: '退出后把应用移到废纸篓，可以选择同时删除所有数据',
      trailing: OutlinedButton.icon(
        onPressed: () => _confirmMacOS(context),
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('卸载…'),
      ),
    ),
    UninstallKind.portable => SettingRow(
      title: '卸载 MelonBanG',
      subtitle: AppUninstall.appImage == null
          ? '便携版不需要卸载：退出后删除程序所在的文件夹即可'
          : 'AppImage 不需要卸载：退出后删除这个 AppImage 文件即可',
      trailing: OutlinedButton.icon(
        onPressed: () => launchUrl(
          Uri.directory(
            AppUninstall.appImage == null
                ? AppUninstall.installation
                : p.dirname(AppUninstall.installation),
          ),
        ),
        icon: const Icon(Icons.folder_open_outlined, size: 18),
        label: const Text('打开文件夹'),
      ),
    ),
    UninstallKind.unavailable => SettingRow(
      title: '卸载 MelonBanG',
      subtitle: AppUpdate.version.isEmpty || !Platform.isMacOS
          ? '开发版本不提供卸载'
          : '请先把 MelonBanG 拖到“应用程序”文件夹再打开',
    ),
  };

  Future<void> _confirmWindows(BuildContext context) async {
    final confirmed = await showMelonDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('卸载 MelonBanG？'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'MelonBanG 会先关闭，正在进行的播放和下载会停止。随后打开的卸载程序里可以选择保留或删除追番记录、设置和已下载的番剧。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('关闭并卸载'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onUninstall(false);
  }

  Future<void> _confirmMacOS(BuildContext context) async {
    final wipe = await showMelonDialog<bool>(
      context: context,
      builder: (context) => _MacOSUninstallDialog(uninstall: uninstall),
    );
    if (wipe != null) await onUninstall(wipe);
  }
}

/// Pops with whether to delete the data, or null when cancelled.
class _MacOSUninstallDialog extends StatefulWidget {
  const _MacOSUninstallDialog({required this.uninstall});
  final AppUninstall uninstall;
  @override
  State<_MacOSUninstallDialog> createState() => _MacOSUninstallDialogState();
}

class _MacOSUninstallDialogState extends State<_MacOSUninstallDialog> {
  bool wipe = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('卸载 MelonBanG？'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MelonBanG 会先退出，正在进行的播放和下载会停止，然后应用会被移到废纸篓。'),
            const SizedBox(height: Gap.lg),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: wipe,
              onChanged: (value) => setState(() => wipe = value ?? false),
              title: const Text('同时删除所有数据'),
              subtitle: const Text(
                '追番记录、播放进度、设置、登录信息和已下载的番剧会被永久删除；已同步到 Bangumi 的收藏不受影响',
              ),
            ),
            if (wipe) ...[
              const SizedBox(height: Gap.sm),
              for (final folder in widget.uninstall.dataFolders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: SelectableText(folder, style: small),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: wipe
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, wipe),
          child: Text(wipe ? '退出并删除全部' : '退出并卸载'),
        ),
      ],
    );
  }
}
