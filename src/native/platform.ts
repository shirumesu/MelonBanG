import { EventEmitter } from "node:events";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

export const platformEvents = new EventEmitter();
export const app = {
  isPackaged: process.env.MELONBANG_PACKAGED === "1",
  getVersion: () => "0.2.0",
  getAppPath: () => resolve(process.env.MELONBANG_CONFIG_DIR || process.cwd())
};
export const shell = {
  openExternal(url: string): Promise<void> {
    platformEvents.emit("openExternal", url);
    return Promise.resolve();
  }
};

// Keep the existing encrypted token contract while running without Electron.
function protect(value: Buffer, decrypt: boolean): Buffer {
  const operation = decrypt ? "Unprotect" : "Protect";
  const command = `Add-Type -AssemblyName System.Security; $bytes = [Convert]::FromBase64String([Console]::In.ReadToEnd()); [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::${operation}($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser))`;
  const result = spawnSync(
    "powershell.exe",
    ["-NoProfile", "-NonInteractive", "-Command", command],
    {
      input: value.toString("base64"),
      encoding: "utf8",
      windowsHide: true
    }
  );
  if (result.status !== 0 || !result.stdout.trim()) throw new Error("Windows 凭据加密失败。");
  return Buffer.from(result.stdout.trim(), "base64");
}
export const safeStorage = {
  isEncryptionAvailable: () => process.platform === "win32",
  encryptString: (value: string) => protect(Buffer.from(value, "utf8"), false),
  decryptString: (value: Buffer) => protect(value, true).toString("utf8")
};
