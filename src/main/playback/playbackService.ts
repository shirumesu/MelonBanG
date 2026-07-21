import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";
import { existsSync } from "node:fs";
import { extname, isAbsolute, relative, resolve } from "node:path";
import type {
  DanmakuEpisodeSearchInput,
  DanmakuEpisodeSearchResult,
  DanmakuSourceId,
  DanmakuSourceView,
  EpisodePlaybackInput,
  LoadDanmakuSourceInput,
  PlaybackProgressInput,
  PlaybackProgressSnapshot,
  PlaybackSessionView,
  PlaybackSourceView,
  SeekPlaybackInput,
  SetDanmakuSourceEnabledInput,
  SelectDanmakuEpisodeInput,
  StartPlaybackFromDownloadInput
} from "../../shared/contracts/playback";
import { getDandanplayConfig } from "../config/dandanplay";
import { clampSeekTarget, HLS_SEEK_TAIL_SECONDS } from "../../shared/playerTiming";
import { BahamutDanmakuClient } from "../danmaku/bahamutDanmakuClient";
import {
  BilibiliDanmakuClient,
  type AutomaticDanmakuInput,
  type DirectDanmakuLoadResult
} from "../danmaku/bilibiliDanmakuClient";
import {
  DandanplayClient,
  type DandanplayLoadInput,
  type DandanplayLoadResult
} from "../danmaku/dandanplayClient";
import { DownloadRepository } from "../download/downloadRepository";
import { getDownloadRootDirectory } from "../download/downloadService";
import { getLocalMediaServer, type RegisterLocalMediaInput } from "../media/localMediaServer";
import { MediaProbe, type MediaProbeLike, type MediaProbeResult } from "../media/mediaProbe";
import { SubtitleService } from "../subtitle/subtitleService";
import { getBangumiService } from "../services/serviceFactory";
import { PlaybackRepository } from "./playbackRepository";

type PlaybackEventName = "session";

export type DanmakuLoaderLike = {
  loadForFile(input: DandanplayLoadInput): Promise<DandanplayLoadResult>;
  searchEpisodes(input: { anime: string }): Promise<DanmakuEpisodeSearchResult[]>;
  loadForEpisode(episodeId: number): Promise<DandanplayLoadResult>;
};

export type DirectDanmakuLoaderLike = {
  loadAutomatic(input: AutomaticDanmakuInput): Promise<DirectDanmakuLoadResult>;
  loadByLocator(locator: string): Promise<DirectDanmakuLoadResult>;
};

export type DanmakuContextResolverLike = {
  resolve(subjectId: number, episodeId: number): Promise<AutomaticDanmakuInput>;
};

const danmakuSourceDefinitions: Array<{ id: DanmakuSourceId; label: string }> = [
  { id: "dandanplay", label: "弹弹play" },
  { id: "bilibili", label: "Bilibili" },
  { id: "bahamut", label: "巴哈姆特动画疯" }
];

