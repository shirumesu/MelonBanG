import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { PlaybackSourceView } from "../shared/contracts/playback";
import type { RegisterLocalMediaInput } from "../main/media/localMediaServer";
import type { MediaProbeLike, MediaProbeResult } from "../main/media/mediaProbe";
import bundledFfmpegPath from "ffmpeg-static";

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
        path: "sample.mp4",
        name: "sample.mp4",
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
    writeFileSync(join(getDownloadRootDirectory(), downloadId, "sample.mp4"), "video");

    const service = new PlaybackService(
      repository,
      mediaServer,
      new FakeMediaProbe({
        durationSeconds: null,
        videoCodec: "h264",
        audioCodec: "aac",
        deliveryMode: "direct"
      })
    );
    const [session, duplicateSession] = await Promise.all([
      service.startFromDownload({ downloadId }),
      service.startFromDownload({ downloadId })
    ]);

    expect(session).toMatchObject({
      downloadId,
      fileId,
      title: "sample.mp4",
      status: "ready",
      source: {
        kind: "file",
        title: "sample.mp4",
        mimeType: "video/mp4"
      },
      subtitles: [],
      danmaku: []
    });
    expect(duplicateSession.id).toBe(session.id);
    expect(mediaServer.registered).toHaveLength(1);
    expect(session.source?.url).toMatch(/^http:\/\/127\.0\.0\.1\/media\//);
    expect(session.source?.url).not.toContain("sample.mp4");
    expect(mediaServer.registered[0]).toMatchObject({
      sessionId: session.id,
      title: "sample.mp4"
    });
    expect(mediaServer.registered[0]?.filePath.endsWith("sample.mp4")).toBe(true);

    const playing = service.updateProgress({
      sessionId: session.id,
      positionSeconds: 42,
      durationSeconds: 120,
      timelineOffsetSeconds: 0,
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

  it("starts HEVC-marked downloads through a transient FFmpeg transcode URL", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-playback-transcode-"));
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
    const downloadId = "33333333-3333-4333-8333-333333333333";
    const fileId = `${downloadId}:0`;
    const fileName = "[Group][Title][1080p HEVC].mp4";
    repository.createSession({
      id: downloadId,
      inputKind: "magnet",
      inputRef: "magnet:?xt=urn:btih:C5PPDMBT7OKFBO4A4MGUK3LLHSDP4BKG",
      title: fileName,
      status: "metadata",
      createdAt,
      updatedAt: createdAt
    });
    repository.replaceFiles(downloadId, [
      {
        id: fileId,
        downloadId,
        path: fileName,
        name: fileName,
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
    writeFileSync(join(getDownloadRootDirectory(), downloadId, fileName), "video");

    const service = new PlaybackService(
      repository,
      mediaServer,
      new FakeMediaProbe({
        durationSeconds: 90.09,
        videoCodec: "hevc",
        audioCodec: "aac",
        deliveryMode: "transcode"
      })
    );
    const session = await service.startFromDownload({ downloadId });

    expect(session.source).toMatchObject({
      kind: "hls",
      url: `http://127.0.0.1/transcode/${session.id}/token/index.m3u8`,
      mimeType: "application/vnd.apple.mpegurl",
      title: fileName
    });
    expect(mediaServer.transcoded[0]).toMatchObject({
      sessionId: session.id,
      title: fileName
    });
    expect(mediaServer.registered).toEqual([]);

    const seeked = await service.seek({
      sessionId: session.id,
      positionSeconds: 80
    });
    expect(seeked).toMatchObject({
      positionSeconds: 80,
      durationSeconds: 90.09,
      source: {
        deliveryMode: "transcode",
        timelineOffsetSeconds: 80
      }
    });
    expect(mediaServer.restarted).toHaveLength(1);
    expect(mediaServer.restarted[0]).toMatchObject({ startSeconds: 80 });

    const afterStaleProgress = service.updateProgress({
      sessionId: session.id,
      positionSeconds: 42,
      durationSeconds: 90.09,
      timelineOffsetSeconds: 0,
      paused: true,
      ended: false
    });
    expect(afterStaleProgress.positionSeconds).toBe(80);

    getAppDatabase().close();
  });

  it("uses stream-copy remuxing and source duration for compatible Matroska cache files", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-playback-remux-"));
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
    const createdAt = "2026-07-11T00:00:00.000Z";
    const downloadId = "44444444-4444-4444-8444-444444444444";
    const fileId = `${downloadId}:0`;
    repository.createSession({
      id: downloadId,
      inputKind: "magnet",
      inputRef: "magnet:?xt=urn:btih:C5PPDMBT7OKFBO4A4MGUK3LLHSDP4BKG",
      title: "episode 1080p",
      status: "metadata",
      createdAt,
      updatedAt: createdAt
    });
    repository.replaceFiles(downloadId, [
      {
        id: fileId,
        downloadId,
        path: "episode.mkv",
        name: "episode.mkv",
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
    mkdirSync(join(getDownloadRootDirectory(), downloadId), { recursive: true });
    writeFileSync(join(getDownloadRootDirectory(), downloadId, "episode.mkv"), "video");

    const service = new PlaybackService(
      repository,
      mediaServer,
      new FakeMediaProbe({
        durationSeconds: 1420.08,
        videoCodec: "h264",
        audioCodec: "aac",
        deliveryMode: "remux"
      })
    );
    const session = await service.startFromDownload({ downloadId });

    expect(session).toMatchObject({
      status: "ready",
      durationSeconds: 1420.08,
      source: {
        kind: "hls",
        deliveryMode: "remux",
        url: `http://127.0.0.1/remux/${session.id}/token/index.m3u8`
      }
    });
    expect(mediaServer.remuxed).toHaveLength(1);
    expect(mediaServer.transcoded).toEqual([]);
    expect(mediaServer.registered).toEqual([]);

    const seeked = await service.seek({ sessionId: session.id, positionSeconds: 1200 });
    expect(seeked.source).toMatchObject({
      deliveryMode: "remux",
      timelineOffsetSeconds: 1200
    });
    expect(mediaServer.remuxRestarted).toHaveLength(1);
    expect(mediaServer.remuxRestarted[0]).toMatchObject({ startSeconds: 1200 });

    const playing = service.updateProgress({
      sessionId: session.id,
      positionSeconds: 4,
      durationSeconds: 4,
      timelineOffsetSeconds: 0,
      paused: false,
      ended: false
    });
    expect(playing.durationSeconds).toBe(1420.08);

    getAppDatabase().close();
  });

  it("binds a Bangumi episode to a downloaded file and persists playback progress", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-playback-binding-"));
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
    const downloadId = "44444444-4444-4444-8444-444444444444";
    const fileId = `${downloadId}:0`;
    repository.createSession({
      id: downloadId,
      inputKind: "magnet",
      inputRef: "magnet:?xt=urn:btih:C5PPDMBT7OKFBO4A4MGUK3LLHSDP4BKG",
      title: "episode media",
      status: "metadata",
      createdAt,
      updatedAt: createdAt
    });
    repository.replaceFiles(downloadId, [
      {
        id: fileId,
        downloadId,
        path: "episode-01.mp4",
        name: "episode-01.mp4",
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
    mkdirSync(join(getDownloadRootDirectory(), downloadId), { recursive: true });
    writeFileSync(join(getDownloadRootDirectory(), downloadId, "episode-01.mp4"), "video");

    const service = new PlaybackService(repository, mediaServer);
    const binding = service.bindEpisodeMedia({
      subjectId: 100,
      episodeId: 200,
      downloadId,
      fileId
    });
    expect(binding).toMatchObject({
      subjectId: 100,
      episodeId: 200,
      downloadId,
      fileId,
      available: true
    });
    expect(service.getEpisodeMediaBinding({ subjectId: 100, episodeId: 200 })).toMatchObject({
      fileName: "episode-01.mp4"
    });

    const session = await service.startEpisode({ subjectId: 100, episodeId: 200 });
    expect(session).toMatchObject({
      subjectId: 100,
      episodeId: 200,
      fileId,
      status: "ready"
    });

    service.updateProgress({
      sessionId: session.id,
      positionSeconds: 88,
      durationSeconds: 120,
      timelineOffsetSeconds: 0,
      paused: false,
      ended: false
    });
    expect(service.getEpisodeProgress({ subjectId: 100, episodeId: 200 })).toMatchObject({
      positionSeconds: 88,
      durationSeconds: 120,
      completed: false
    });

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

  it("registers transient FFmpeg transcode URLs without exposing source filenames", async () => {
    const root = mkdtempSync(join(tmpdir(), "melonbang-local-transcode-"));
    const filePath = join(root, "source-hevc.mp4");
    writeFileSync(filePath, "video");

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => root
      }
    }));

    const { LocalMediaServer } = await import("../main/media/localMediaServer");
    const server = new LocalMediaServer([root]);
    const source = await server.registerTranscodedMediaFile({
      sessionId: "session-1",
      filePath,
      title: "source-hevc.mp4"
    });

    expect(source).toMatchObject({
      kind: "hls",
      mimeType: "application/vnd.apple.mpegurl",
      title: "source-hevc.mp4"
    });
    expect(source.url).toMatch(
      /^http:\/\/127\.0\.0\.1:\d+\/transcode\/session-1\/[a-f0-9]+\/index\.m3u8$/
    );
    expect(source.url).not.toContain("source-hevc.mp4");

    await server.dispose();
  });

  it("restarts transcoded HLS from an absolute source position", async () => {
    if (!bundledFfmpegPath) {
      throw new Error("FFmpeg fixture generation is unavailable on this platform.");
    }

    const root = mkdtempSync(join(tmpdir(), "melonbang-local-transcode-seek-"));
    const filePath = join(root, "source.mp4");
    const fixture = spawnSync(
      bundledFfmpegPath,
      [
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "lavfi",
        "-i",
        "color=c=black:s=320x180:r=24",
        "-t",
        "3",
        "-an",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        filePath
      ],
      { windowsHide: true }
    );
    expect(fixture.status).toBe(0);

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => root
      }
    }));

    const { LocalMediaServer } = await import("../main/media/localMediaServer");
    const server = new LocalMediaServer([root]);
    const initial = await server.registerTranscodedMediaFile({
      sessionId: "session-transcode-seek",
      filePath,
      title: "source.mp4"
    });
    const restarted = await server.restartTranscodedMediaFile({
      sessionId: "session-transcode-seek",
      filePath,
      title: "source.mp4",
      startSeconds: 1.5
    });

    expect((await fetch(initial.url)).status).toBe(404);
    const response = await fetch(restarted.url);
    const playlist = await response.text();
    const segmentDuration = [...playlist.matchAll(/#EXTINF:([\d.]+)/g)].reduce(
      (total, match) => total + Number(match[1]),
      0
    );
    expect(response.status).toBe(200);
    expect(restarted.timelineOffsetSeconds).toBe(1.5);
    expect(segmentDuration).toBeGreaterThan(1);
    expect(segmentDuration).toBeLessThan(2);

    await server.dispose();
  });

  it("serves a completed HLS playlist through the stream-copy remux route", async () => {
    if (!bundledFfmpegPath) {
      throw new Error("FFmpeg fixture generation is unavailable on this platform.");
    }

    const root = mkdtempSync(join(tmpdir(), "melonbang-local-remux-"));
    const filePath = join(root, "source.mkv");
    const fixture = spawnSync(
      bundledFfmpegPath,
      [
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "lavfi",
        "-i",
        "color=c=black:s=320x180:r=24",
        "-t",
        "1",
        "-an",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        filePath
      ],
      { windowsHide: true }
    );
    expect(fixture.status).toBe(0);

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => root
      }
    }));

    const { LocalMediaServer } = await import("../main/media/localMediaServer");
    const server = new LocalMediaServer([root]);
    const source = await server.registerRemuxedMediaFile({
      sessionId: "session-remux",
      filePath,
      title: "source.mkv"
    });
    const response = await fetch(source.url);

    expect(response.status).toBe(200);
    expect(source.deliveryMode).toBe("remux");
    expect(await response.text()).toContain("#EXT-X-ENDLIST");

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
  readonly remuxed: RegisterLocalMediaInput[] = [];
  readonly transcoded: RegisterLocalMediaInput[] = [];
  readonly restarted: RegisterLocalMediaInput[] = [];
  readonly remuxRestarted: RegisterLocalMediaInput[] = [];
  readonly revoked: string[] = [];

  registerMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    this.registered.push(input);
    return Promise.resolve({
      kind: "file",
      deliveryMode: "direct",
      timelineOffsetSeconds: 0,
      url: `http://127.0.0.1/media/${input.sessionId}/token`,
      mimeType: "video/mp4",
      title: input.title
    });
  }

  registerRemuxedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    this.remuxed.push(input);
    return Promise.resolve({
      kind: "hls",
      deliveryMode: "remux",
      timelineOffsetSeconds: input.startSeconds ?? 0,
      url: `http://127.0.0.1/remux/${input.sessionId}/token/index.m3u8`,
      mimeType: "application/vnd.apple.mpegurl",
      title: input.title
    });
  }

  registerTranscodedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    this.transcoded.push(input);
    return Promise.resolve({
      kind: "hls",
      deliveryMode: "transcode",
      timelineOffsetSeconds: input.startSeconds ?? 0,
      url: `http://127.0.0.1/transcode/${input.sessionId}/token/index.m3u8`,
      mimeType: "application/vnd.apple.mpegurl",
      title: input.title
    });
  }

  revokeSession(sessionId: string): void {
    this.revoked.push(sessionId);
  }

  restartTranscodedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    this.restarted.push(input);
    return this.registerTranscodedMediaFile(input);
  }

  restartRemuxedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    this.remuxRestarted.push(input);
    return this.registerRemuxedMediaFile(input);
  }
}

class FakeMediaProbe implements MediaProbeLike {
  constructor(private readonly result: MediaProbeResult) {}

  probe(): Promise<MediaProbeResult> {
    return Promise.resolve(this.result);
  }
}
