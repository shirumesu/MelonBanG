import type { PlaybackProgressSnapshot } from "../../shared/contracts/playback";
import { getAppDatabase } from "../store/appDatabase";

type PlaybackProgressRow = {
  subject_id: number;
  episode_id: number;
  position_seconds: number;
  duration_seconds: number | null;
  completed: number;
  updated_at: string;
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
