import '../../domain/resource_title.dart';
import '../../domain/sources.dart';
import '../../features/appearance/appearance.dart';
import '../../features/subscriptions/subscription_matcher.dart';
import '../core/selection_controls.dart';

/// The subtitle filter's sections: either script may meet a selection,
/// while 中日双语 and 内封 each narrow it further. [option] makes a choice's
/// option, with the label and help it shows.
List<MelonFilterSection<String>> subtitleFilterSections(
  MelonFilterOption<String> Function(String value, String label, String? help)
  option,
) => [
  MelonFilterSection([
    for (final value in resourceLanguages) option(value, value, null),
  ], title: '中文字幕'),
  MelonFilterSection([
    option(resourceBilingual, resourceBilingual, '中文字幕旁同时有日文字幕，如简日、繁日'),
    for (final value in resourceSubtitleForms)
      option(
        value,
        '$value字幕',
        '字幕是视频文件里单独的轨道，播放时可以关闭，有多条时（如简繁）可以切换；'
            '内嵌字幕已压进画面，无法关闭',
      ),
  ], title: '只看'),
];

/// The subtitle filter's selection, such as `简体、中日双语、内封`.
String subtitleFilterSummary(Set<String> selected) =>
    resourceSubtitleChoices.where(selected.contains).join('、');

/// A site's search progress beside its name in the 资源站 menu: `12 条`,
/// `搜索中 2/5`.
String resourceProviderStatus(SourceProgress source) => switch (source.status) {
  SearchStatus.loading => '搜索中 ${source.completed}/${source.total}',
  SearchStatus.error => '搜索失败',
  SearchStatus.partial => '${source.resultCount} 条，部分失败',
  SearchStatus.ready => '${source.resultCount} 条',
};

String resourceSizeLabel(TorrentRelease release, ByteUnits units) {
  final provided = (release.sizeLabel ?? '').trim();
  if (provided.isNotEmpty) return provided;
  return resourceBytesLabel(release.sizeBytes ?? 0, units);
}

String resourceBytesLabel(int bytes, ByteUnits units) =>
    bytes <= 1 ? '—' : units.format(bytes);

/// The day [release] was published, in the viewer's zone.
String resourceDateLabel(TorrentRelease release) {
  final published = releasePublished(release.publishedAt);
  if (published == null) return '—';
  return published.toLocal().toIso8601String().substring(0, 10);
}

/// Site release groups, else the group the title credits.
String resourceGroupLabel(ResourceTitleInfo info) => info.sourceGroups.isEmpty
    ? info.credit ?? ''
    : info.sourceGroups.join(' & ');
