import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";
import { existsSync } from "node:fs";
import { isAbsolute, relative, resolve } from "node:path";
import type {
  PlaybackProgressInput,
  PlaybackSessionView,
  PlaybackSourceView,
  StartPlaybackFromDownloadInput
} from "../../shared/contracts/playback";
import { DownloadRepository } from "../download/downloadRepository";
import { getDownloadRootDirectory } from "../download/downloadService";
import { getLocalMediaServer, type RegisterLocalMediaInput } from "../media/localMediaServer";

type PlaybackEventName = "session";

type LocalMediaServerLike = {
  registerMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView>;
  revokeSession(sessionId: string): void;
};

let serviceInstance: PlaybackService | null = null;

export function getPlaybackService(): PlaybackService {
  serviceInstance ??= new PlaybackService();
  return serviceInstance;
}

export class PlaybackService {
  private readonly events = new EventEmitter();
  private session: PlaybackSessionView | null = null;

  constructor(
    private readonly repository = new DownloadRepository(),
    private readonly mediaServer: LocalMediaServerLike = getLocalMediaServer()
  ) {}

  onSession(callback: (session: PlaybackSessionView | null) => void): () => void {
    const listener = (): void => callback(this.session);
    this.events.on("session", listener);
    return () => this.events.off("session", listener);
  }

  async startFromDownload(input: StartPlaybackFromDownloadInput): Promise<PlaybackSessionView> {
    const media = this.resolveDownloadMedia(input);
    if (this.session) {
      this.mediaServer.revokeSession(this.session.id);
    }

    const sessionId = randomUUID();
    const now = new Date().toISOString();
    this.session = {
      id: sessionId,
      downloadId: input.downloadId,
      fileId: media.fileId,
      title: media.title,
      status: "preparing",
      source: null,
      subtitles: [],
      danmaku: [],
      positionSeconds: 0,
      durationSeconds: null,
      errorMessage: null,
      createdAt: now,
      updatedAt: now
    };
    this.emitSession();

    try {
      const source = await this.mediaServer.registerMediaFile({
        sessionId,
        filePath: media.path,
        title: media.title
      });
      this.updateSession({
        status: "ready",
        source,
        errorMessage: null
      });
      return this.requireSession(sessionId);
    } catch (error) {
      this.updateSession({
        status: "failed",
        source: null,
        errorMessage: toRendererSafeError(error)
      });
      return this.requireSession(sessionId);
    }
  }

  getSession(): PlaybackSessionView | null {
    return this.session;
  }

  updateProgress(input: PlaybackProgressInput): PlaybackSessionView {
    const session = this.requireSession(input.sessionId);
    if (session.status === "stopped" || session.status === "failed") {
      return session;
    }

    this.updateSession({
      status: input.ended ? "ended" : input.paused ? "paused" : "playing",
      positionSeconds: Math.max(0, input.positionSeconds),
      durationSeconds:
        input.durationSeconds && input.durationSeconds > 0 ? input.durationSeconds : null
    });

    return this.requireSession(input.sessionId);
  }

  stop(sessionId: string): void {
    this.requireSession(sessionId);
    this.mediaServer.revokeSession(sessionId);
    this.updateSession({ status: "stopped" });
  }

  private resolveDownloadMedia(input: StartPlaybackFromDownloadInput): {
    path: string;
    title: string;
    fileId: string;
  } {
    const task = this.repository.getSession(input.downloadId);
    if (!task) {
      throw new Error("下载任务不存在。");
    }

    if (task.status !== "completed" && task.status !== "ready") {
      throw new Error("下载任务尚未可播放。");
    }

    const files = this.repository.listFiles(task.id);
    const selectedFile =
      files.find((file) => file.id === input.fileId) ??
      files.find((file) => file.id === task.selectedFileId) ??
      files.find((file) => file.mediaKind === "video");

    if (!selectedFile || selectedFile.mediaKind !== "video") {
      throw new Error("下载任务没有可播放的视频文件。");
    }

    const downloadRoot = resolve(getDownloadRootDirectory(), task.id);
    const mediaPath = resolve(downloadRoot, selectedFile.path);
    const relativePath = relative(downloadRoot, mediaPath);
    if (relativePath.length === 0 || relativePath.startsWith("..") || isAbsolute(relativePath)) {
      throw new Error("拒绝播放下载目录之外的文件。");
    }

    if (!existsSync(mediaPath)) {
      throw new Error("本地视频文件不存在，请重新缓存。");
    }

    return {
      path: mediaPath,
      title: selectedFile.name || task.title,
      fileId: selectedFile.id
    };
  }

  private requireSession(sessionId: string): PlaybackSessionView {
    if (!this.session || this.session.id !== sessionId) {
      throw new Error("播放会话不存在。");
    }
    return this.session;
  }

  private updateSession(
    patch: Partial<
      Pick<
        PlaybackSessionView,
        | "status"
        | "source"
        | "subtitles"
        | "danmaku"
        | "positionSeconds"
        | "durationSeconds"
        | "errorMessage"
      >
    >
  ): void {
    if (!this.session) {
      return;
    }

    this.session = {
      ...this.session,
      ...patch,
      updatedAt: new Date().toISOString()
    };
    this.emitSession();
  }

  private emitSession(): void {
    this.events.emit("session" satisfies PlaybackEventName);
  }
}

function toRendererSafeError(error: unknown): string {
  if (error instanceof Error) {
    return error.message || "播放请求失败。";
  }

  return "播放请求失败。";
}
