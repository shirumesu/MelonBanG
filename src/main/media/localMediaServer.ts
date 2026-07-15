import { spawn, type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";
import { createReadStream, existsSync, mkdirSync, readFileSync, statSync } from "node:fs";
import { rm } from "node:fs/promises";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { basename, extname, isAbsolute, join, relative, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import bundledFfmpegPath from "ffmpeg-static";
import type { PlaybackDeliveryMode, PlaybackSourceView } from "../../shared/contracts/playback";
import { getDownloadRootDirectory } from "../download/downloadService";
import { getAppDataDirectory } from "../store/appDatabase";

type HlsState = {
  directory: string;
  playlistPath: string;
  process: ChildProcess | null;
  stderr: string;
  failedMessage: string | null;
  revoked: boolean;
};

type LocalMediaEntry = {
  sessionId: string;
  filePath: string;
  title: string;
  mimeType: string | null;
  delivery: PlaybackDeliveryMode;
  timelineOffsetSeconds: number;
  hls?: HlsState;
};

export type RegisterLocalMediaInput = {
  sessionId: string;
  filePath: string;
  title: string;
  mimeType?: string | null;
  startSeconds?: number;
};

type LocalMediaRoute = {
  kind: "media" | "remux" | "transcode";
  entry: LocalMediaEntry;
  assetName: string | null;
};

const HLS_STARTUP_SEGMENT_COUNT = 2;
const TRANSCODE_SEGMENT_SECONDS = 2;

let localMediaServerInstance: LocalMediaServer | null = null;

export function getLocalMediaServer(): LocalMediaServer {
  localMediaServerInstance ??= new LocalMediaServer([
    getDownloadRootDirectory(),
    join(getAppDataDirectory(), "subtitles")
  ]);
  return localMediaServerInstance;
}

export class LocalMediaServer {
  private readonly allowedRoots: string[];
  private readonly entries = new Map<string, LocalMediaEntry>();
  private readonly cleanupTasks = new Set<Promise<void>>();
  private server: Server | null = null;
  private origin: string | null = null;

  constructor(allowedRoots: string[]) {
    this.allowedRoots = allowedRoots.map((root) => resolve(root));
  }

  async registerMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    const filePath = this.resolveAllowedFile(input.filePath);
    await this.ensureListening();

    const token = randomBytes(24).toString("hex");
    const mimeType = input.mimeType ?? inferMimeType(filePath);
    this.entries.set(token, {
      sessionId: input.sessionId,
      filePath,
      title: input.title,
      mimeType,
      delivery: "direct",
      timelineOffsetSeconds: 0
    });

    return {
      kind: inferSourceKind(filePath, mimeType),
      deliveryMode: "direct",
      timelineOffsetSeconds: 0,
      url: `${this.requireOrigin()}/media/${encodeURIComponent(input.sessionId)}/${token}/${encodeURIComponent(
        basename(filePath)
      )}`,
      mimeType,
      title: input.title
    };
  }

  async registerTranscodedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    return this.registerHlsMediaFile(input, "transcode");
  }

  async restartTranscodedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    this.revokeHlsStreams(input.sessionId);
    return this.registerHlsMediaFile(input, "transcode");
  }

  async restartRemuxedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    this.revokeHlsStreams(input.sessionId);
    return this.registerHlsMediaFile(input, "remux");
  }

  async registerRemuxedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    return this.registerHlsMediaFile(input, "remux");
  }

  private async registerHlsMediaFile(
    input: RegisterLocalMediaInput,
    deliveryMode: Exclude<PlaybackDeliveryMode, "direct">
  ): Promise<PlaybackSourceView> {
    const filePath = this.resolveAllowedFile(input.filePath);
    await this.ensureListening();

    const token = randomBytes(24).toString("hex");
    const directory = join(getAppDataDirectory(), "playback-streams", input.sessionId, token);
    mkdirSync(directory, { recursive: true });
    const hls: HlsState = {
      directory,
      playlistPath: join(directory, "index.m3u8"),
      process: null,
      stderr: "",
      failedMessage: null,
      revoked: false
    };
    const entry: LocalMediaEntry = {
      sessionId: input.sessionId,
      filePath,
      title: input.title,
      mimeType: "application/vnd.apple.mpegurl",
      delivery: deliveryMode,
      timelineOffsetSeconds: normalizeStartSeconds(input.startSeconds),
      hls
    };
    this.entries.set(token, entry);
    this.ensureHlsProcess(entry, hls);

    return {
      kind: "hls",
      deliveryMode,
      timelineOffsetSeconds: normalizeStartSeconds(input.startSeconds),
      url: `${this.requireOrigin()}/${deliveryMode}/${encodeURIComponent(input.sessionId)}/${token}/index.m3u8`,
      mimeType: "application/vnd.apple.mpegurl",
      title: input.title
    };
  }

  revokeSession(sessionId: string): void {
    for (const [token, entry] of this.entries) {
      if (entry.sessionId === sessionId) {
        this.scheduleHlsCleanup(entry);
        this.entries.delete(token);
      }
    }
  }

  private revokeHlsStreams(sessionId: string): void {
    for (const [token, entry] of this.entries) {
      if (entry.sessionId === sessionId && entry.hls) {
        this.scheduleHlsCleanup(entry);
        this.entries.delete(token);
      }
    }
  }

  async dispose(): Promise<void> {
    for (const entry of this.entries.values()) {
      this.scheduleHlsCleanup(entry);
    }
    this.entries.clear();
    await Promise.allSettled(this.cleanupTasks);
    const server = this.server;
    this.server = null;
    this.origin = null;
    if (!server) {
      return;
    }

    await new Promise<void>((resolvePromise, rejectPromise) => {
      server.close((error) => {
        if (error) {
          rejectPromise(error);
          return;
        }
        resolvePromise();
      });
    });
  }

  private async ensureListening(): Promise<void> {
    if (this.server && this.origin) {
      return;
    }

    const server = createServer((request, response) => this.handleRequest(request, response));
    await new Promise<void>((resolvePromise, rejectPromise) => {
      server.once("error", rejectPromise);
      server.listen(0, "127.0.0.1", () => {
        server.off("error", rejectPromise);
        const address = server.address() as AddressInfo;
        this.origin = `http://127.0.0.1:${address.port}`;
        this.server = server;
        resolvePromise();
      });
    });
  }

  private handleRequest(request: IncomingMessage, response: ServerResponse): void {
    if (request.method !== "GET" && request.method !== "HEAD") {
      response.writeHead(405).end();
      return;
    }

    const route = this.findRoute(request.url);
    if (!route) {
      response.writeHead(404).end();
      return;
    }

    let stat;
    try {
      stat = statSync(route.entry.filePath);
    } catch {
      response.writeHead(404).end();
      return;
    }

    if (!stat.isFile()) {
      response.writeHead(404).end();
      return;
    }

    if (route.kind !== "media") {
      void this.handleHlsRequest(request, response, route).catch((error: unknown) => {
        if (!response.headersSent) {
          response.writeHead(500, {
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store",
            "Content-Type": "text/plain; charset=utf-8"
          });
        }
        response.end(error instanceof Error ? error.message : "FFmpeg 转码失败。");
      });
      return;
    }

    const range = parseRangeHeader(request.headers.range, stat.size);
    if (!range) {
      response.writeHead(416, {
        "Access-Control-Allow-Origin": "*",
        "Accept-Ranges": "bytes",
        "Content-Range": `bytes */${stat.size}`
      });
      response.end();
      return;
    }

    const headers: Record<string, string | number> = {
      "Access-Control-Allow-Origin": "*",
      "Accept-Ranges": "bytes",
      "Content-Type": route.entry.mimeType ?? "application/octet-stream",
      "Content-Length": range.end - range.start + 1
    };

    if (range.partial) {
      headers["Content-Range"] = `bytes ${range.start}-${range.end}/${stat.size}`;
    }

    response.writeHead(range.partial ? 206 : 200, headers);
    if (request.method === "HEAD") {
      response.end();
      return;
    }

    createReadStream(route.entry.filePath, { start: range.start, end: range.end }).pipe(response);
  }

  private async handleHlsRequest(
    request: IncomingMessage,
    response: ServerResponse,
    route: LocalMediaRoute
  ): Promise<void> {
    const hls = route.entry.hls;
    if (!hls || !route.assetName) {
      response.writeHead(404).end();
      return;
    }

    this.ensureHlsProcess(route.entry, hls);

    const assetPath = join(hls.directory, route.assetName);
    const relativeAssetPath = relative(hls.directory, assetPath);
    if (
      relativeAssetPath.length === 0 ||
      relativeAssetPath.startsWith("..") ||
      isAbsolute(relativeAssetPath) ||
      !isAllowedHlsAsset(route.assetName)
    ) {
      response.writeHead(404).end();
      return;
    }

    const available =
      route.assetName === "index.m3u8"
        ? await waitForHlsStartupBuffer(
            assetPath,
            () => hls.failedMessage,
            20_000,
            HLS_STARTUP_SEGMENT_COUNT
          )
        : await waitForFile(assetPath, () => hls.failedMessage, 20_000);
    if (!available) {
      const message = hls.failedMessage ?? "等待 FFmpeg 生成播放切片超时。";
      throw new Error(message);
    }

    const stat = statSync(assetPath);
    response.writeHead(200, {
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-store",
      "Content-Length": stat.size,
      "Content-Type": inferHlsAssetMimeType(route.assetName)
    });

    if (request.method === "HEAD") {
      response.end();
      return;
    }

    createReadStream(assetPath).pipe(response);
  }

  private ensureHlsProcess(entry: LocalMediaEntry, hls: HlsState): void {
    if (hls.revoked || hls.process || hls.failedMessage) {
      return;
    }

    const args =
      entry.delivery === "remux"
        ? createFfmpegRemuxArgs(entry.filePath, hls.directory, entry.timelineOffsetSeconds)
        : createFfmpegTranscodeArgs(entry.filePath, hls.directory, entry.timelineOffsetSeconds);
    const ffmpeg = spawn(getFfmpegPath(), args, {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"]
    });

    hls.process = ffmpeg;
    ffmpeg.stderr.on("data", (chunk: Buffer) => {
      if (hls.stderr.length < 4000) {
        hls.stderr += chunk.toString("utf8");
      }
    });
    ffmpeg.stdout.resume();
    ffmpeg.once("error", (error) => {
      hls.failedMessage = error.message || "无法启动 FFmpeg 媒体准备进程。";
    });
    ffmpeg.once("close", (code) => {
      hls.process = null;
      if (code) {
        hls.failedMessage = hls.stderr || `FFmpeg 媒体准备失败，退出码 ${code}。`;
      }
    });
  }

  private scheduleHlsCleanup(entry: LocalMediaEntry): void {
    const task = this.stopHls(entry).finally(() => this.cleanupTasks.delete(task));
    this.cleanupTasks.add(task);
  }

  private async stopHls(entry: LocalMediaEntry): Promise<void> {
    if (!entry.hls) {
      return;
    }

    const hls = entry.hls;
    hls.revoked = true;
    hls.failedMessage ??= "播放流已关闭。";
    const process = hls.process;
    hls.process = null;
    if (process && process.exitCode === null) {
      process.kill("SIGTERM");
      if (!(await waitForProcessExit(process, 1_500)) && process.exitCode === null) {
        process.kill("SIGKILL");
        await waitForProcessExit(process, 1_000);
      }
    }

    try {
      await rm(hls.directory, {
        recursive: true,
        force: true,
        maxRetries: 8,
        retryDelay: 125
      });
    } catch {
      // Cleanup is best-effort. A later session or app shutdown can retry stale directories.
    }
  }

  private findRoute(rawUrl: string | undefined): LocalMediaRoute | null {
    if (!rawUrl) {
      return null;
    }

    const url = new URL(rawUrl, "http://127.0.0.1");
    const [, kind, , token, assetName] = url.pathname.split("/");
    if ((kind !== "media" && kind !== "remux" && kind !== "transcode") || !token) {
      return null;
    }

    const entry = this.entries.get(token);
    if (!entry) {
      return null;
    }

    if (kind === "media" && entry.delivery !== "direct") {
      return null;
    }

    if ((kind === "remux" || kind === "transcode") && entry.delivery !== kind) {
      return null;
    }

    return { kind, entry, assetName: assetName ? decodeURIComponent(assetName) : null };
  }

  private resolveAllowedFile(filePath: string): string {
    const resolved = resolve(filePath);
    const allowed = this.allowedRoots.some((root) => {
      const relativePath = relative(root, resolved);
      return relativePath.length > 0 && !relativePath.startsWith("..") && !isAbsolute(relativePath);
    });

    if (!allowed) {
      throw new Error("拒绝注册媒体根目录之外的文件。");
    }

    if (!existsSync(resolved)) {
      throw new Error("本地媒体文件不存在。");
    }

    return resolved;
  }

  private requireOrigin(): string {
    if (!this.origin) {
      throw new Error("本地媒体服务尚未启动。");
    }
    return this.origin;
  }
}

