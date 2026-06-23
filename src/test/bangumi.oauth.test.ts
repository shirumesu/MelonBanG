import { mkdtempSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { BangumiOAuthConfig } from "../main/config/bangumi";

describe("BangumiOAuth", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.resetModules();
    delete process.env.MELONBANG_DATA_DIR;
  });

  it("cancels the loopback authorization listener so sign-in can be retried", async () => {
    const port = await getOpenPort();
    const { BangumiOAuth, openExternal } = await loadOAuthModule();
    const oauth = new BangumiOAuth(oauthConfig(port));

    const firstSignIn = oauth.signIn();
    await vi.waitFor(() => expect(openExternal).toHaveBeenCalledTimes(1));
    oauth.cancelSignIn();
    await expect(firstSignIn).rejects.toThrow("cancelled");

    const secondSignIn = oauth.signIn();
    await vi.waitFor(() => expect(openExternal).toHaveBeenCalledTimes(2));
    oauth.cancelSignIn();
    await expect(secondSignIn).rejects.toThrow("cancelled");
  });
});

async function loadOAuthModule(): Promise<{
  BangumiOAuth: typeof import("../main/bangumi/BangumiOAuth").BangumiOAuth;
  openExternal: ReturnType<typeof vi.fn>;
}> {
  vi.resetModules();
  process.env.MELONBANG_DATA_DIR = mkdtempSync(join(tmpdir(), "melonbang-test-"));
  const openExternal = vi.fn(() => Promise.resolve());
  vi.doMock("electron", () => ({
    app: {
      isPackaged: false,
      getAppPath: () => process.env.MELONBANG_DATA_DIR,
      getPath: () => process.env.MELONBANG_DATA_DIR,
      getVersion: () => "0.1.0"
    },
    safeStorage: {
      isEncryptionAvailable: () => true,
      encryptString: (value: string) => Buffer.from(value, "utf8"),
      decryptString: (value: Buffer) => value.toString("utf8")
    },
    shell: {
      openExternal
    }
  }));

  const { BangumiOAuth } = await import("../main/bangumi/BangumiOAuth");
  return { BangumiOAuth, openExternal };
}

function oauthConfig(port: number): BangumiOAuthConfig {
  return {
    clientId: "client-id",
    clientSecret: "client-secret",
    redirectUri: `http://127.0.0.1:${port}/callback`,
    userAgent: "melonbang-test/0.1.0"
  };
}

async function getOpenPort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        reject(new Error("Could not reserve a local port."));
        return;
      }

      server.close((error) => {
        if (error) {
          reject(error);
        } else {
          resolve(address.port);
        }
      });
    });
  });
}
