import 'package:pinyin/pinyin.dart';

import '../../core/error_message.dart';
import '../../core/json.dart';
import '../../core/network.dart';
import '../../domain/torrent_identity.dart';
import '../../domain/sources.dart';
import '../../domain/transfer.dart';
import '../downloads/download_repository.dart';
import 'source_registry.dart';

/// Torrent search across the usable index sources, and enqueueing of its
/// results with their subject/chapter context.
class ReleaseSearch {
  ReleaseSearch(this.api, this.registry, this.downloads);
  final ApiClient api;
  final SourceRegistry registry;
  final DownloadRepository downloads;

  /// Each keyword/source pair publishes through [onUpdate] as soon as its RSS
  /// arrives; optional metadata pages enrich results later and never discard
  /// usable downloads. Releases they list beyond a search feed's limit join
  /// when their title holds every word of the keyword.
  Future<ReleaseSearchResult> search(
    int subjectId,
    String keyword, {
    int? episodeId,
    Iterable<String> alternativeNames = const [],
    String episodeKeyword = '',
    String? coverUrl,
    void Function(ReleaseSearchResult)? onUpdate,
    bool Function()? isCurrent,
    RequestCancellation? cancel,
    bool includeMetadata = true,
  }) async {
    cancel?.throwIfCancelled();
    final keywords = {keyword.trim(), ...alternativeNames.map((e) => e.trim())}
        .where((e) => e.isNotEmpty)
        .map(
          (e) =>
              [e, episodeKeyword.trim()].where((e) => e.isNotEmpty).join(' '),
        )
        .toList();
    if (keywords.isEmpty) return const ReleaseSearchResult();
    final sources = registry.usableOf(SourceKind.torrent);
    final progress = {
      for (final source in sources)
        source.id: SourceProgress(
          sourceId: source.id,
          sourceName: source.name,
          total: keywords.length,
        ),
    };
    final candidates = <String, ReleaseCandidate>{};
    final metadata = <String, TorrentRelease>{};
    final pages = <Uri, Future<String>>{};
    bool current() =>
        cancel?.isCancelled != true && (isCurrent?.call() ?? true);
    ReleaseSearchResult snapshot() => ReleaseSearchResult(
      candidates: candidates.values.toList(),
      sources: progress.values.toList(),
    );
    void emit() {
      if (current()) onUpdate?.call(snapshot());
    }

    Future<void> enrich(SourceInstance source, String name) async {
      try {
        await for (final rows
            in registry
                .torrent(source.id)
                .metadata(name, pages: pages, cancel: cancel)) {
          if (!current()) return;
          for (final row in rows) {
            final identity = '${source.id}:${torrentIdentity(row.locator)}';
            metadata[identity] = row;
            final candidate = candidates[identity];
            if (candidate != null) {
              candidates[identity] = candidate.withRelease(
                candidate.release.enrich(row),
              );
            } else if (_mentions(row.title, name)) {
              candidates[identity] = ReleaseCandidate(
                candidateId: newId(),
                sourceId: source.id,
                sourceName: source.name,
                release: row,
                subjectId: subjectId,
                episodeId: episodeId,
                coverUrl: coverUrl,
              );
            }
          }
          emit();
        }
      } catch (_) {
        // Optional site metadata must never discard usable RSS downloads.
        if (current()) {
          progress[source.id] = progress[source.id]!.copyWith(
            metadataMessage: '部分字幕组信息暂不可用',
          );
          emit();
        }
      }
    }

    emit();
    await Future.wait(
      sources.expand(
        (source) => keywords.map((name) async {
          if (!current()) return;
          var succeeded = false;
          var state = progress[source.id]!;
          try {
            final rows = await registry
                .torrent(source.id)
                .search(name, cancel: cancel);
            if (!current()) return;
            for (final row in rows) {
              final identity = '${source.id}:${torrentIdentity(row.locator)}';
              if (candidates.containsKey(identity)) continue;
              final known = metadata[identity];
              candidates[identity] = ReleaseCandidate(
                candidateId: newId(),
                sourceId: source.id,
                sourceName: source.name,
                release: known == null ? row : row.enrich(known),
                subjectId: subjectId,
                episodeId: episodeId,
                coverUrl: coverUrl,
              );
            }
            succeeded = true;
          } catch (e) {
            state = progress[source.id]!;
            state = state.copyWith(
              failed: state.failed + 1,
              message: errorMessage(e),
            );
            progress[source.id] = state;
          } finally {
            state = progress[source.id]!;
            final completed = state.completed + 1;
            progress[source.id] = state.copyWith(
              completed: completed,
              resultCount: candidates.values
                  .where((e) => e.sourceId == source.id)
                  .length,
              status: completed < state.total
                  ? null
                  : state.failed == 0
                  ? SearchStatus.ready
                  : state.failed == state.total
                  ? SearchStatus.error
                  : SearchStatus.partial,
            );
            emit();
          }
          if (succeeded && includeMetadata) await enrich(source, name);
        }),
      ),
    );
    cancel?.throwIfCancelled();
    return snapshot();
  }

  Future<DownloadTask> enqueue(
    ReleaseCandidate candidate, {
    required CacheMethod method,
    int? episodeId,
  }) async {
    final release = candidate.release;
    episodeId ??= candidate.episodeId;
    if (release.locator.startsWith('magnet:')) {
      return downloads.addMagnet(
        release.locator,
        method: method,
        subjectId: candidate.subjectId,
        episodeId: episodeId,
        coverUrl: candidate.coverUrl,
        releaseGroups: release.releaseGroups,
      );
    }
    final response = await api.send(Uri.parse(release.locator));
    return downloads.addTorrent(
      response.bodyBytes,
      release.title,
      method: method,
      subjectId: candidate.subjectId,
      episodeId: episodeId,
      coverUrl: candidate.coverUrl,
      releaseGroups: release.releaseGroups,
    );
  }
}

/// Whether [title] holds every word of [keyword], as the site search matched
/// it, ignoring case and script.
bool _mentions(String title, String keyword) {
  String fold(String text) =>
      ChineseHelper.convertToSimplifiedChinese(text).toLowerCase();
  final text = fold(title);
  return fold(keyword)
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .every(text.contains);
}
