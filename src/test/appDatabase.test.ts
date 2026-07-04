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

  it("creates playback binding and progress tables for episode-bound playback", async () => {
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
        WHERE type = 'table' AND name IN ('media_bindings', 'playback_progress')
        ORDER BY name
      `
      )
      .all() as Array<{ name: string }>;
    database.close();

    expect(tables.map((table) => table.name)).toEqual([
      "media_bindings",
      "playback_progress"
    ]);
  });
});
