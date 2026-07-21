import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

describe("appDatabase", () => {
  afterEach(() => {
    vi.resetModules();
    delete process.env.MELONBANG_DATA_DIR;
  });

  it("stores the default SQLite cache under the app temp directory", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-app-root-"));
    const appDataRoot = join(appRoot, "userData");

    vi.doMock("electron", () => ({
      app: {
        isPackaged: true,
        getAppPath: () => appRoot,
        getPath: () => appDataRoot
      }
    }));

    const { getAppDatabase } = await import("../main/store/appDatabase");
    const database = getAppDatabase();
    database.close();

    expect(existsSync(join(appRoot, "temp", "melonbang.sqlite"))).toBe(true);
    expect(existsSync(join(appDataRoot, "melonbang.sqlite"))).toBe(false);
  });

  it("creates additive download tables for Goal 2 cache state", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-app-root-"));

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => appRoot
      }
    }));

    const { getAppDatabase } = await import("../main/store/appDatabase");
    const database = getAppDatabase();
    const tables = database
      .prepare(
        `
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name IN ('download_sessions', 'download_files')
        ORDER BY name
      `
      )
      .all() as Array<{ name: string }>;
    const sessionColumns = database.prepare("PRAGMA table_info(download_sessions)").all() as Array<{
      name: string;
    }>;
    database.close();

    expect(tables.map((table) => table.name)).toEqual(["download_files", "download_sessions"]);
    expect(sessionColumns.map((column) => column.name)).toEqual(
      expect.arrayContaining(["preview_image_url", "preview_source_name", "preview_source_url"])
    );
  });

  it("migrates legacy media bindings into download episode context", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-app-root-"));

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => appRoot
      }
    }));

    const firstModule = await import("../main/store/appDatabase");
    const database = firstModule.getAppDatabase();
    database.exec(`
      CREATE TABLE IF NOT EXISTS media_bindings (
        id TEXT PRIMARY KEY,
        subject_id INTEGER NOT NULL,
        episode_id INTEGER NOT NULL,
        download_id TEXT NOT NULL,
        file_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(subject_id, episode_id)
      ) STRICT;
    `);
    database
      .prepare(`
        INSERT INTO download_sessions (
          id, input_kind, input_ref, title, status, selected_file_id, created_at, updated_at
        ) VALUES (?, 'magnet', ?, ?, 'completed', ?, ?, ?)
      `)
      .run(
        "download-1",
        "magnet:?xt=urn:btih:C5PPDMBT7OKFBO4A4MGUK3LLHSDP4BKG",
        "Episode 1",
        "download-1:old",
        "2026-07-21T00:00:00.000Z",
        "2026-07-21T00:00:00.000Z"
      );
    database
      .prepare(`
        INSERT INTO download_files (
          id, download_id, path, name, size_bytes, media_kind, priority, progress, created_at, updated_at
        ) VALUES (?, ?, ?, ?, 1024, 'video', 1, 1, ?, ?)
      `)
      .run(
        "download-1:0",
        "download-1",
        "episode-1.mkv",
        "episode-1.mkv",
        "2026-07-21T00:00:00.000Z",
        "2026-07-21T00:00:00.000Z"
      );
    database
      .prepare(`
        INSERT INTO media_bindings (
          id, subject_id, episode_id, download_id, file_id, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `)
      .run(
        "binding-1",
        100,
        501,
        "download-1",
        "download-1:0",
        "2026-07-21T00:00:00.000Z",
        "2026-07-21T00:00:00.000Z"
      );
    database.close();

    vi.resetModules();
    const secondModule = await import("../main/store/appDatabase");
    const migrated = secondModule.getAppDatabase();
    const session = migrated
      .prepare("SELECT subject_id, episode_id, selected_file_id FROM download_sessions WHERE id = ?")
      .get("download-1") as {
      subject_id: number | null;
      episode_id: number | null;
      selected_file_id: string | null;
    };
    const legacyTable = migrated
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'media_bindings'")
      .get();
    const progressTable = migrated
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'playback_progress'")
      .get() as { name: string };
    migrated.close();

    expect(session).toEqual({
      subject_id: 100,
      episode_id: 501,
      selected_file_id: "download-1:0"
    });
    expect(legacyTable).toBeUndefined();
    expect(progressTable.name).toBe("playback_progress");
  });
});
