import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { randomBytes } from "node:crypto";
import { createReadStream, existsSync, mkdirSync, rmSync, statSync } from "node:fs";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { basename, extname, isAbsolute, join, relative, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import bundledFfmpegPath from "ffmpeg-static";
import type { PlaybackSourceView } from "../../shared/contracts/playback";
import { getDownloadRootDirectory } from "../download/downloadService";
import { getAppDataDirectory } from "../store/appDatabase";

type TranscodeState = {
  directory: string;
  playlistPath: string;
  process: ChildProcessWithoutNullStreams | null;
  stderr: string;
  failedMessage: string | null;
};

type LocalMediaEntry = {
  sessionId: string;
  filePath: string;
  title: string;
  mimeType: string | null;
  delivery: "direct" | "ffmpeg-transcode";
  transcode?: TranscodeState;
};

export type RegisterLocalMediaInput = {
  sessionId: string;
  filePath: string;
  title: string;
  mimeType?: string | null;
};

type LocalMediaRoute = {
  kind: "media" | "transcode";
  entry: LocalMediaEntry;
  assetName: string | null;
};

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
      delivery: "direct"
    });

    return {
      kind: inferSourceKind(filePath, mimeType),
      url: `${this.requireOrigin()}/media/${encodeURIComponent(input.sessionId)}/${token}/${encodeURIComponent(
        basename(filePath)
      )}`,
      mimeType,
      title: input.title
    };
  }

  async registerTranscodedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView> {
    const filePath = this.resolveAllowedFile(input.filePath);
    await this.ensureListening();

    const token = randomBytes(24).toString("hex");
    const directory = join(getAppDataDirectory(), "transcodes", input.sessionId, token);
    mkdirSync(directory, { recursive: true });
    this.entries.set(token, {
      sessionId: input.sessionId,
      filePath,
      title: input.title,
      mimeType: "application/vnd.apple.mpegurl",
      delivery: "ffmpeg-transcode",
      transcode: {
        directory,
        playlistPath: join(directory, "index.m3u8"),
        process: null,
        stderr: "",
        failedMessage: null
      }
    });

    return {
      kind: "hls",
      url: `${this.requireOrigin()}/transcode/${encodeURIComponent(input.sessionId)}/${token}/index.m3u8`,
      mimeType: "application/vnd.apple.mpegurl",
      title: input.title
    };
  }

  revokeSession(sessionId: string): void {
    for (const [token, entry] of this.entries) {
      if (entry.sessionId === sessionId) {
        this.stopTranscode(entry);
        this.entries.delete(token);
      }
    }
  }

  async dispose(): Promise<void> {
    for (const entry of this.entries.values()) {
      this.stopTranscode(entry);
    }
    this.entries.clear();
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

    if (route.kind === "transcode") {
      void this.handleTranscodeRequest(request, response, route).catch((error: unknown) => {
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

  private async handleTranscodeRequest(
    request: IncomingMessage,
    response: ServerResponse,
    route: LocalMediaRoute
  ): Promise<void> {
    const transcode = route.entry.transcode;
    if (!transcode || !route.assetName) {
      response.writeHead(404).end();
      return;
    }

    this.ensureTranscodeProcess(route.entry, transcode);

    const assetPath = join(transcode.directory, route.assetName);
    const relativeAssetPath = relative(transcode.directory, assetPath);
    if (
      relativeAssetPath.length === 0 ||
      relativeAssetPath.startsWith("..") ||
      isAbsolute(relativeAssetPath) ||
      !isAllowedTranscodeAsset(route.assetName)
    ) {
      response.writeHead(404).end();
      return;
    }

    const available = await waitForFile(assetPath, () => transcode.failedMessage, 20_000);
    if (!available) {
      const message = transcode.failedMessage ?? "等待 FFmpeg 生成播放切片超时。";
      throw new Error(message);
    }

    const stat = statSync(assetPath);
    response.writeHead(200, {
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-store",
      "Content-Length": stat.size,
      "Content-Type": inferTranscodeAssetMimeType(route.assetName)
    });

    if (request.method === "HEAD") {
      response.end();
      return;
    }

    createReadStream(assetPath).pipe(response);
  }

  private ensureTranscodeProcess(entry: LocalMediaEntry, transcode: TranscodeState): void {
    if (transcode.process || transcode.failedMessage) {
      return;
    }

    const ffmpeg = spawn(getFfmpegPath(), createFfmpegTranscodeArgs(entry.filePath, transcode.directory), {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"]
    });

    transcode.process = ffmpeg;
    ffmpeg.stderr.on("data", (chunk: Buffer) => {
      if (transcode.stderr.length < 4000) {
        transcode.stderr += chunk.toString("utf8");
      }
    });
    ffmpeg.stdout.resume();
    ffmpeg.once("error", (error) => {
      transcode.failedMessage = error.message || "无法启动 FFmpeg 转码进程。";
    });
    ffmpeg.once("close", (code) => {
      transcode.process = null;
      if (code) {
        transcode.failedMessage = transcode.stderr || `FFmpeg 转码失败，退出码 ${code}。`;
      }
    });
  }

  private stopTranscode(entry: LocalMediaEntry): void {
    if (!entry.transcode) {
      return;
    }

    const process = entry.transcode.process;
    if (process && !process.killed) {
      process.kill("SIGTERM");
    }
    rmSync(entry.transcode.directory, { recursive: true, force: true });
  }

  private findRoute(rawUrl: string | undefined): LocalMediaRoute | null {
    if (!rawUrl) {
      return null;
    }

    const url = new URL(rawUrl, "http://127.0.0.1");
    const [, kind, , token, assetName] = url.pathname.split("/");
    if ((kind !== "media" && kind !== "transcode") || !token) {
      return null;
    }

    const entry = this.entries.get(token);
    if (!entry) {
      return null;
    }

    if (kind === "media" && entry.delivery !== "direct") {
      return null;
    }

    if (kind === "transcode" && entry.delivery !== "ffmpeg-transcode") {
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

function createFfmpegTranscodeArgs(filePath: string, outputDirectory: string): string[] {
  return [
    "-hide_banner",
    "-loglevel",
    "error",
    "-nostdin",
    "-i",
    filePath,
    "-map",
    "0:v:0",
    "-map",
    "0:a:0?",
    "-sn",
    "-dn",
    "-c:v",
    "libx264",
    "-preset",
    "veryfast",
    "-tune",
    "zerolatency",
    "-pix_fmt",
    "yuv420p",
    "-c:a",
    "aac",
    "-b:a",
    "160k",
    "-start_number",
    "0",
    "-hls_time",
    "4",
    "-hls_list_size",
    "0",
    "-hls_flags",
    "independent_segments",
    "-hls_segment_filename",
    join(outputDirectory, "segment-%05d.ts"),
    "-f",
    "hls",
    join(outputDirectory, "index.m3u8")
  ];
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

function isAllowedTranscodeAsset(assetName: string): boolean {
  return assetName === "index.m3u8" || /^segment-\d{5}\.ts$/.test(assetName);
}

function inferTranscodeAssetMimeType(assetName: string): string {
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
