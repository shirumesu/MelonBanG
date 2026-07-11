import { EventEmitter } from "node:events";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { isAbsolute, join, relative, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import type {
  DownloadSnapshot,
  DownloadStatus,
  DownloadTaskView,
  TorrentInput
} from "../../shared/contracts/download";
import { getAppDataDirectory } from "../store/appDatabase";
import {
  DownloadRepository,
  type PersistedDownloadSession,
  type PersistedFileInput
} from "./downloadRepository";
import {
  type AddTorrentRuntimeOptions,
  type TorrentHandle,
  type TorrentMetadata,
  type TorrentRuntimeFile,
  type TorrentRuntimeStats
} from "./torrentClient";
import { WhatsLinkClient, type DownloadPreviewMetadata } from "./whatsLinkClient";
import { VideoThumbnailGenerator, type VideoThumbnailGeneratorLike } from "./videoThumbnail";

type DownloadEventName = "snapshot";

const progressPersistIntervalMs = 800;

let serviceInstance: DownloadService | null = null;

type TorrentClientLike = {
  addTorrent(options: AddTorrentRuntimeOptions): TorrentHandle | Promise<TorrentHandle>;
};
type PreviewClientLike = {
  getPreview(input: TorrentInput): Promise<DownloadPreviewMetadata | null>;
};

export function getDownloadService(): DownloadService {
  serviceInstance ??= new DownloadService();
  return serviceInstance;
}

export class DownloadService {
  private readonly events = new EventEmitter();
  private readonly activeHandles = new Map<string, TorrentHandle>();
  private readonly lastProgressPersistedAt = new Map<string, number>();
  private readonly previewRefreshAttempted = new Set<string>();

  constructor(
    private readonly repository = new DownloadRepository(),
    private readonly torrentClient: TorrentClientLike = createLazyTorrentClient(),
    private readonly previewClient: PreviewClientLike = new WhatsLinkClient(),
    private readonly thumbnailGenerator: VideoThumbnailGeneratorLike = new VideoThumbnailGenerator()
  ) {
    this.repository.markInterruptedSessionsPaused();
  }

  onSnapshot(callback: (snapshot: DownloadSnapshot) => void): () => void {
    const listener = (): void => callback(this.list());
    this.events.on("snapshot", listener);
    return () => this.events.off("snapshot", listener);
  }

  create(input: TorrentInput): DownloadTaskView {
    const validInput = validateTorrentInput(input);
    const id = randomUUID();
    const now = new Date().toISOString();
    const task = this.repository.createSession({
      id,
      inputKind: validInput.kind,
      inputRef: serializeTorrentInput(validInput),
      title: inferInitialTitle(validInput),
      status: "metadata",
      createdAt: now,
      updatedAt: now
    });

    this.emitSnapshot();
    void this.refreshPreview(task.id, validInput);
    void this.startSession({
      ...task,
      inputKind: validInput.kind,
      inputRef: serializeTorrentInput(validInput)
    });
    return task;
  }

  list(): DownloadSnapshot {
    const snapshot = this.repository.listSnapshot();
    for (const task of snapshot.tasks) {
      if (
        (task.status === "completed" || task.status === "ready") &&
        (!task.previewImageUrl || /^https?:\/\//i.test(task.previewImageUrl))
      ) {
        this.schedulePersistedPreviewRefresh(task.id);
      }
    }
    return snapshot;
  }

  pause(downloadId: string): DownloadTaskView {
    const task = this.repository.requireTask(downloadId);
    const handle = this.activeHandles.get(downloadId);
    handle?.pause();
    const updated = this.repository.updateSession(task.id, {
      status: "paused",
      downloadSpeedBytesPerSecond: 0,
      uploadSpeedBytesPerSecond: 0,
      peerCount: 0,
      etaSeconds: null
    });
    this.emitSnapshot();
    return updated;
  }

  resume(downloadId: string): DownloadTaskView {
    const session = this.repository.getSession(downloadId);
    if (!session) {
      throw new Error("下载任务不存在。");
    }

    if (session.status === "completed") {
      return session;
    }

    const handle = this.activeHandles.get(downloadId);
    if (handle) {
      handle.resume();
      const updated = this.repository.updateSession(downloadId, {
        status: session.selectedFileId ? "downloading" : "metadata",
        errorMessage: null
      });
      this.emitSnapshot();
      return updated;
    }

    const updated = this.repository.updateSession(downloadId, {
      status: session.selectedFileId ? "downloading" : "metadata",
      errorMessage: null
    });
    void this.startSession(this.repository.getSession(downloadId) ?? session);
    this.emitSnapshot();
    return updated;
  }

  async remove(downloadId: string): Promise<void> {
    const handle = this.activeHandles.get(downloadId);
    if (handle) {
      await handle.remove();
      this.activeHandles.delete(downloadId);
    }

    removeDownloadDirectory(downloadId);
    this.repository.removeSession(downloadId);
    this.emitSnapshot();
  }

  private async startSession(session: PersistedDownloadSession): Promise<void> {
    try {
      const input = deserializeTorrentInput(session);
      const downloadPath = join(getDownloadRootDirectory(), session.id);
      mkdirSync(downloadPath, { recursive: true });

      const handleOrPromise = this.torrentClient.addTorrent({
        input,
        downloadPath,
        onMetadata: (metadata) => this.handleMetadata(session.id, metadata),
        onProgress: (stats, files) => this.handleProgress(session.id, stats, files),
        onDone: (stats, files) => this.handleDone(session.id, stats, files),
        onError: (error) => this.handleError(session.id, error)
      });
      const handle = isPromiseLike(handleOrPromise) ? await handleOrPromise : handleOrPromise;

      this.activeHandles.set(session.id, handle);
    } catch (error) {
      this.handleError(session.id, toError(error));
    }
  }

  private handleMetadata(downloadId: string, metadata: TorrentMetadata): void {
    const session = this.repository.getSession(downloadId);
    if (!session) {
      this.activeHandles.delete(downloadId);
      return;
    }

    const now = new Date().toISOString();
    const selectedFileId =
      metadata.selectedFileIndex === null
        ? null
        : createFileId(downloadId, metadata.selectedFileIndex);
    const nextStatus: DownloadStatus = selectedFileId
      ? session.status === "paused"
        ? "paused"
        : "downloading"
      : "failed";
    const files = metadata.files.map<PersistedFileInput>((file) => ({
      id: createFileId(downloadId, file.index),
      downloadId,
      path: file.path,
      name: file.name,
      sizeBytes: file.sizeBytes,
      mediaKind: file.mediaKind,
      priority: selectedFileId === createFileId(downloadId, file.index) ? 1 : 0,
      progress: file.progress,
      createdAt: now,
      updatedAt: now
    }));

    this.repository.replaceFiles(downloadId, files);
    this.repository.updateSession(downloadId, {
      title: metadata.title,
      status: nextStatus,
      progress: metadata.stats.progress,
      downloadedBytes: metadata.stats.downloadedBytes,
      totalBytes: metadata.stats.totalBytes || null,
      downloadSpeedBytesPerSecond:
        nextStatus === "paused" ? 0 : metadata.stats.downloadSpeedBytesPerSecond,
      uploadSpeedBytesPerSecond:
        nextStatus === "paused" ? 0 : metadata.stats.uploadSpeedBytesPerSecond,
      peerCount: nextStatus === "paused" ? 0 : metadata.stats.peerCount,
      etaSeconds: nextStatus === "paused" ? null : estimateEtaSeconds(metadata.stats),
      selectedFileId,
      errorMessage: selectedFileId ? null : "种子里没有可下载文件。"
    });
    this.emitSnapshot();
  }

  private handleProgress(
    downloadId: string,
    stats: TorrentRuntimeStats,
    files: TorrentRuntimeFile[]
  ): void {
    const session = this.repository.getSession(downloadId);
    if (!session) {
      this.activeHandles.delete(downloadId);
      return;
    }
    if (session.status === "failed" || session.status === "completed") {
      return;
    }

    const now = Date.now();
    const lastPersistedAt = this.lastProgressPersistedAt.get(downloadId) ?? 0;
    if (!stats.done && now - lastPersistedAt < progressPersistIntervalMs) {
      return;
    }

    this.lastProgressPersistedAt.set(downloadId, now);
    this.persistRuntimeState(
      downloadId,
      stats.done ? "completed" : "downloading",
      stats,
      files,
      null
    );
  }

  private handleDone(
    downloadId: string,
    stats: TorrentRuntimeStats,
    files: TorrentRuntimeFile[]
  ): void {
    if (!this.repository.getSession(downloadId)) {
      this.activeHandles.delete(downloadId);
      return;
    }

    this.persistRuntimeState(downloadId, "completed", stats, files, null);
    this.activeHandles.delete(downloadId);
    void this.ensureLocalPreview(downloadId);
  }

  private handleError(downloadId: string, error: Error): void {
    if (!this.repository.getSession(downloadId)) {
      this.activeHandles.delete(downloadId);
      return;
    }

    this.repository.updateSession(downloadId, {
      status: "failed",
      downloadSpeedBytesPerSecond: 0,
      uploadSpeedBytesPerSecond: 0,
      peerCount: 0,
      etaSeconds: null,
      errorMessage: toRendererSafeError(error)
    });
    this.activeHandles.delete(downloadId);
    this.emitSnapshot();
  }

  private persistRuntimeState(
    downloadId: string,
    status: DownloadStatus,
    stats: TorrentRuntimeStats,
    files: TorrentRuntimeFile[],
    errorMessage: string | null
  ): void {
    const session = this.repository.getSession(downloadId);
    if (!session) {
      this.activeHandles.delete(downloadId);
      return;
    }

    const nextStatus = session.status === "paused" && status !== "completed" ? "paused" : status;

    for (const file of files) {
      this.repository.updateFileProgress(createFileId(downloadId, file.index), file.progress);
    }

    this.repository.updateSession(downloadId, {
      title: stats.title,
      status: nextStatus,
      progress: stats.done ? 1 : stats.progress,
      downloadedBytes: stats.downloadedBytes,
      totalBytes: stats.totalBytes || null,
      downloadSpeedBytesPerSecond:
        nextStatus === "completed" || nextStatus === "paused"
          ? 0
          : stats.downloadSpeedBytesPerSecond,
      uploadSpeedBytesPerSecond:
        nextStatus === "completed" || nextStatus === "paused" ? 0 : stats.uploadSpeedBytesPerSecond,
      peerCount: nextStatus === "completed" || nextStatus === "paused" ? 0 : stats.peerCount,
      etaSeconds:
        nextStatus === "completed" || nextStatus === "paused" ? null : estimateEtaSeconds(stats),
      errorMessage
    });
    this.emitSnapshot();
  }

  private async refreshPreview(downloadId: string, input: TorrentInput): Promise<void> {
    const preview = await this.previewClient.getPreview(input);
    if (!preview || !this.repository.getSession(downloadId)) {
      return;
    }

    this.repository.updateSession(downloadId, {
      title: preview.title,
      totalBytes: preview.totalBytes,
      previewImageUrl: preview.imageUrl,
      previewSourceName: preview.sourceName,
      previewSourceUrl: preview.sourceUrl
    });
    this.emitSnapshot();
  }

  private schedulePersistedPreviewRefresh(downloadId: string): void {
    if (this.previewRefreshAttempted.has(downloadId)) {
      return;
    }
    this.previewRefreshAttempted.add(downloadId);

    const session = this.repository.getSession(downloadId);
    if (!session) {
      return;
    }
    void (async () => {
      if (session.inputKind === "magnet") {
        await this.refreshPreview(downloadId, deserializeTorrentInput(session));
      }
      await this.ensureLocalPreview(downloadId);
    })();
  }

  private async ensureLocalPreview(downloadId: string): Promise<void> {
    const session = this.repository.getSession(downloadId);
    if (
      !session ||
      (session.status !== "completed" && session.status !== "ready") ||
      isDurablePreviewImage(session.previewImageUrl)
    ) {
      return;
    }

    const selectedFile = this.repository
      .listFiles(downloadId)
      .find((file) => file.id === session.selectedFileId && file.mediaKind === "video");
    if (!selectedFile) {
      return;
    }

    const mediaPath = resolveDownloadFilePath(downloadId, selectedFile.path);
    if (!existsSync(mediaPath)) {
      return;
    }

    try {
      const imageUrl = await this.thumbnailGenerator.generate(mediaPath);
      const current = this.repository.getSession(downloadId);
      if (!current || isDurablePreviewImage(current.previewImageUrl)) {
        return;
      }
      this.repository.updateSession(downloadId, { previewImageUrl: imageUrl });
      this.emitSnapshot();
    } catch {
      // A missing thumbnail must not change download completion or playback availability.
    }
  }

  private emitSnapshot(): void {
    this.events.emit("snapshot" satisfies DownloadEventName);
  }
}

export function getDownloadRootDirectory(): string {
  return join(getAppDataDirectory(), "downloads");
}

export function validateTorrentInput(input: TorrentInput): TorrentInput {
  if (input.kind === "magnet") {
    const uri = input.uri.trim();
    if (!isValidMagnetUri(uri)) {
      throw new Error("请输入有效的 magnet 链接。");
    }

    return { kind: "magnet", uri };
  }

  if (!input.name.trim()) {
    throw new Error("种子文件名称不能为空。");
  }

  if (!(input.bytes instanceof Uint8Array) || input.bytes.byteLength === 0) {
    throw new Error("种子文件内容不能为空。");
  }

  return {
    kind: "torrentFile",
    name: input.name.trim(),
    bytes: input.bytes
  };
}

function serializeTorrentInput(input: TorrentInput): string {
  if (input.kind === "magnet") {
    return input.uri;
  }

  return Buffer.from(input.bytes).toString("base64");
}

function deserializeTorrentInput(session: PersistedDownloadSession): TorrentInput {
  if (session.inputKind === "magnet") {
    return { kind: "magnet", uri: session.inputRef };
  }

  return {
    kind: "torrentFile",
    name: session.title,
    bytes: Uint8Array.from(Buffer.from(session.inputRef, "base64"))
  };
}

function isValidMagnetUri(value: string): boolean {
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== "magnet:") {
      return false;
    }

    const exactTopic = parsed.searchParams.get("xt") ?? "";
    return /^urn:btih:(?:[a-z2-7]{32}|[a-f0-9]{40})$/i.test(exactTopic);
  } catch {
    return false;
  }
}

