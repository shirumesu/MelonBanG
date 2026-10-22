import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/update/app_update.dart';
import '../../integrations/github/app_releases.dart';
import '../core/page_widgets.dart';
import '../core/theme.dart';
import 'settings_page.dart';

/// Version, update state and the update preferences.
class UpdateSettings extends StatelessWidget {
  const UpdateSettings({
    super.key,
    required this.update,
    required this.onRestart,
  });
  final AppUpdate update;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: update,
    builder: (context, _) => PageScroll(
      key: const PageStorageKey('settings-update'),
      children: [
        const SectionTitle(title: '版本'),
        MelonPanel(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingRow(
                title: AppUpdate.version.isEmpty
                    ? 'MelonBanG 开发版本'
                    : 'MelonBanG ${AppUpdate.version}',
                subtitle: _status(),
                subtitleColor: update.phase == UpdatePhase.failed
                    ? coral
                    : null,
                trailing: _action(),
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
                  child: SelectableText(
                    release.notes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (update.unavailable == null) ...[
          const SectionTitle(title: '更新方式'),
          MelonPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SettingRow(
                  title: '自动检查更新',
                  subtitle: '每次启动时检查 GitHub 上的新版本',
                  trailing: Switch(
                    value: update.autoCheck,
                    onChanged: update.setAutoCheck,
                  ),
                ),
                SettingRow(
                  title: '自动下载更新',
                  subtitle: '在后台下载，下次重启或退出时安装',
                  trailing: Switch(
                    value: update.autoDownload,
                    onChanged: update.setAutoDownload,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SectionTitle(title: '关于'),
        MelonPanel(
          padding: EdgeInsets.zero,
          child: SettingRow(
            title: '开源许可',
            subtitle: 'MelonBanG 以 GNU GPL 3.0 许可发布',
            trailing: OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.https('github.com', '/$releaseRepository'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('源代码'),
            ),
          ),
        ),
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

  Widget _action() {
    if (update.unavailable != null) {
      return OutlinedButton.icon(
        onPressed: () =>
            launchUrl(releasePage, mode: LaunchMode.externalApplication),
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
