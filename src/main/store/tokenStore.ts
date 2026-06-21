import { safeStorage } from "electron";
import { getAppDatabase } from "./appDatabase";

type TokenKey = "access_token" | "refresh_token" | "token_expires_at" | "session_payload";

export type TokenBundle = {
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
  sessionPayload: string;
};

export class TokenStore {
  private readonly database = getAppDatabase();

  constructor() {
    if (!safeStorage.isEncryptionAvailable()) {
      throw new Error("safeStorage encryption is not available on this system.");
    }
  }

  read(): TokenBundle | null {
    const rows = this.database
      .prepare("SELECT key, encrypted_value FROM app_tokens")
      .all() as Array<{ key: TokenKey; encrypted_value: Uint8Array }>;

    if (rows.length === 0) {
      return null;
    }

    const values = new Map<TokenKey, string>();
    for (const row of rows) {
      values.set(row.key, safeStorage.decryptString(Buffer.from(row.encrypted_value)));
    }

    const accessToken = values.get("access_token");
    const refreshToken = values.get("refresh_token");
    const expiresAt = values.get("token_expires_at");
    const sessionPayload = values.get("session_payload");

    if (!accessToken || !refreshToken || !expiresAt || !sessionPayload) {
      return null;
    }

    return {
      accessToken,
      refreshToken,
      expiresAt,
      sessionPayload
    };
  }

  write(bundle: TokenBundle): void {
    const writeStatement = this.database.prepare(`
      INSERT INTO app_tokens (key, encrypted_value, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        encrypted_value = excluded.encrypted_value,
        updated_at = excluded.updated_at
    `);

    const updatedAt = new Date().toISOString();
    const rows: Array<[TokenKey, string]> = [
      ["access_token", bundle.accessToken],
      ["refresh_token", bundle.refreshToken],
      ["token_expires_at", bundle.expiresAt],
      ["session_payload", bundle.sessionPayload]
    ];

    this.database.prepare("BEGIN").run();
    try {
      for (const [key, value] of rows) {
        writeStatement.run(key, safeStorage.encryptString(value), updatedAt);
      }
      this.database.prepare("COMMIT").run();
    } catch (error) {
      this.database.prepare("ROLLBACK").run();
      throw error;
    }
  }

  clear(): void {
    this.database.prepare("DELETE FROM app_tokens").run();
  }
}
