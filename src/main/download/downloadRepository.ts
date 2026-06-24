import type {
  DownloadFileView,
  DownloadSnapshot,
  DownloadStatus,
  DownloadTaskView
} from "../../shared/contracts/download";
import { getAppDatabase } from "../store/appDatabase";

type DownloadSessionRow = {
  id: string;
  input_kind: string;
  input_ref: string;
  title: string;
  status: DownloadStatus;
  progress: number;
  downloaded_bytes: number;
  total_bytes: number | null;
  download_speed_bytes_per_second: number;
  upload_speed_bytes_per_second: number;
  peer_count: number;
  eta_seconds: number | null;
  selected_file_id: string | null;
  error_message: string | null;
  preview_image_url: string | null;
  preview_source_name: string | null;
  preview_source_url: string | null;
  created_at: string;
  updated_at: string;
};

type DownloadFileRow = {
  id: string;
  download_id: string;
  path: string;
  name: string;
  size_bytes: number;
  media_kind: DownloadFileView["mediaKind"];
  priority: number;
  progress: number;
  created_at: string;
  updated_at: string;
};

export type PersistedDownloadSession = DownloadTaskView & {
  inputKind: "magnet" | "torrentFile";
  inputRef: string;
};

export type NewDownloadSession = {
  id: string;
  inputKind: PersistedDownloadSession["inputKind"];
  inputRef: string;
  title: string;
  status: DownloadStatus;
  createdAt: string;
  updatedAt: string;
};

export type DownloadSessionPatch = Partial<{
  title: string;
  status: DownloadStatus;
  progress: number;
  downloadedBytes: number;
  totalBytes: number | null;
  downloadSpeedBytesPerSecond: number;
  uploadSpeedBytesPerSecond: number;
  peerCount: number;
  etaSeconds: number | null;
  selectedFileId: string | null;
  errorMessage: string | null;
  previewImageUrl: string | null;
  previewSourceName: string | null;
  previewSourceUrl: string | null;
}>;

export type PersistedFileInput = {
  id: string;
  downloadId: string;
  path: string;
  name: string;
  sizeBytes: number;
  mediaKind: DownloadFileView["mediaKind"];
  priority: number;
  progress: number;
  createdAt: string;
  updatedAt: string;
};

export class DownloadRepository {
  createSession(input: NewDownloadSession): DownloadTaskView {
    getAppDatabase()
      .prepare(
        `
        INSERT INTO download_sessions (
          id,
          input_kind,
          input_ref,
          title,
          status,
          created_at,
          updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `
      )
      .run(
        input.id,
        input.inputKind,
        input.inputRef,
        input.title,
        input.status,
        input.createdAt,
        input.updatedAt
      );

    return this.requireTask(input.id);
  }

  listSnapshot(): DownloadSnapshot {
    return {
      tasks: this.listTasks(),
      files: this.listFiles()
    };
  }

  listTasks(): DownloadTaskView[] {
    const rows = getAppDatabase()
      .prepare(
        `
        SELECT *
        FROM download_sessions
        WHERE status <> 'removed'
        ORDER BY created_at DESC
      `
      )
      .all() as DownloadSessionRow[];

    return rows.map(toTaskView);
  }

  listSessions(): PersistedDownloadSession[] {
    const rows = getAppDatabase()
      .prepare(
        `
        SELECT *
        FROM download_sessions
        WHERE status <> 'removed'
        ORDER BY created_at DESC
      `
      )
      .all() as DownloadSessionRow[];

    return rows.map(toPersistedSession);
  }

  getSession(downloadId: string): PersistedDownloadSession | null {
    const row = getAppDatabase()
      .prepare(
        `
        SELECT *
        FROM download_sessions
        WHERE id = ? AND status <> 'removed'
      `
      )
      .get(downloadId) as DownloadSessionRow | undefined;

    return row ? toPersistedSession(row) : null;
  }

  requireTask(downloadId: string): DownloadTaskView {
    const session = this.getSession(downloadId);
    if (!session) {
      throw new Error("下载任务不存在。");
    }

    return session;
  }

