import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import type {
  AddTorrentRuntimeOptions,
  TorrentHandle,
  TorrentRuntimeFile,
  TorrentRuntimeStats
} from "../main/download/torrentClient";
import type { DownloadPreviewMetadata } from "../main/download/whatsLinkClient";

const magnet = "magnet:?xt=urn:btih:C5PPDMBT7OKFBO4A4MGUK3LLHSDP4BKG";

class FakeTorrentClient {
  options: AddTorrentRuntimeOptions | null = null;
  pause = vi.fn();
  resume = vi.fn();
  remove = vi.fn<() => Promise<void>>(() => Promise.resolve());

  addTorrent(options: AddTorrentRuntimeOptions): TorrentHandle {
    this.options = options;
    return {
      pause: this.pause,
      resume: this.resume,
      remove: this.remove,
      getStats: () => stats({ progress: 0 })
    };
  }
}

class FakePreviewClient {
  constructor(private readonly preview: DownloadPreviewMetadata | null = null) {}

  getPreview = vi.fn(() => Promise.resolve(this.preview));
}

class FakeThumbnailGenerator {
  generate = vi.fn(() => Promise.resolve("data:image/jpeg;base64,dGh1bWJuYWls"));
}

describe("DownloadService", () => {
  afterEach(() => {
    vi.resetModules();
    delete process.env.MELONBANG_DATA_DIR;
  });

  it("keeps a paused task paused when late torrent events arrive", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-download-service-"));
    process.env.MELONBANG_DATA_DIR = join(appRoot, "data");

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => appRoot
      }
    }));

    const { getAppDatabase } = await import("../main/store/appDatabase");
    const { DownloadRepository } = await import("../main/download/downloadRepository");
    const { DownloadService } = await import("../main/download/downloadService");
    const repository = new DownloadRepository();
    const torrentClient = new FakeTorrentClient();
    const service = new DownloadService(repository, torrentClient, new FakePreviewClient());

    const task = service.create({ kind: "magnet", uri: magnet });
    service.pause(task.id);

    torrentClient.options?.onMetadata({
      title: "Sample Anime 1080p",
      files: [file({ progress: 0.2 })],
      selectedFileIndex: 0,
      stats: stats({ progress: 0.2, downloadedBytes: 200, downloadSpeedBytesPerSecond: 1024 })
    });

    expect(repository.requireTask(task.id)).toMatchObject({
      status: "paused",
      selectedFileId: `${task.id}:0`,
      downloadSpeedBytesPerSecond: 0,
      peerCount: 0
    });

    torrentClient.options?.onProgress(
      stats({ progress: 0.4, downloadedBytes: 400, downloadSpeedBytesPerSecond: 2048 }),
      [file({ progress: 0.4 })]
    );

    expect(repository.requireTask(task.id)).toMatchObject({
      status: "paused",
      progress: 0.4,
      downloadedBytes: 400,
      downloadSpeedBytesPerSecond: 0,
      etaSeconds: null
    });

    service.resume(task.id);

    expect(torrentClient.resume).toHaveBeenCalledTimes(1);
    expect(repository.requireTask(task.id).status).toBe("downloading");

    getAppDatabase().close();
  });

  it("updates a download task with whatslink preview metadata", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-download-preview-"));
    process.env.MELONBANG_DATA_DIR = join(appRoot, "data");

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => appRoot
      }
    }));

    const { getAppDatabase } = await import("../main/store/appDatabase");
    const { DownloadRepository } = await import("../main/download/downloadRepository");
    const { DownloadService } = await import("../main/download/downloadService");
    const repository = new DownloadRepository();
    const torrentClient = new FakeTorrentClient();
    const previewClient = new FakePreviewClient({
      title: "[Haruhana] Kamiina Botan - 11.mkv",
      totalBytes: 253418173,
      imageUrl: "https://whatslink.info/image/2dcbdefbac60dffb83af326e2f994a91",
      sourceName: "whatslink.info",
      sourceUrl: "https://whatslink.info/"
    });
    const service = new DownloadService(repository, torrentClient, previewClient);

    const task = service.create({ kind: "magnet", uri: magnet });
    await nextTick();

    expect(previewClient.getPreview).toHaveBeenCalledWith({ kind: "magnet", uri: magnet });
    expect(repository.requireTask(task.id)).toMatchObject({
      title: "[Haruhana] Kamiina Botan - 11.mkv",
      totalBytes: 253418173,
      previewImageUrl: "https://whatslink.info/image/2dcbdefbac60dffb83af326e2f994a91",
      previewSourceName: "whatslink.info",
      previewSourceUrl: "https://whatslink.info/"
    });

    getAppDatabase().close();
  });

  it("persists a local video thumbnail when a completed download has no remote cover", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-download-thumbnail-"));
    process.env.MELONBANG_DATA_DIR = join(appRoot, "data");

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => appRoot
      }
    }));

    const { getAppDatabase } = await import("../main/store/appDatabase");
    const { DownloadRepository } = await import("../main/download/downloadRepository");
    const { DownloadService, getDownloadRootDirectory } =
      await import("../main/download/downloadService");
    const repository = new DownloadRepository();
    const torrentClient = new FakeTorrentClient();
    const thumbnailGenerator = new FakeThumbnailGenerator();
    const service = new DownloadService(
      repository,
      torrentClient,
      new FakePreviewClient(),
      thumbnailGenerator
    );

    const task = service.create({ kind: "magnet", uri: magnet });
    const runtimeFile = file({ progress: 1 });
    torrentClient.options?.onMetadata({
      title: "Sample Anime 1080p",
      files: [runtimeFile],
      selectedFileIndex: 0,
      stats: stats({ progress: 1, downloadedBytes: 1000 })
    });
    const mediaPath = join(getDownloadRootDirectory(), task.id, runtimeFile.path);
    mkdirSync(join(getDownloadRootDirectory(), task.id), { recursive: true });
    writeFileSync(mediaPath, "video");
    torrentClient.options?.onDone(stats({ progress: 1, downloadedBytes: 1000 }), [runtimeFile]);
    await nextTick();

    expect(thumbnailGenerator.generate).toHaveBeenCalledWith(mediaPath);
    expect(repository.requireTask(task.id).previewImageUrl).toBe(
      "data:image/jpeg;base64,dGh1bWJuYWls"
    );

    getAppDatabase().close();
  });
});

async function nextTick(): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 0));
}

function file({ progress }: { progress: number }): TorrentRuntimeFile {
  return {
    index: 0,
    path: "Sample Anime.mkv",
    name: "Sample Anime.mkv",
    sizeBytes: 1000,
    mediaKind: "video",
    progress
  };
}

function stats({
  progress,
  downloadedBytes = 0,
  downloadSpeedBytesPerSecond = 0
}: {
  progress: number;
  downloadedBytes?: number;
  downloadSpeedBytesPerSecond?: number;
}): TorrentRuntimeStats {
  return {
    title: "Sample Anime 1080p",
    progress,
    downloadedBytes,
    totalBytes: 1000,
    downloadSpeedBytesPerSecond,
    uploadSpeedBytesPerSecond: 128,
    peerCount: 2,
    done: false
  };
}
