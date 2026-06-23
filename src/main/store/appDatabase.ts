import { app } from "electron";
import { mkdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";

let databaseInstance: DatabaseSync | null = null;

export function getAppDatabase(): DatabaseSync {
  if (databaseInstance) {
    return databaseInstance;
  }

  const dataDir = getAppDataDirectory();
  mkdirSync(dataDir, { recursive: true });

  const dbPath = join(dataDir, "melonbang.sqlite");
  const database = new DatabaseSync(dbPath);
  database.exec("PRAGMA journal_mode = WAL;");
  database.exec("PRAGMA foreign_keys = ON;");

  database.exec(`
    CREATE TABLE IF NOT EXISTS app_tokens (
      key TEXT PRIMARY KEY,
      encrypted_value BLOB NOT NULL,
      updated_at TEXT NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS subject_collections (
      subject_id INTEGER PRIMARY KEY,
      status TEXT NOT NULL,
      score INTEGER,
      ep_status INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS subject_cache (
      subject_id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      name_cn TEXT,
      cover_url TEXT,
      summary TEXT,
      air_date TEXT,
      platform TEXT,
      episode_total INTEGER,
      rank INTEGER,
      score REAL,
      rating_count INTEGER,
      collection_stats_json TEXT,
      meta_tags_json TEXT,
      tags_json TEXT,
      infobox_json TEXT,
      characters_json TEXT,
      staff_json TEXT,
      related_subjects_json TEXT,
      comments_json TEXT,
      topics_json TEXT,
      schedule_json TEXT,
      source_notes_json TEXT,
      updated_at TEXT NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS episode_collections (
      episode_id INTEGER PRIMARY KEY,
      subject_id INTEGER NOT NULL,
      sort INTEGER NOT NULL,
      name TEXT NOT NULL,
      name_cn TEXT,
      status TEXT NOT NULL,
      updated_at TEXT
    ) STRICT;

    CREATE TABLE IF NOT EXISTS mutation_queue (
      mutation_id TEXT PRIMARY KEY,
      mutation_key TEXT NOT NULL,
      kind TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      state TEXT NOT NULL,
      created_at TEXT NOT NULL,
      attempt_count INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT,
      updated_at TEXT NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS sync_state (
      singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
      stale INTEGER NOT NULL DEFAULT 0,
      last_successful_sync_at TEXT,
      last_sync_error TEXT,
      updated_at TEXT NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS public_cache (
      cache_key TEXT PRIMARY KEY,
      value_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS download_sessions (
      id TEXT PRIMARY KEY,
      input_kind TEXT NOT NULL,
      input_ref TEXT NOT NULL,
      title TEXT NOT NULL,
      status TEXT NOT NULL,
      progress REAL NOT NULL DEFAULT 0,
      downloaded_bytes INTEGER NOT NULL DEFAULT 0,
      total_bytes INTEGER,
      download_speed_bytes_per_second INTEGER NOT NULL DEFAULT 0,
      upload_speed_bytes_per_second INTEGER NOT NULL DEFAULT 0,
      peer_count INTEGER NOT NULL DEFAULT 0,
      eta_seconds INTEGER,
      selected_file_id TEXT,
      error_message TEXT,
      preview_image_url TEXT,
      preview_source_name TEXT,
      preview_source_url TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS download_files (
      id TEXT PRIMARY KEY,
      download_id TEXT NOT NULL REFERENCES download_sessions(id) ON DELETE CASCADE,
      path TEXT NOT NULL,
      name TEXT NOT NULL,
      size_bytes INTEGER NOT NULL,
      media_kind TEXT NOT NULL,
      priority INTEGER NOT NULL DEFAULT 0,
      progress REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    ) STRICT;

    CREATE UNIQUE INDEX IF NOT EXISTS mutation_queue_pending_key
      ON mutation_queue (mutation_key)
      WHERE state IN ('pending', 'retry');

    CREATE INDEX IF NOT EXISTS subject_collections_status_updated
      ON subject_collections (status, updated_at DESC);

    CREATE INDEX IF NOT EXISTS episode_collections_subject_status_sort
      ON episode_collections (subject_id, status, sort, episode_id);

    CREATE INDEX IF NOT EXISTS episode_collections_subject_sort
      ON episode_collections (subject_id, sort, episode_id);

    CREATE INDEX IF NOT EXISTS mutation_queue_state_created
      ON mutation_queue (state, created_at);

    CREATE INDEX IF NOT EXISTS download_sessions_status_updated
      ON download_sessions (status, updated_at DESC);

    CREATE INDEX IF NOT EXISTS download_files_download_priority
      ON download_files (download_id, priority DESC, id);
  `);

  ensureColumn(database, "subject_collections", "ep_status", "INTEGER NOT NULL DEFAULT 0");
  ensureColumn(database, "subject_cache", "platform", "TEXT");
  ensureColumn(database, "subject_cache", "rating_count", "INTEGER");
  ensureColumn(database, "subject_cache", "collection_stats_json", "TEXT");
  ensureColumn(database, "subject_cache", "meta_tags_json", "TEXT");
  ensureColumn(database, "subject_cache", "tags_json", "TEXT");
  ensureColumn(database, "subject_cache", "infobox_json", "TEXT");
  ensureColumn(database, "subject_cache", "characters_json", "TEXT");
  ensureColumn(database, "subject_cache", "staff_json", "TEXT");
  ensureColumn(database, "subject_cache", "related_subjects_json", "TEXT");
  ensureColumn(database, "subject_cache", "comments_json", "TEXT");
  ensureColumn(database, "subject_cache", "topics_json", "TEXT");
  ensureColumn(database, "subject_cache", "schedule_json", "TEXT");
  ensureColumn(database, "subject_cache", "source_notes_json", "TEXT");
  ensureColumn(database, "download_sessions", "preview_image_url", "TEXT");
  ensureColumn(database, "download_sessions", "preview_source_name", "TEXT");
  ensureColumn(database, "download_sessions", "preview_source_url", "TEXT");
  database
    .prepare(
      `
    INSERT INTO sync_state (singleton_id, stale, last_successful_sync_at, last_sync_error, updated_at)
    VALUES (1, 0, NULL, NULL, ?)
    ON CONFLICT(singleton_id) DO NOTHING
  `
    )
    .run(new Date().toISOString());

  databaseInstance = database;
  return database;
}

export function getAppDataDirectory(): string {
  const override = process.env.MELONBANG_DATA_DIR?.trim();
  if (override) {
    return resolve(override);
  }

  return join(app.getAppPath(), "temp");
}

function ensureColumn(
  database: DatabaseSync,
  tableName: string,
  columnName: string,
  definition: string
): void {
  const columns = database.prepare(`PRAGMA table_info(${tableName})`).all() as Array<{
    name: string;
  }>;
  if (columns.some((column) => column.name === columnName)) {
    return;
  }

  database.exec(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${definition};`);
}