function getFfmpegPath(): string {
  if (!bundledFfmpegPath) {
    throw new Error("当前平台缺少内置 FFmpeg 二进制。");
  }

  return bundledFfmpegPath;
}

function createFfmpegRemuxArgs(
  filePath: string,
  outputDirectory: string,
  startSeconds: number
): string[] {
  return [
    "-hide_banner",
    "-loglevel",
    "error",
    "-nostdin",
    ...createFfmpegInputArgs(filePath, startSeconds),
    "-map",
    "0:v:0",
    "-map",
    "0:a:0?",
    "-sn",
    "-dn",
    "-c",
    "copy",
    "-start_number",
    "0",
    "-hls_time",
    "4",
    "-hls_list_size",
    "0",
    "-hls_flags",
    "independent_segments",
    "-hls_playlist_type",
    "event",
    "-hls_segment_filename",
    join(outputDirectory, "segment-%05d.ts"),
    "-f",
    "hls",
    join(outputDirectory, "index.m3u8")
  ];
}

function createFfmpegTranscodeArgs(
  filePath: string,
  outputDirectory: string,
  startSeconds: number
): string[] {
  return [
    "-hide_banner",
    "-loglevel",
    "error",
    "-nostdin",
    ...createFfmpegInputArgs(filePath, startSeconds),
    "-map",
    "0:v:0",
    "-map",
    "0:a:0?",
    "-sn",
    "-dn",
    "-c:v",
    "libx264",
    "-preset",
    "superfast",
    "-tune",
    "zerolatency",
    "-pix_fmt",
    "yuv420p",
    "-force_key_frames",
    `expr:gte(t,n_forced*${TRANSCODE_SEGMENT_SECONDS})`,
    "-c:a",
    "aac",
    "-b:a",
    "160k",
    "-start_number",
    "0",
    "-hls_time",
    String(TRANSCODE_SEGMENT_SECONDS),
    "-hls_list_size",
    "0",
    "-hls_flags",
    "independent_segments+temp_file",
    "-hls_playlist_type",
    "event",
    "-hls_segment_filename",
    join(outputDirectory, "segment-%05d.ts"),
    "-f",
    "hls",
    join(outputDirectory, "index.m3u8")
  ];
}

