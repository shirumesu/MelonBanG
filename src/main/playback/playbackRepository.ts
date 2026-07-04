import type {
  MediaBindingView,
  PlaybackProgressSnapshot
} from "../../shared/contracts/playback";
import { getAppDatabase } from "../store/appDatabase";

type MediaBindingRow = {
  id: string;
  subject_id: number;
  episode_id: number;
  download_id: string;
  file_id: string;
  file_name: string | null;
  download_title: string | null;
  download_status: string | null;
  created_at: string;
  updated_at: string;
};

type PlaybackProgressRow = {
  subject_id: number;
  episode_id: number;
  position_seconds: number;
  duration_seconds: number | null;
  completed: number;
  updated_at: string;
};

export type SaveMediaBindingInput = {
  id: string;
  subjectId: number;
  episodeId: number;
  downloadId: string;
  fileId: string;
  createdAt: string;
  updatedAt: string;
};

export type SavePlaybackProgressInput = {
  subjectId: number;
  episodeId: number;
  positionSeconds: number;
  durationSeconds: number | null;
  completed: boolean;
  updatedAt: string;
};

export class PlaybackRepository {
  saveMediaBinding(input: SaveMediaBindingInput): MediaBindingView {
    getAppDatabase()
      .prepare(
        `
        INSERT INTO media_bindings (
          id,
          subject_id,
          episode_id,
          download_id,
          file_id,
          created_at,
          updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(subject_id, episode_id) DO UPDATE SET
          download_id = excluded.download_id,
          file_id = excluded.file_id,
          updated_at = excluded.updated_at
      `
      )
      .run(
        input.id,
        input.subjectId,
        input.episodeId,
        input.downloadId,
        input.fileId,
        input.createdAt,
        input.updatedAt
      );

    const binding = this.getMediaBinding(input.subjectId, input.episodeId);
    if (!binding) {
      throw new Error("媒体绑定保存失败。");
    }
    return binding;
  }

  getMediaBinding(subjectId: number, episodeId: number): MediaBindingView | null {
    const row = getAppDatabase()
      .prepare(
        `
        SELECT
          media_bindings.*,
          download_files.name AS file_name,
          download_sessions.title AS download_title,
          download_sessions.status AS download_status
        FROM media_bindings
        LEFT JOIN download_files ON download_files.id = media_bindings.file_id
        LEFT JOIN download_sessions ON download_sessions.id = media_bindings.download_id
        WHERE media_bindings.subject_id = ? AND media_bindings.episode_id = ?
      `
      )
      .get(subjectId, episodeId) as MediaBindingRow | undefined;

    return row ? toMediaBindingView(row) : null;
  }

  getMediaBindingById(bindingId: string): MediaBindingView | null {
    const row = getAppDatabase()
      .prepare(
        `
        SELECT
          media_bindings.*,
          download_files.name AS file_name,
          download_sessions.title AS download_title,
          download_sessions.status AS download_status
        FROM media_bindings
        LEFT JOIN download_files ON download_files.id = media_bindings.file_id
        LEFT JOIN download_sessions ON download_sessions.id = media_bindings.download_id
        WHERE media_bindings.id = ?
      `
      )
      .get(bindingId) as MediaBindingRow | undefined;

    return row ? toMediaBindingView(row) : null;
  }

  clearMediaBinding(bindingId: string): void {
    getAppDatabase().prepare("DELETE FROM media_bindings WHERE id = ?").run(bindingId);
  }

  saveProgress(input: SavePlaybackProgressInput): PlaybackProgressSnapshot {
    getAppDatabase()
      .prepare(
        `
        INSERT INTO playback_progress (
          subject_id,
          episode_id,
          position_seconds,
          duration_seconds,
          completed,
          updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(subject_id, episode_id) DO UPDATE SET
          position_seconds = excluded.position_seconds,
          duration_seconds = excluded.duration_seconds,
          completed = excluded.completed,
          updated_at = excluded.updated_at
      `
      )
      .run(
        input.subjectId,
        input.episodeId,
        input.positionSeconds,
        input.durationSeconds,
        input.completed ? 1 : 0,
        input.updatedAt
      );

    const progress = this.getProgress(input.subjectId, input.episodeId);
    if (!progress) {
      throw new Error("播放进度保存失败。");
    }
    return progress;
  }

  getProgress(subjectId: number, episodeId: number): PlaybackProgressSnapshot | null {
    const row = getAppDatabase()
      .prepare(
        `
        SELECT *
        FROM playback_progress
        WHERE subject_id = ? AND episode_id = ?
      `
      )
      .get(subjectId, episodeId) as PlaybackProgressRow | undefined;

    return row ? toPlaybackProgressSnapshot(row) : null;
  }
}

function toMediaBindingView(row: MediaBindingRow): MediaBindingView {
  return {
    id: row.id,
    subjectId: row.subject_id,
    episodeId: row.episode_id,
    downloadId: row.download_id,
    fileId: row.file_id,
    fileName: row.file_name,
    downloadTitle: row.download_title,
    available: Boolean(row.file_name && row.download_status && row.download_status !== "removed"),
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function toPlaybackProgressSnapshot(row: PlaybackProgressRow): PlaybackProgressSnapshot {
  return {
    subjectId: row.subject_id,
    episodeId: row.episode_id,
    positionSeconds: row.position_seconds,
    durationSeconds: row.duration_seconds,
    completed: row.completed === 1,
    updatedAt: row.updated_at
  };
}