function inferInitialTitle(input: TorrentInput): string {
  if (input.kind === "torrentFile") {
    return input.name;
  }

  try {
    const parsed = new URL(input.uri);
    const displayName = parsed.searchParams.get("dn")?.trim();
    if (displayName) {
      return displayName;
    }

    const exactTopic = parsed.searchParams.get("xt") ?? "";
    const hash = exactTopic.replace(/^urn:btih:/i, "");
    return hash ? `BT ${hash.slice(0, 8).toUpperCase()}` : "BT 下载任务";
  } catch {
    return "BT 下载任务";
  }
}

function createFileId(downloadId: string, fileIndex: number): string {
  return `${downloadId}:${fileIndex}`;
}

function estimateEtaSeconds(stats: TorrentRuntimeStats): number | null {
  if (stats.done || stats.downloadSpeedBytesPerSecond <= 0 || stats.totalBytes <= 0) {
    return null;
  }

  const remainingBytes = Math.max(0, stats.totalBytes - stats.downloadedBytes);
  return Math.ceil(remainingBytes / stats.downloadSpeedBytesPerSecond);
}

function removeDownloadDirectory(downloadId: string): void {
  const root = resolve(getDownloadRootDirectory());
  const target = resolve(root, downloadId);
  const targetRelativeToRoot = relative(root, target);
  if (
    targetRelativeToRoot.length === 0 ||
    targetRelativeToRoot.startsWith("..") ||
    isAbsolute(targetRelativeToRoot)
  ) {
    throw new Error("拒绝删除下载根目录之外的文件。");
  }

  rmSync(target, { recursive: true, force: true });
}

