import { app } from "electron";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

let databaseInstance: DatabaseSync | null = null;

export function getAppDatabase(): DatabaseSync {
  if (databaseInstance) {
    return databaseInstance;
  }

  const dataDir = app.getPath("userData");
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
      episode_total INTEGER,
      rank INTEGER,
      score REAL,
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

    CREATE UNIQUE INDEX IF NOT EXISTS mutation_queue_pending_key
      ON mutation_queue (mutation_key)
      WHERE state IN ('pending', 'retry');
  `);

  ensureColumn(database, "subject_collections", "ep_status", "INTEGER NOT NULL DEFAULT 0");
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
