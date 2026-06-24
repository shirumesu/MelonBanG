import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { PlaybackSourceView } from "../shared/contracts/playback";
import type { RegisterLocalMediaInput } from "../main/media/localMediaServer";

afterEach(() => {
  vi.resetModules();
  delete process.env.MELONBANG_DATA_DIR;
});

describe("PlaybackService", () => {
  it("starts Web playback from a completed download file through a safe local URL", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-playback-service-"));
    process.env.MELONBANG_DATA_DIR = join(appRoot, "data");

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => appRoot
      }
    }));

    const { DownloadRepository } = await import("../main/download/downloadRepository");
    const { getDownloadRootDirectory } = await import("../main/download/downloadService");
    const { PlaybackService } = await import("../main/playback/playbackService");
    const { getAppDatabase } = await import("../main/store/appDatabase");

    const repository = new DownloadRepository();
    const mediaServer = new FakeMediaServer();
    const createdAt = "2026-06-23T00:00:00.000Z";
    const downloadId = "11111111-1111-4111-8111-111111111111";
    const fileId = `${downloadId}:0`;
    repository.createSession({
      id: downloadId,
      inputKind: "magnet",
      inputRef: "magnet:?xt=urn:btih:C5PPDMBT7OKFBO4A4MGUK3LLHSDP4BKG",
      title: "sample 1080p",
      status: "metadata",
      createdAt,
      updatedAt: createdAt
    });
    repository.replaceFiles(downloadId, [
      {
        id: fileId,
        downloadId,
        path: "sample.mkv",
        name: "sample.mkv",
        sizeBytes: 1024,
        mediaKind: "video",
        priority: 1,
        progress: 1,
        createdAt,
        updatedAt: createdAt
      }
    ]);
    repository.updateSession(downloadId, {
      status: "completed",
      progress: 1,
      downloadedBytes: 1024,
      totalBytes: 1024,
      selectedFileId: fileId
    });
    mkdirSync(join(getDownloadRootDirectory(), downloadId), { recursive: true });
    writeFileSync(join(getDownloadRootDirectory(), downloadId, "sample.mkv"), "video");

    const service = new PlaybackService(repository, mediaServer);
    const session = await service.startFromDownload({ downloadId });

    expect(session).toMatchObject({
      downloadId,
      fileId,
      title: "sample.mkv",
      status: "ready",
      source: {
        kind: "file",
        title: "sample.mkv",
        mimeType: "video/x-matroska"
      },
      subtitles: [],
      danmaku: []
    });
    expect(session.source?.url).toMatch(/^http:\/\/127\.0\.0\.1\/media\//);
    expect(session.source?.url).not.toContain("sample.mkv");
    expect(mediaServer.registered[0]).toMatchObject({
      sessionId: session.id,
      title: "sample.mkv"
    });
    expect(mediaServer.registered[0]?.filePath.endsWith("sample.mkv")).toBe(true);

    const playing = service.updateProgress({
      sessionId: session.id,
      positionSeconds: 42,
      durationSeconds: 120,
      paused: false,
      ended: false
    });
    expect(playing).toMatchObject({
      status: "playing",
      positionSeconds: 42,
      durationSeconds: 120
    });

    service.stop(session.id);
    expect(service.getSession()).toMatchObject({ status: "stopped" });
    expect(mediaServer.revoked).toEqual([session.id]);

    getAppDatabase().close();
  });

  it("rejects playback when the completed download file is missing", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-playback-missing-"));
    process.env.MELONBANG_DATA_DIR = join(appRoot, "data");

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => appRoot
      }
    }));

    const { DownloadRepository } = await import("../main/download/downloadRepository");
    const { PlaybackService } = await import("../main/playback/playbackService");
    const { getAppDatabase } = await import("../main/store/appDatabase");

    const repository = new DownloadRepository();
    const createdAt = "2026-06-23T00:00:00.000Z";
    const downloadId = "22222222-2222-4222-8222-222222222222";
    const fileId = `${downloadId}:0`;
    repository.createSession({
      id: downloadId,
      inputKind: "magnet",
      inputRef: "magnet:?xt=urn:btih:C5PPDMBT7OKFBO4A4MGUK3LLHSDP4BKG",
      title: "missing 1080p",
      status: "completed",
      createdAt,
      updatedAt: createdAt
    });
    repository.replaceFiles(downloadId, [
      {
        id: fileId,
        downloadId,
        path: "missing.mkv",
        name: "missing.mkv",
        sizeBytes: 1024,
        mediaKind: "video",
        priority: 1,
        progress: 1,
        createdAt,
        updatedAt: createdAt
      }
    ]);
    repository.updateSession(downloadId, {
      status: "completed",
      selectedFileId: fileId
    });

    const service = new PlaybackService(repository, new FakeMediaServer());

    await expect(service.startFromDownload({ downloadId })).rejects.toThrow("本地视频文件不存在");
    getAppDatabase().close();
  });
});

describe("LocalMediaServer", () => {
  it("serves registered media with byte ranges", async () => {
    const root = mkdtempSync(join(tmpdir(), "melonbang-local-media-"));
    const filePath = join(root, "sample.mp4");
    writeFileSync(filePath, "0123456789");

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => root
      }
    }));

    const { LocalMediaServer } = await import("../main/media/localMediaServer");
    const server = new LocalMediaServer([root]);
    const source = await server.registerMediaFile({
      sessionId: "session-1",
      filePath,
      title: "sample.mp4"
    });

    const response = await fetch(source.url, {
      headers: {
        Range: "bytes=2-5"
      }
    });
    expect(response.status).toBe(206);
    expect(response.headers.get("content-range")).toBe("bytes 2-5/10");
    expect(await response.text()).toBe("2345");

    await server.dispose();
  });

  it("refuses to register files outside allowed roots", async () => {
    const root = mkdtempSync(join(tmpdir(), "melonbang-local-media-root-"));
    const outside = mkdtempSync(join(tmpdir(), "melonbang-local-media-outside-"));
    const filePath = join(outside, "sample.mp4");
    writeFileSync(filePath, "video");

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => root
      }
    }));

    const { LocalMediaServer } = await import("../main/media/localMediaServer");
    const server = new LocalMediaServer([root]);

    await expect(
      server.registerMediaFile({
        sessionId: "session-1",
        filePath,
        title: "sample.mp4"
      })
    ).rejects.toThrow("拒绝注册媒体根目录之外的文件");

    await server.dispose();
  });
});

class FakeMediaServer {
  readonly registered: RegisterLocalMediaInput[] = [];
  readonly revoked: string[] = [];

  registerMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    this.registered.push(input);
    return Promise.resolve({
      kind: "file",
      url: `http://127.0.0.1/media/${input.sessionId}/token`,
      mimeType: "video/x-matroska",
      title: input.title
    });
  }

  revokeSession(sessionId: string): void {
    this.revoked.push(sessionId);
  }
}
