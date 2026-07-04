import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";
import { existsSync } from "node:fs";
import { extname, isAbsolute, relative, resolve } from "node:path";
import type {
  BindEpisodeMediaInput,
  ClearEpisodeMediaBindingInput,
  EpisodeMediaBindingInput,
  MediaBindingView,
  PlaybackProgressInput,
  PlaybackProgressSnapshot,
  PlaybackSessionView,
  PlaybackSourceView,
  StartEpisodePlaybackInput,
  StartPlaybackFromDownloadInput
} from "../../shared/contracts/playback";
import { DownloadRepository } from "../download/downloadRepository";
import { getDownloadRootDirectory } from "../download/downloadService";
import { getLocalMediaServer, type RegisterLocalMediaInput } from "../media/localMediaServer";
import { SubtitleService } from "../subtitle/subtitleService";
import { PlaybackRepository } from "./playbackRepository";

type PlaybackEventName = "session";

type LocalMediaServerLike = {
  registerMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView>;
  registerTranscodedMediaFile?(input: RegisterLocalMediaInput): Promise<PlaybackSourceView>;
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
    private readonly mediaServer: LocalMediaServerLike = getLocalMediaServer(),
    private readonly subtitleService = new SubtitleService(mediaServer),
    private readonly playbackRepository = new PlaybackRepository()
  ) {}

  onSession(callback: (session: PlaybackSessionView | null) => void): () => void {
    const listener = (): void => callback(this.session);
    this.events.on("session", listener);
    return () => this.events.off("session", listener);
  }

  async startFromDownload(input: StartPlaybackFromDownloadInput): Promise<PlaybackSessionView> {
    const media = this.resolveDownloadMedia(input);
    return this.startPlaybackSession(media, {
      downloadId: input.downloadId,
      subjectId: null,
      episodeId: null
    });
  }

  bindEpisodeMedia(input: BindEpisodeMediaInput): MediaBindingView {
    const media = this.resolveDownloadMedia(input);
    const now = new Date().toISOString();
    return this.playbackRepository.saveMediaBinding({
      id: randomUUID(),
      subjectId: input.subjectId,
      episodeId: input.episodeId,
      downloadId: input.downloadId,
      fileId: media.fileId,
      createdAt: now,
      updatedAt: now
    });
  }

  getEpisodeMediaBinding(input: EpisodeMediaBindingInput): MediaBindingView | null {
    return this.playbackRepository.getMediaBinding(input.subjectId, input.episodeId);
  }

  clearEpisodeMediaBinding(input: ClearEpisodeMediaBindingInput): void {
    this.playbackRepository.clearMediaBinding(input.bindingId);
  }

  async startEpisode(input: StartEpisodePlaybackInput): Promise<PlaybackSessionView> {
    const binding = this.playbackRepository.getMediaBinding(input.subjectId, input.episodeId);
    if (!binding) {
      throw new Error("当前章节还没有绑定本地媒体文件。");
    }

    const media = this.resolveDownloadMedia({
      downloadId: binding.downloadId,
      fileId: binding.fileId
    });
    return this.startPlaybackSession(media, {
      downloadId: binding.downloadId,
      subjectId: input.subjectId,
      episodeId: input.episodeId
    });
  }

  getEpisodeProgress(input: EpisodeMediaBindingInput): PlaybackProgressSnapshot | null {
    return this.playbackRepository.getProgress(input.subjectId, input.episodeId);
  }

  private async startPlaybackSession(
    media: {
      path: string;
      title: string;
      fileId: string;
    },
    context: {
      downloadId: string;
      subjectId: number | null;
      episodeId: number | null;
    }
  ): Promise<PlaybackSessionView> {
    if (this.session) {
      this.mediaServer.revokeSession(this.session.id);
    }

    const sessionId = randomUUID();
    const now = new Date().toISOString();
    this.session = {
      id: sessionId,
      downloadId: context.downloadId,
      fileId: media.fileId,
      subjectId: context.subjectId,
      episodeId: context.episodeId,
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
      const sourceInput = {
        sessionId,
        filePath: media.path,
        title: media.title
      };
      const source =
        shouldTranscodeForWeb(media.path, media.title) && this.mediaServer.registerTranscodedMediaFile
          ? await this.mediaServer.registerTranscodedMediaFile(sourceInput)
          : await this.mediaServer.registerMediaFile(sourceInput);
      const subtitles = await this.subtitleService.prepareSubtitles({
        sessionId,
        mediaPath: media.path
      });
      this.updateSession({
        status: "ready",
        source,
        subtitles,
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

    const nextSession = this.requireSession(input.sessionId);
    if (nextSession.subjectId !== null && nextSession.episodeId !== null) {
      try {
        this.playbackRepository.saveProgress({
          subjectId: nextSession.subjectId,
          episodeId: nextSession.episodeId,
          positionSeconds: nextSession.positionSeconds,
          durationSeconds: nextSession.durationSeconds,
          completed: input.ended,
          updatedAt: nextSession.updatedAt
        });
      } catch {
        // Playback should continue even when local progress persistence is unavailable.
      }
    }

    return nextSession;
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

function shouldTranscodeForWeb(filePath: string, title: string): boolean {
  const extension = extname(filePath).toLowerCase();
  if (extension === ".mkv" || extension === ".avi" || extension === ".flv" || extension === ".wmv") {
    return true;
  }

  return /\b(hevc|h\.?265|x265|10bit|hi10p|av1)\b/i.test(title);
}
