import WebTorrent, { type Torrent, type TorrentFile } from "webtorrent";
import type { TorrentInput } from "../../shared/contracts/download";

export type TorrentRuntimeFile = {
  index: number;
  path: string;
  name: string;
  sizeBytes: number;
  mediaKind: "video" | "subtitle" | "other";
  progress: number;
};

export type TorrentRuntimeStats = {
  title: string;
  progress: number;
  downloadedBytes: number;
  totalBytes: number;
  downloadSpeedBytesPerSecond: number;
  uploadSpeedBytesPerSecond: number;
  peerCount: number;
  done: boolean;
};

export type TorrentMetadata = {
  title: string;
  files: TorrentRuntimeFile[];
  selectedFileIndex: number | null;
  stats: TorrentRuntimeStats;
};

export type TorrentHandle = {
  pause(): void;
  resume(): void;
  remove(): Promise<void>;
  getStats(): TorrentRuntimeStats;
};

export type AddTorrentRuntimeOptions = {
  input: TorrentInput;
  downloadPath: string;
  onMetadata(metadata: TorrentMetadata): void;
  onProgress(stats: TorrentRuntimeStats, files: TorrentRuntimeFile[]): void;
  onDone(stats: TorrentRuntimeStats, files: TorrentRuntimeFile[]): void;
  onError(error: Error): void;
};

export class TorrentClientAdapter {
  private readonly client = new WebTorrent();

  addTorrent(options: AddTorrentRuntimeOptions): TorrentHandle {
    let metadataHandled = false;
    let paused = false;
    let selectedFileIndex: number | null = null;
    const handleMetadata = (readyTorrent: Torrent): void => {
      if (metadataHandled) {
        return;
      }

      metadataHandled = true;
      const files = toRuntimeFiles(readyTorrent.files);
      selectedFileIndex = choosePlayableFileIndex(files);
      for (const file of readyTorrent.files) {
        file.deselect();
      }

      if (selectedFileIndex !== null && !paused) {
        readyTorrent.files[selectedFileIndex]?.select(1);
      }

      options.onMetadata({
        title: readyTorrent.name || inferFallbackTitle(options.input),
        files,
        selectedFileIndex,
        stats: toStats(readyTorrent, options.input)
      });
    };

    const torrent = this.client.add(
      toTorrentId(options.input),
      { path: options.downloadPath },
      handleMetadata
    );

    torrent.on("metadata", () => handleMetadata(torrent));

    torrent.on("download", () => {
      options.onProgress(toStats(torrent, options.input), toRuntimeFiles(torrent.files));
    });

    torrent.on("done", () => {
      options.onDone(toStats(torrent, options.input), toRuntimeFiles(torrent.files));
    });

    torrent.on("error", (error) => options.onError(error));

    return {
      pause() {
        paused = true;
        for (const file of torrent.files) {
          file.deselect();
        }
        torrent.pause();
      },
      resume() {
        paused = false;
        if (selectedFileIndex !== null) {
          torrent.files[selectedFileIndex]?.select(1);
        }
        torrent.resume();
      },
      remove: () =>
        new Promise((resolve, reject) => {
          this.client.remove(torrent, { destroyStore: true }, (error?: Error) => {
            if (error) {
              reject(error);
              return;
            }

            resolve();
          });
        }),
      getStats: () => toStats(torrent, options.input)
    };
  }

  destroy(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.client.destroy((error?: Error) => {
        if (error) {
          reject(error);
          return;
        }

        resolve();
      });
    });
  }
}

function toTorrentId(input: TorrentInput): string | Uint8Array {
  if (input.kind === "magnet") {
    return input.uri;
  }

  return input.bytes;
}

function toRuntimeFiles(files: TorrentFile[]): TorrentRuntimeFile[] {
  return files.map((file, index) => ({
    index,
    path: file.path,
    name: file.name,
    sizeBytes: file.length,
    mediaKind: inferMediaKind(file.name),
    progress: clampProgress(file.progress)
  }));
}

function toStats(torrent: Torrent, input: TorrentInput): TorrentRuntimeStats {
  const totalBytes = Number.isFinite(torrent.length) ? torrent.length : 0;
  return {
    title: torrent.name || inferFallbackTitle(input),
    progress: clampProgress(torrent.progress),
    downloadedBytes: Math.max(0, Math.round(torrent.downloaded || 0)),
    totalBytes: totalBytes > 0 ? totalBytes : 0,
    downloadSpeedBytesPerSecond: Math.max(0, Math.round(torrent.downloadSpeed || 0)),
    uploadSpeedBytesPerSecond: Math.max(0, Math.round(torrent.uploadSpeed || 0)),
    peerCount: Math.max(0, Math.round(torrent.numPeers || 0)),
    done: torrent.done
  };
}

function choosePlayableFileIndex(files: TorrentRuntimeFile[]): number | null {
  const videoFiles = files.filter((file) => file.mediaKind === "video");
  const candidates = videoFiles.length > 0 ? videoFiles : files;
  const selected = candidates.toSorted((left, right) => right.sizeBytes - left.sizeBytes)[0];
  return selected ? selected.index : null;
}

function inferMediaKind(name: string): TorrentRuntimeFile["mediaKind"] {
  const extension = name.toLowerCase().split(".").pop();
  if (!extension) {
    return "other";
  }

  if (["mkv", "mp4", "avi", "mov", "webm", "m4v", "ts"].includes(extension)) {
    return "video";
  }

  if (["ass", "ssa", "srt", "vtt"].includes(extension)) {
    return "subtitle";
  }

  return "other";
}

function inferFallbackTitle(input: TorrentInput): string {
  if (input.kind === "torrentFile") {
    return input.name;
  }

  try {
    const parsed = new URL(input.uri);
    const displayName = parsed.searchParams.get("dn")?.trim();
    if (displayName) {
      return displayName;
    }
  } catch {
    return "BT 下载任务";
  }

  return "BT 下载任务";
}

function clampProgress(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }

  return Math.min(1, Math.max(0, value));
}