function createFfmpegInputArgs(filePath: string, startSeconds: number): string[] {
  if (startSeconds > 0) {
    return ["-ss", startSeconds.toFixed(3), "-i", filePath];
  }

  return ["-i", filePath];
}

function normalizeStartSeconds(value: number | undefined): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : 0;
}

async function waitForFile(
  filePath: string,
  getFailureMessage: () => string | null,
  timeoutMs: number
): Promise<boolean> {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (existsSync(filePath)) {
      return true;
    }

    if (getFailureMessage()) {
      return false;
    }

    await delay(150);
  }

  return existsSync(filePath);
}

async function waitForHlsStartupBuffer(
  playlistPath: string,
  getFailureMessage: () => string | null,
  timeoutMs: number,
  segmentCount: number
): Promise<boolean> {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (hasHlsStartupBuffer(playlistPath, segmentCount)) {
      return true;
    }

    if (getFailureMessage()) {
      return false;
    }

    await delay(100);
  }

  return hasHlsStartupBuffer(playlistPath, segmentCount);
}

function hasHlsStartupBuffer(playlistPath: string, segmentCount: number): boolean {
  if (!existsSync(playlistPath)) {
    return false;
  }

  try {
    const playlist = readFileSync(playlistPath, "utf8");
    const completedSegments = playlist.match(/^#EXTINF:/gm)?.length ?? 0;
    return completedSegments >= segmentCount || playlist.includes("#EXT-X-ENDLIST");
  } catch {
    return false;
  }
}

async function waitForProcessExit(process: ChildProcess, timeoutMs: number): Promise<boolean> {
  if (process.exitCode !== null) {
    return true;
  }

  return new Promise<boolean>((resolvePromise) => {
    const timeout = setTimeout(() => {
      process.off("close", handleClose);
      resolvePromise(false);
    }, timeoutMs);
    const handleClose = (): void => {
      clearTimeout(timeout);
      resolvePromise(true);
    };
    process.once("close", handleClose);
  });
}

function isAllowedHlsAsset(assetName: string): boolean {
  return assetName === "index.m3u8" || /^segment-\d{5}\.ts$/.test(assetName);
}

function inferHlsAssetMimeType(assetName: string): string {
  if (assetName.endsWith(".m3u8")) {
    return "application/vnd.apple.mpegurl";
  }

  if (assetName.endsWith(".ts")) {
    return "video/mp2t";
  }

  return "application/octet-stream";
}

function parseRangeHeader(
  header: string | undefined,
  size: number
): { start: number; end: number; partial: boolean } | null {
  if (!header) {
    return { start: 0, end: Math.max(0, size - 1), partial: false };
  }

  const match = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!match) {
    return null;
  }

  const [, rawStart, rawEnd] = match;
  if (!rawStart && !rawEnd) {
    return null;
  }

  if (!rawStart) {
    const suffixLength = Number(rawEnd);
    if (!Number.isFinite(suffixLength) || suffixLength <= 0) {
      return null;
    }
    const start = Math.max(0, size - suffixLength);
    return { start, end: Math.max(0, size - 1), partial: true };
  }

  const start = Number(rawStart);
  const end = rawEnd ? Number(rawEnd) : size - 1;
  if (
    !Number.isFinite(start) ||
    !Number.isFinite(end) ||
    start < 0 ||
    end < start ||
    start >= size
  ) {
    return null;
  }

  return {
    start,
    end: Math.min(end, size - 1),
    partial: true
  };
}

function inferSourceKind(filePath: string, mimeType: string | null): PlaybackSourceView["kind"] {
  const extension = extname(filePath).toLowerCase();
  if (extension === ".m3u8" || mimeType === "application/vnd.apple.mpegurl") {
    return "hls";
  }

  return "file";
}

function inferMimeType(filePath: string): string | null {
  const extension = extname(filePath).toLowerCase();
  const mimeTypes: Record<string, string> = {
    ".m3u8": "application/vnd.apple.mpegurl",
    ".mp4": "video/mp4",
    ".m4v": "video/mp4",
    ".webm": "video/webm",
    ".ogv": "video/ogg",
    ".ogg": "video/ogg",
    ".mkv": "video/x-matroska",
    ".mov": "video/quicktime",
    ".vtt": "text/vtt"
  };

  return mimeTypes[extension] ?? null;
}
