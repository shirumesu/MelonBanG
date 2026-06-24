import { randomBytes } from "node:crypto";
import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { basename, extname, isAbsolute, join, relative, resolve } from "node:path";
import type { PlaybackSourceView } from "../../shared/contracts/playback";
import { getDownloadRootDirectory } from "../download/downloadService";
import { getAppDataDirectory } from "../store/appDatabase";

type LocalMediaEntry = {
  sessionId: string;
  filePath: string;
  title: string;
  mimeType: string | null;
};

export type RegisterLocalMediaInput = {
  sessionId: string;
  filePath: string;
  title: string;
  mimeType?: string | null;
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
      mimeType
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

  revokeSession(sessionId: string): void {
    for (const [token, entry] of this.entries) {
      if (entry.sessionId === sessionId) {
        this.entries.delete(token);
      }
    }
  }

  async dispose(): Promise<void> {
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

    const entry = this.findEntry(request.url);
    if (!entry) {
      response.writeHead(404).end();
      return;
    }

    let stat;
    try {
      stat = statSync(entry.filePath);
    } catch {
      response.writeHead(404).end();
      return;
    }

    if (!stat.isFile()) {
      response.writeHead(404).end();
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
      "Content-Type": entry.mimeType ?? "application/octet-stream",
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

    createReadStream(entry.filePath, { start: range.start, end: range.end }).pipe(response);
  }

  private findEntry(rawUrl: string | undefined): LocalMediaEntry | null {
    if (!rawUrl) {
      return null;
    }

    const url = new URL(rawUrl, "http://127.0.0.1");
    const [, kind, , token] = url.pathname.split("/");
    if (kind !== "media" || !token) {
      return null;
    }

    return this.entries.get(token) ?? null;
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
