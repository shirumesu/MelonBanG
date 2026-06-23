import type { BroadcastDay, BroadcastItem } from "../../shared/contracts/bangumi";
import { getAppDatabase } from "./appDatabase";

type PublicCacheKey = "trending-current" | "today-schedule";

type PublicCacheRow = {
  value_json: string;
};

export class PublicCacheStore {
  private readonly database = getAppDatabase();

  getTrendingCurrent(): BroadcastItem[] {
    return this.read<BroadcastItem[]>("trending-current") ?? [];
  }

  setTrendingCurrent(items: BroadcastItem[]): void {
    this.write("trending-current", items);
  }

  getTodaySchedule(): BroadcastDay | null {
    return this.read<BroadcastDay>("today-schedule") ?? null;
  }

  setTodaySchedule(day: BroadcastDay): void {
    this.write("today-schedule", day);
  }

  private read<T>(key: PublicCacheKey): T | undefined {
    const row = this.database
      .prepare("SELECT value_json FROM public_cache WHERE cache_key = ?")
      .get(key) as PublicCacheRow | undefined;

    if (!row) {
      return undefined;
    }

    try {
      return JSON.parse(row.value_json) as T;
    } catch {
      return undefined;
    }
  }

  private write(key: PublicCacheKey, value: unknown): void {
    const now = new Date().toISOString();
    this.database
      .prepare(
        `
      INSERT INTO public_cache (cache_key, value_json, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(cache_key) DO UPDATE SET
        value_json = excluded.value_json,
        updated_at = excluded.updated_at
    `
      )
      .run(key, JSON.stringify(value), now);
  }
}
