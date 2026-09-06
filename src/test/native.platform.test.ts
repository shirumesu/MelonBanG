import { describe, expect, it } from "vitest";
import { safeStorage } from "../native/platform";

describe.skipIf(process.platform !== "win32")("native credential storage", () => {
  it("round-trips Unicode credentials with Windows DPAPI", () => {
    const credential = "local-token-fixture-测试";
    const encrypted = safeStorage.encryptString(credential);
    expect(encrypted.includes(Buffer.from(credential))).toBe(false);
    expect(safeStorage.decryptString(encrypted)).toBe(credential);
  });
});
