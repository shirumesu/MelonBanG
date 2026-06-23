import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

describe("DownloadRepository", () => {
  afterEach(() => {
    vi.resetModules();
    delete process.env.MELONBANG_DATA_DIR;
  });

  it("maps persisted download sessions and files to renderer-safe views", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-download-repo-"));
    process.env.MELONBANG_DATA_DIR = join(appRoot, "data");

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => appRoot
      }
    }));

    const { getAppDatabase } = await import("../main/store/appDatabase");
    const { DownloadRepository } = await import("../main/download/downloadRepository");
    const repository = new DownloadRepository();
    const createdAt = "2026-06-23T00:00:00.000Z";

    repository.createSession({
      id: "download-1",
      inputKind: "magnet",
      inputRef: "magnet:?xt=urn:btih:C5PPDMBT7OKFBO4A4MGUK3LLHSDP4BKG",
      title: "sample 1080p",
      status: "metadata",
      createdAt,
      updatedAt: createdAt
    });
    repository.replaceFiles("download-1", [
      {
        id: "download-1:0",
        downloadId: "download-1",
        path: "sample.mkv",
        name: "sample.mkv",
        sizeBytes: 1024,
        mediaKind: "video",
        priority: 1,
        progress: 0,
        createdAt,
        updatedAt: createdAt
      }
    ]);
    repository.updateSession("download-1", {
      status: "downloading",
      progress: 0.5,
      downloadedBytes: 512,
      totalBytes: 1024,
      downloadSpeedBytesPerSecond: 256,
      peerCount: 2,
      selectedFileId: "download-1:0",
      previewImageUrl: "https://whatslink.info/image/example",
      previewSourceName: "whatslink.info",
      previewSourceUrl: "https://whatslink.info/"
    });

    expect(repository.listSnapshot()).toMatchObject({
      tasks: [
        {
          id: "download-1",
          title: "sample 1080p",
          status: "downloading",
          progress: 0.5,
          downloadedBytes: 512,
          totalBytes: 1024,
          downloadSpeedBytesPerSecond: 256,
          peerCount: 2,
          selectedFileId: "download-1:0",
          errorMessage: null,
          previewImageUrl: "https://whatslink.info/image/example",
          previewSourceName: "whatslink.info",
          previewSourceUrl: "https://whatslink.info/"
        }
      ],
      files: [
        {
          id: "download-1:0",
          downloadId: "download-1",
          path: "sample.mkv",
          name: "sample.mkv",
          sizeBytes: 1024,
          mediaKind: "video",
          priority: 1,
          progress: 0
        }
      ]
    });

    getAppDatabase().close();
  });
});
