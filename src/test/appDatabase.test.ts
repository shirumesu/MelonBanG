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
});
