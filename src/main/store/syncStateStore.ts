import type { SyncState } from "../../shared/contracts/bangumi";
import { getAppDatabase } from "./appDatabase";

type SyncStateRow = {
  stale: number;
  last_successful_sync_at: string | null;
  last_sync_error: string | null;
};

export class SyncStateStore {
  private readonly database = getAppDatabase();

  read(pendingMutationCount: number): SyncState {
    const row = this.database
      .prepare(
        `
      SELECT stale, last_successful_sync_at, last_sync_error
      FROM sync_state
      WHERE singleton_id = 1
    `
      )
      .get() as SyncStateRow | undefined;

    return {
      stale: Boolean(row?.stale ?? 0),
      lastSuccessfulSyncAt: row?.last_successful_sync_at ?? undefined,
      lastSyncError: row?.last_sync_error ?? undefined,
      pendingMutationCount
    };
  }

  markSuccess(at = new Date().toISOString()): void {
    this.database
      .prepare(
        `
      UPDATE sync_state
      SET stale = 0,
          last_successful_sync_at = ?,
          last_sync_error = NULL,
          updated_at = ?
      WHERE singleton_id = 1
    `
      )
      .run(at, at);
  }

  markError(message: string): void {
    const now = new Date().toISOString();
    this.database
      .prepare(
        `
      UPDATE sync_state
      SET stale = 1,
          last_sync_error = ?,
          updated_at = ?
      WHERE singleton_id = 1
    `
      )
      .run(message, now);
  }
}