function resolveDownloadFilePath(downloadId: string, filePath: string): string {
  const downloadRoot = resolve(getDownloadRootDirectory(), downloadId);
  const target = resolve(downloadRoot, filePath);
  const targetRelativeToRoot = relative(downloadRoot, target);
  if (
    targetRelativeToRoot.length === 0 ||
    targetRelativeToRoot.startsWith("..") ||
    isAbsolute(targetRelativeToRoot)
  ) {
    throw new Error("拒绝读取下载目录之外的媒体文件。");
  }
  return target;
}

function isDurablePreviewImage(value: string | null): boolean {
  return Boolean(value?.startsWith("data:image/"));
}

let lazyTorrentClientPromise: Promise<TorrentClientLike> | null = null;

function createLazyTorrentClient(): TorrentClientLike {
  return {
    async addTorrent(options) {
      lazyTorrentClientPromise ??= import("./torrentClient").then(
        ({ TorrentClientAdapter }) => new TorrentClientAdapter()
      );
      const client = await lazyTorrentClientPromise;
      return client.addTorrent(options);
    }
  };
}

function isPromiseLike<T>(value: T | Promise<T>): value is Promise<T> {
  return typeof (value as Promise<T>).then === "function";
}

function toRendererSafeError(error: Error): string {
  return error.message || "下载任务失败。";
}

function toError(error: unknown): Error {
  return error instanceof Error ? error : new Error(String(error));
}
