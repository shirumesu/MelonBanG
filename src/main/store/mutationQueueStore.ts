import type { TrackingMutation } from "../../shared/contracts/bangumi";
import { getAppDatabase } from "./appDatabase";

export type QueuedMutationState = "pending" | "retry" | "applied" | "failed";

export type QueuedMutation = {
  mutationId: string;
  mutationKey: string;
  kind: TrackingMutation["kind"];
  payload: TrackingMutation;
  state: QueuedMutationState;
  createdAt: string;
  attemptCount: number;
  nextAttemptAt?: string;
  updatedAt: string;
};

export class MutationQueueStore {
  private readonly database = getAppDatabase();

  enqueue(input: TrackingMutation): {
    mutationId: string;
    mutationKey: string;
    supersededMutationId?: string;
  } {
    const mutationId = crypto.randomUUID();
    const mutationKey = mutationKeyFor(input);
    const now = new Date().toISOString();
    const existing = this.database
      .prepare(
        `
      SELECT mutation_id
      FROM mutation_queue
      WHERE mutation_key = ?
        AND state IN ('pending', 'retry')
      LIMIT 1
    `
      )
      .get(mutationKey) as { mutation_id: string } | undefined;

    this.database.prepare("BEGIN").run();
    try {
      if (existing) {
        this.database
          .prepare("DELETE FROM mutation_queue WHERE mutation_id = ?")
          .run(existing.mutation_id);
      }

      this.database
        .prepare(
          `
        INSERT INTO mutation_queue (
          mutation_id,
          mutation_key,
          kind,
          payload_json,
          state,
          created_at,
          attempt_count,
          next_attempt_at,
          updated_at
        )
        VALUES (?, ?, ?, ?, 'pending', ?, 0, NULL, ?)
      `
        )
        .run(mutationId, mutationKey, input.kind, JSON.stringify(input), now, now);

      this.database.prepare("COMMIT").run();
    } catch (error) {
      this.database.prepare("ROLLBACK").run();
      throw error;
    }

    return {
      mutationId,
      mutationKey,
      supersededMutationId: existing?.mutation_id
    };
  }

  listReady(now = new Date().toISOString()): QueuedMutation[] {
    const rows = this.database
      .prepare(
        `
      SELECT mutation_id, mutation_key, kind, payload_json, state, created_at, attempt_count, next_attempt_at, updated_at
      FROM mutation_queue
      WHERE state IN ('pending', 'retry')
        AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
      ORDER BY created_at ASC
    `
      )
      .all(now) as Array<{
      mutation_id: string;
      mutation_key: string;
      kind: TrackingMutation["kind"];
      payload_json: string;
      state: QueuedMutationState;
      created_at: string;
      attempt_count: number;
      next_attempt_at: string | null;
      updated_at: string;
    }>;

    return rows.map((row) => this.mapRow(row));
  }

  listPending(): QueuedMutation[] {
    const rows = this.database
      .prepare(
        `
      SELECT mutation_id, mutation_key, kind, payload_json, state, created_at, attempt_count, next_attempt_at, updated_at
      FROM mutation_queue
      WHERE state IN ('pending', 'retry')
      ORDER BY created_at ASC
    `
      )
      .all() as Array<{
      mutation_id: string;
      mutation_key: string;
      kind: TrackingMutation["kind"];
      payload_json: string;
      state: QueuedMutationState;
      created_at: string;
      attempt_count: number;
      next_attempt_at: string | null;
      updated_at: string;
    }>;

    return rows.map((row) => this.mapRow(row));
  }

  getPendingCount(): number {
    const row = this.database
      .prepare("SELECT COUNT(*) as count FROM mutation_queue WHERE state IN ('pending', 'retry')")
      .get() as { count: number };

    return row.count;
  }

  clear(): void {
    this.database.prepare("DELETE FROM mutation_queue").run();
  }

  markApplied(mutationId: string): void {
    this.database
      .prepare(
        `
      UPDATE mutation_queue
      SET state = 'applied',
          next_attempt_at = NULL,
          updated_at = ?
      WHERE mutation_id = ?
    `
      )
      .run(new Date().toISOString(), mutationId);
  }

  markRetry(mutationId: string, nextAttemptAt: string): void {
    this.database
      .prepare(
        `
      UPDATE mutation_queue
      SET state = 'retry',
          attempt_count = attempt_count + 1,
          next_attempt_at = ?,
          updated_at = ?
      WHERE mutation_id = ?
    `
      )
      .run(nextAttemptAt, new Date().toISOString(), mutationId);
  }

  private mapRow(row: {
    mutation_id: string;
    mutation_key: string;
    kind: TrackingMutation["kind"];
    payload_json: string;
    state: QueuedMutationState;
    created_at: string;
    attempt_count: number;
    next_attempt_at: string | null;
    updated_at: string;
  }): QueuedMutation {
    return {
      mutationId: row.mutation_id,
      mutationKey: row.mutation_key,
      kind: row.kind,
      payload: JSON.parse(row.payload_json) as TrackingMutation,
      state: row.state,
      createdAt: row.created_at,
      attemptCount: row.attempt_count,
      nextAttemptAt: row.next_attempt_at ?? undefined,
      updatedAt: row.updated_at
    };
  }
}

function mutationKeyFor(input: TrackingMutation): string {
  if (input.kind === "subjectCollection") {
    return `subject:${input.subjectId}:collection`;
  }

  return `episode:${input.episodeId}:collection`;
}