type LocalMediaServerLike = {
  registerMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView>;
  registerRemuxedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView>;
  registerTranscodedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView>;
  restartTranscodedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView>;
  restartRemuxedMediaFile(input: RegisterLocalMediaInput): Promise<PlaybackSourceView>;
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
  private startQueue: Promise<void> = Promise.resolve();
  private readonly pendingStarts = new Map<string, Promise<PlaybackSessionView>>();
  private readonly danmakuItemsBySource = new Map<
    DanmakuSourceId,
    PlaybackSessionView["danmaku"]
  >();
  private readonly danmakuSourceEnabled = new Map<DanmakuSourceId, boolean>(
    danmakuSourceDefinitions.map(({ id }) => [id, true])
  );

  constructor(
    private readonly repository = new DownloadRepository(),
    private readonly mediaServer: LocalMediaServerLike = getLocalMediaServer(),
    private readonly mediaProbe: MediaProbeLike = new MediaProbe(),
    private readonly subtitleService = new SubtitleService(mediaServer),
    private readonly playbackRepository = new PlaybackRepository(),
    private readonly danmakuLoader?: DanmakuLoaderLike,
    private readonly bilibiliDanmakuLoader: DirectDanmakuLoaderLike = new BilibiliDanmakuClient(),
    private readonly bahamutDanmakuLoader: DirectDanmakuLoaderLike = new BahamutDanmakuClient(),
    private readonly danmakuContextResolver: DanmakuContextResolverLike = createDanmakuContextResolver()
  ) {}

  onSession(callback: (session: PlaybackSessionView | null) => void): () => void {
    const listener = (): void => callback(this.session);
    this.events.on("session", listener);
    return () => this.events.off("session", listener);
  }

  async startFromDownload(input: StartPlaybackFromDownloadInput): Promise<PlaybackSessionView> {
    const media = this.resolveDownloadMedia(input);
    const task = this.repository.requireTask(input.downloadId);
    const hasEpisodeContext = task.subjectId !== null && task.episodeId !== null;
    return this.enqueuePlaybackStart(media, {
      downloadId: input.downloadId,
      subjectId: hasEpisodeContext ? task.subjectId : null,
      episodeId: hasEpisodeContext ? task.episodeId : null
    });
  }

  async startEpisode(input: EpisodePlaybackInput): Promise<PlaybackSessionView> {
    const task = this.repository
      .listTasks()
      .find(
        (candidate) =>
          candidate.subjectId === input.subjectId &&
          candidate.episodeId === input.episodeId &&
          (candidate.status === "completed" || candidate.status === "ready") &&
          candidate.selectedFileId
      );
    if (!task?.selectedFileId) {
      throw new Error("当前章节还没有下载完成的本地媒体文件。");
    }

    const media = this.resolveDownloadMedia({
      downloadId: task.id,
      fileId: task.selectedFileId
    });
    return this.enqueuePlaybackStart(media, {
      downloadId: task.id,
      subjectId: input.subjectId,
      episodeId: input.episodeId
    });
  }

  getEpisodeProgress(input: EpisodePlaybackInput): PlaybackProgressSnapshot | null {
    return this.playbackRepository.getProgress(input.subjectId, input.episodeId);
  }

  private enqueuePlaybackStart(
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
    const key = [
      context.downloadId,
      media.fileId,
      context.subjectId ?? "cache",
      context.episodeId ?? "cache"
    ].join(":");
    const pending = this.pendingStarts.get(key);
    if (pending) {
      return pending;
    }

    const start = this.startQueue.then(() => this.startPlaybackSession(media, context));
    this.startQueue = start.then(
      () => undefined,
      () => undefined
    );
    this.pendingStarts.set(key, start);
    void start.then(
      () => this.pendingStarts.delete(key),
      () => this.pendingStarts.delete(key)
    );
    return start;
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
    this.resetDanmakuSources();
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
      danmakuSources: this.createDanmakuSourceViews(),
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
      const mediaInfo = await this.probeMedia(media.path, media.title);
      const [source, subtitles] = await Promise.all([
        this.prepareSource(sourceInput, mediaInfo),
        this.subtitleService.prepareSubtitles({
          sessionId,
          mediaPath: media.path
        })
      ]);
      this.updateSession({
        status: "ready",
        source,
        subtitles,
        durationSeconds: mediaInfo.durationSeconds,
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

  async loadDanmaku(sessionId: string): Promise<PlaybackSessionView> {
    const session = this.requireSession(sessionId);
    if (session.status === "stopped" || session.status === "failed" || !session.source) {
      throw new Error("当前播放会话无法加载弹幕。");
    }
    const media =
      session.downloadId && session.fileId
        ? this.resolveDownloadMedia({ downloadId: session.downloadId, fileId: session.fileId })
        : null;
    const enabledSources = session.danmakuSources
      .filter((source) => source.enabled)
      .map((source) => source.id);
    const context = enabledSources.some((providerId) => providerId !== "dandanplay")
      ? this.resolveAutomaticDanmakuContext(session)
      : null;
    await Promise.allSettled(
      enabledSources.map((providerId) =>
        this.loadDanmakuSourceAutomatically(sessionId, providerId, media, context)
      )
    );
    return this.requireSession(sessionId);
  }

  async searchDanmakuEpisodes(
    input: DanmakuEpisodeSearchInput
  ): Promise<DanmakuEpisodeSearchResult[]> {
    this.requirePlayableSession(input.sessionId);
    const loader = this.danmakuLoader ?? createConfiguredDanmakuLoader();
    return loader.searchEpisodes({ anime: input.anime });
  }

  async selectDanmakuEpisode(input: SelectDanmakuEpisodeInput): Promise<PlaybackSessionView> {
    this.requirePlayableSession(input.sessionId);
    this.setDanmakuSourceState(input.sessionId, "dandanplay", {
      status: "loading",
      errorMessage: null
    });
    const loader = this.danmakuLoader ?? createConfiguredDanmakuLoader();
    try {
      const result = await loader.loadForEpisode(input.episodeId);
      return this.applyDanmakuSourceResult(input.sessionId, "dandanplay", {
        items: result.items,
        matchLabel:
          [result.animeTitle, result.episodeTitle].filter(Boolean).join(" · ") ||
          `弹弹play剧集 ${input.episodeId}`
      });
    } catch (error) {
      this.setDanmakuSourceFailure(input.sessionId, "dandanplay", error);
      throw error;
    }
  }

  async loadDanmakuSource(input: LoadDanmakuSourceInput): Promise<PlaybackSessionView> {
    this.requirePlayableSession(input.sessionId);
    this.setDanmakuSourceState(input.sessionId, input.providerId, {
      status: "loading",
      errorMessage: null
    });
    const loader =
      input.providerId === "bilibili" ? this.bilibiliDanmakuLoader : this.bahamutDanmakuLoader;
    try {
      const result = await loader.loadByLocator(input.locator);
      return this.applyDanmakuSourceResult(input.sessionId, input.providerId, result);
    } catch (error) {
      this.setDanmakuSourceFailure(input.sessionId, input.providerId, error);
      throw error;
    }
  }

  async setDanmakuSourceEnabled(input: SetDanmakuSourceEnabledInput): Promise<PlaybackSessionView> {
    const session = this.requirePlayableSession(input.sessionId);
    this.danmakuSourceEnabled.set(input.providerId, input.enabled);
    this.setDanmakuSourceState(input.sessionId, input.providerId, { enabled: input.enabled });
    if (
      input.enabled &&
      !this.danmakuItemsBySource.has(input.providerId) &&
      session.danmakuSources.find((source) => source.id === input.providerId)?.status !== "loading"
    ) {
      const media =
        session.downloadId && session.fileId
          ? this.resolveDownloadMedia({ downloadId: session.downloadId, fileId: session.fileId })
          : null;
      await this.loadDanmakuSourceAutomatically(
        input.sessionId,
        input.providerId,
        media,
        input.providerId === "dandanplay" ? null : this.resolveAutomaticDanmakuContext(session)
      );
    }
    return this.requireSession(input.sessionId);
  }

  private async loadDanmakuSourceAutomatically(
    sessionId: string,
    providerId: DanmakuSourceId,
    media: { path: string } | null,
    context: Promise<AutomaticDanmakuInput> | null
  ): Promise<void> {
    this.setDanmakuSourceState(sessionId, providerId, {
      status: "loading",
      errorMessage: null
    });
    try {
      if (providerId === "dandanplay") {
        if (!media) throw new Error("当前播放会话没有可用于弹弹play匹配的本地媒体。");
        const loader = this.danmakuLoader ?? createConfiguredDanmakuLoader();
        const session = this.requireSession(sessionId);
        const result = await loader.loadForFile({
          filePath: media.path,
          videoDurationSeconds: session.durationSeconds
        });
        this.applyDanmakuSourceResult(sessionId, providerId, {
          items: result.items,
          matchLabel:
            [result.animeTitle, result.episodeTitle].filter(Boolean).join(" · ") ||
            `弹弹play剧集 ${result.episodeId}`
        });
        return;
      }

      if (!context) throw new Error("当前播放会话没有可用于自动匹配的章节信息。");
      const resolvedContext = await context;
      const loader =
        providerId === "bilibili" ? this.bilibiliDanmakuLoader : this.bahamutDanmakuLoader;
      const result = await loader.loadAutomatic(resolvedContext);
      this.applyDanmakuSourceResult(sessionId, providerId, result);
    } catch (error) {
      this.setDanmakuSourceFailure(sessionId, providerId, error);
    }
  }

  private applyDanmakuSourceResult(
    sessionId: string,
    providerId: DanmakuSourceId,
    result: { items: PlaybackSessionView["danmaku"]; matchLabel: string }
  ): PlaybackSessionView {
    this.requireSession(sessionId);
    this.danmakuItemsBySource.set(providerId, result.items);
    this.setDanmakuSourceState(sessionId, providerId, {
      status: "ready",
      count: result.items.length,
      matchLabel: result.matchLabel,
      errorMessage: null
    });
    return this.requireSession(sessionId);
  }

  private setDanmakuSourceFailure(
    sessionId: string,
    providerId: DanmakuSourceId,
    error: unknown
  ): void {
    this.requireSession(sessionId);
    this.danmakuItemsBySource.delete(providerId);
    this.setDanmakuSourceState(sessionId, providerId, {
      status: "error",
      count: 0,
      matchLabel: null,
      errorMessage: toDanmakuError(error, providerId)
    });
  }

  private setDanmakuSourceState(
    sessionId: string,
    providerId: DanmakuSourceId,
    patch: Partial<DanmakuSourceView>
  ): void {
    const session = this.requireSession(sessionId);
    const danmakuSources = session.danmakuSources.map((source) =>
      source.id === providerId ? { ...source, ...patch, id: source.id } : source
    );
    this.updateSession({
      danmakuSources,
      danmaku: this.combineEnabledDanmaku(danmakuSources)
    });
  }

  private combineEnabledDanmaku(sources: DanmakuSourceView[]): PlaybackSessionView["danmaku"] {
    const seen = new Set<string>();
    return sources
      .filter((source) => source.enabled)
      .flatMap((source) =>
        (this.danmakuItemsBySource.get(source.id) ?? []).map((item) => ({
          ...item,
          sourceId: source.id
        }))
      )
      .filter((item) => {
        const key = `${Math.round(item.timeSeconds * 1000)}\u0000${item.mode}\u0000${item.color}\u0000${item.text}`;
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      })
      .sort((left, right) => left.timeSeconds - right.timeSeconds);
  }

  private createDanmakuSourceViews(): DanmakuSourceView[] {
    return danmakuSourceDefinitions.map(({ id, label }) => ({
      id,
      label,
      enabled: this.danmakuSourceEnabled.get(id) ?? true,
      status: "idle",
      count: 0,
      matchLabel: null,
      errorMessage: null
    }));
  }

  private resetDanmakuSources(): void {
    this.danmakuItemsBySource.clear();
  }

  private resolveAutomaticDanmakuContext(
    session: PlaybackSessionView
  ): Promise<AutomaticDanmakuInput> {
    if (!session.subjectId || !session.episodeId) {
      return Promise.reject(
        new Error("当前视频未关联 Bangumi 章节，请手动输入该弹幕源的剧集编号。")
      );
    }
    return this.danmakuContextResolver.resolve(session.subjectId, session.episodeId);
  }

  async seek(input: SeekPlaybackInput): Promise<PlaybackSessionView> {
    const session = this.requireSession(input.sessionId);
    if (session.status === "stopped" || session.status === "failed" || !session.source) {
      throw new Error("当前播放会话无法跳转。");
    }

    if (session.source.deliveryMode === "direct") {
      throw new Error("当前播放源应由播放器直接跳转。");
    }

    if (!session.downloadId || !session.fileId) {
      throw new Error("当前播放源无法重新定位本地媒体文件。");
    }

    const positionSeconds = clampSeekTarget(input.positionSeconds, session.durationSeconds);
    const media = this.resolveDownloadMedia({
      downloadId: session.downloadId,
      fileId: session.fileId
    });
    const restartInput = {
      sessionId: session.id,
      filePath: media.path,
      title: media.title,
      startSeconds: positionSeconds
    };
    const source =
      session.source.deliveryMode === "remux"
        ? await this.mediaServer.restartRemuxedMediaFile(restartInput)
        : await this.mediaServer.restartTranscodedMediaFile(restartInput);
    this.updateSession({
      status: "ready",
      source,
      positionSeconds,
      errorMessage: null
    });
    return this.requireSession(input.sessionId);
  }

  updateProgress(input: PlaybackProgressInput): PlaybackSessionView {
    const session = this.requireSession(input.sessionId);
    if (session.status === "stopped" || session.status === "failed") {
      return session;
    }

    if (!session.source || input.timelineOffsetSeconds !== session.source.timelineOffsetSeconds) {
      return session;
    }

    // Prepared HLS media elements only see the already-generated part of the
    // stream, so their reported duration is a growing partial value; adopt the
    // media element duration for direct playback only.
    const reportedDuration =
      session.source.deliveryMode === "direct" &&
      input.durationSeconds &&
      input.durationSeconds > 0
        ? input.durationSeconds
        : null;
    this.updateSession({
      status: input.ended ? "ended" : input.paused ? "paused" : "playing",
      positionSeconds: Math.max(0, input.positionSeconds),
      durationSeconds: session.durationSeconds ?? reportedDuration
    });

    const nextSession = this.requireSession(input.sessionId);
    if (nextSession.subjectId !== null && nextSession.episodeId !== null) {
      // A stream restarted right at the clamped tail ends within seconds even
      // when the user merely dragged the progress bar to the end; that ending
      // should not mark the episode as watched.
      const tailOnlyStream =
        session.source.timelineOffsetSeconds > 0 &&
        nextSession.durationSeconds !== null &&
        nextSession.durationSeconds - session.source.timelineOffsetSeconds <=
          HLS_SEEK_TAIL_SECONDS + 0.25;
      try {
        this.playbackRepository.saveProgress({
          subjectId: nextSession.subjectId,
          episodeId: nextSession.episodeId,
          positionSeconds: nextSession.positionSeconds,
          durationSeconds: nextSession.durationSeconds,
          completed: input.ended && !tailOnlyStream,
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

  private async probeMedia(filePath: string, title: string): Promise<MediaProbeResult> {
    try {
      return await this.mediaProbe.probe(filePath);
    } catch {
      return fallbackMediaProbe(filePath, title);
    }
  }

  private async prepareSource(
    input: RegisterLocalMediaInput,
    mediaInfo: MediaProbeResult
  ): Promise<PlaybackSourceView> {
    if (mediaInfo.deliveryMode === "remux") {
      return this.mediaServer.registerRemuxedMediaFile(input);
    }

    if (mediaInfo.deliveryMode === "transcode") {
      return this.mediaServer.registerTranscodedMediaFile(input);
    }

    return this.mediaServer.registerMediaFile(input);
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

  private requirePlayableSession(sessionId: string): PlaybackSessionView {
    const session = this.requireSession(sessionId);
    if (session.status === "stopped" || session.status === "failed" || !session.source) {
      throw new Error("当前播放会话无法加载弹幕。");
    }
    return session;
  }

  private updateSession(
    patch: Partial<
      Pick<
        PlaybackSessionView,
        | "status"
        | "source"
        | "subtitles"
        | "danmaku"
        | "danmakuSources"
        | "subjectId"
        | "episodeId"
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

function createConfiguredDanmakuLoader(): DanmakuLoaderLike {
  const config = getDandanplayConfig();
  if (!config) {
    throw new Error(
      "弹弹play未配置。请设置 DANDANPLAY_APP_ID 和 DANDANPLAY_APP_SECRET，或在开发环境创建 temp/dandanplay.json。"
    );
  }
  return new DandanplayClient(config);
}

function toDanmakuError(error: unknown, providerId: DanmakuSourceId): string {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  const label = danmakuSourceDefinitions.find((source) => source.id === providerId)?.label;
  return `${label ?? "弹幕源"}加载失败，视频播放不受影响。`;
}

function createDanmakuContextResolver(): DanmakuContextResolverLike {
  return {
    async resolve(subjectId, episodeId) {
      const service = getBangumiService();
      const subject =
        (await service.getCachedSubject(subjectId).catch(() => null)) ??
        (await service.getSubject(subjectId));
      const episode = subject.episodes.find((candidate) => candidate.episodeId === episodeId);
      if (!episode) {
        throw new Error("当前 Bangumi 章节信息不完整，请手动输入弹幕源剧集编号。");
      }
      const animeTitles = [subject.nameCn, subject.name].filter((title): title is string =>
        Boolean(title?.trim())
      );
      if (animeTitles.length === 0) {
        throw new Error("当前番剧缺少可用于自动匹配的标题，请手动输入弹幕源剧集编号。");
      }
      return { animeTitles, episodeNumber: episode.sort };
    }
  };
}

function toRendererSafeError(error: unknown): string {
  if (error instanceof Error) {
    return error.message || "播放请求失败。";
  }

  return "播放请求失败。";
}

function fallbackMediaProbe(filePath: string, title: string): MediaProbeResult {
  const extension = extname(filePath).toLowerCase();
  const likelyNeedsTranscode =
    [".mkv", ".avi", ".flv", ".wmv"].includes(extension) ||
    /\b(hevc|h\.?265|x265|10bit|hi10p)\b/i.test(title);
  return {
    durationSeconds: null,
    videoCodec: "unknown",
    audioCodec: null,
    deliveryMode: likelyNeedsTranscode ? "transcode" : "direct"
  };
}