  updateSession(downloadId: string, patch: DownloadSessionPatch): DownloadTaskView {
    const existing = this.getSession(downloadId);
    if (!existing) {
      throw new Error("下载任务不存在。");
    }

    const next = {
      title: patch.title ?? existing.title,
      status: patch.status ?? existing.status,
      progress: patch.progress ?? existing.progress,
      downloadedBytes: patch.downloadedBytes ?? existing.downloadedBytes,
      totalBytes: patch.totalBytes === undefined ? existing.totalBytes : patch.totalBytes,
      downloadSpeedBytesPerSecond:
        patch.downloadSpeedBytesPerSecond ?? existing.downloadSpeedBytesPerSecond,
      uploadSpeedBytesPerSecond:
        patch.uploadSpeedBytesPerSecond ?? existing.uploadSpeedBytesPerSecond,
      peerCount: patch.peerCount ?? existing.peerCount,
      etaSeconds: patch.etaSeconds === undefined ? existing.etaSeconds : patch.etaSeconds,
      selectedFileId:
        patch.selectedFileId === undefined ? existing.selectedFileId : patch.selectedFileId,
      errorMessage: patch.errorMessage === undefined ? existing.errorMessage : patch.errorMessage,
      previewImageUrl:
        patch.previewImageUrl === undefined ? existing.previewImageUrl : patch.previewImageUrl,
      previewSourceName:
        patch.previewSourceName === undefined
          ? existing.previewSourceName
          : patch.previewSourceName,
      previewSourceUrl:
        patch.previewSourceUrl === undefined ? existing.previewSourceUrl : patch.previewSourceUrl,
      updatedAt: new Date().toISOString()
    };

    getAppDatabase()
      .prepare(
        `
        UPDATE download_sessions
        SET
          title = ?,
          status = ?,
          progress = ?,
          downloaded_bytes = ?,
          total_bytes = ?,
          download_speed_bytes_per_second = ?,
          upload_speed_bytes_per_second = ?,
          peer_count = ?,
          eta_seconds = ?,
          selected_file_id = ?,
          error_message = ?,
          preview_image_url = ?,
          preview_source_name = ?,
          preview_source_url = ?,
          updated_at = ?
        WHERE id = ?
      `
      )
      .run(
        next.title,
        next.status,
        next.progress,
        next.downloadedBytes,
        next.totalBytes,
        next.downloadSpeedBytesPerSecond,
        next.uploadSpeedBytesPerSecond,
        next.peerCount,
        next.etaSeconds,
        next.selectedFileId,
        next.errorMessage,
        next.previewImageUrl,
        next.previewSourceName,
        next.previewSourceUrl,
        next.updatedAt,
        downloadId
      );

    return this.requireTask(downloadId);
  }

  replaceFiles(downloadId: string, files: PersistedFileInput[]): DownloadFileView[] {
    const database = getAppDatabase();
    database.prepare("DELETE FROM download_files WHERE download_id = ?").run(downloadId);

    const statement = database.prepare(
      `
      INSERT INTO download_files (
        id,
        download_id,
        path,
        name,
        size_bytes,
        media_kind,
        priority,
        progress,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `
    );

    for (const file of files) {
      statement.run(
        file.id,
        file.downloadId,
        file.path,
        file.name,
        file.sizeBytes,
        file.mediaKind,
        file.priority,
        file.progress,
        file.createdAt,
        file.updatedAt
      );
    }

    return this.listFiles(downloadId);
  }

  updateFileProgress(fileId: string, progress: number): void {
    getAppDatabase()
      .prepare(
        `
        UPDATE download_files
        SET progress = ?, updated_at = ?
        WHERE id = ?
      `
      )
      .run(progress, new Date().toISOString(), fileId);
  }

  listFiles(downloadId?: string): DownloadFileView[] {
    const rows = (
      downloadId
        ? getAppDatabase()
            .prepare(
              `
              SELECT *
              FROM download_files
              WHERE download_id = ?
              ORDER BY priority DESC, id
            `
            )
            .all(downloadId)
        : getAppDatabase()
            .prepare(
              `
              SELECT *
              FROM download_files
              ORDER BY created_at DESC, priority DESC, id
            `
            )
            .all()
    ) as DownloadFileRow[];

    return rows.map(toFileView);
  }

  removeSession(downloadId: string): void {
    getAppDatabase()
      .prepare("UPDATE download_sessions SET status = 'removed', updated_at = ? WHERE id = ?")
      .run(new Date().toISOString(), downloadId);
    getAppDatabase().prepare("DELETE FROM download_files WHERE download_id = ?").run(downloadId);
  }

  markInterruptedSessionsPaused(): void {
    getAppDatabase()
      .prepare(
        `
        UPDATE download_sessions
        SET
          status = 'paused',
          download_speed_bytes_per_second = 0,
          upload_speed_bytes_per_second = 0,
          peer_count = 0,
          eta_seconds = NULL,
          updated_at = ?
        WHERE status IN ('queued', 'metadata', 'downloading', 'ready')
      `
      )
      .run(new Date().toISOString());
  }
}

function toPersistedSession(row: DownloadSessionRow): PersistedDownloadSession {
  return {
    ...toTaskView(row),
    inputKind: toInputKind(row.input_kind),
    inputRef: row.input_ref
  };
}

function toTaskView(row: DownloadSessionRow): DownloadTaskView {
  return {
    id: row.id,
    title: row.title,
    status: row.status,
    progress: row.progress,
    downloadedBytes: row.downloaded_bytes,
    totalBytes: row.total_bytes,
    downloadSpeedBytesPerSecond: row.download_speed_bytes_per_second,
    uploadSpeedBytesPerSecond: row.upload_speed_bytes_per_second,
    peerCount: row.peer_count,
    etaSeconds: row.eta_seconds,
    selectedFileId: row.selected_file_id,
    errorMessage: row.error_message,
    previewImageUrl: row.preview_image_url,
    previewSourceName: row.preview_source_name,
    previewSourceUrl: row.preview_source_url,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function toFileView(row: DownloadFileRow): DownloadFileView {
  return {
    id: row.id,
    downloadId: row.download_id,
    path: row.path,
    name: row.name,
    sizeBytes: row.size_bytes,
    mediaKind: row.media_kind,
    priority: row.priority,
    progress: row.progress,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function toInputKind(value: string): PersistedDownloadSession["inputKind"] {
  if (value === "magnet" || value === "torrentFile") {
    return value;
  }

  throw new Error(`未知下载输入类型：${value}`);
}
