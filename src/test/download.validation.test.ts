import { afterEach, describe, expect, it, vi } from "vitest";

describe("download input validation", () => {
  afterEach(() => {
    vi.resetModules();
  });

  it("rejects invalid magnet input before a download session is created", async () => {
    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => "."
      }
    }));

    const { validateTorrentInput } = await import("../main/download/downloadService");

    expect(() => validateTorrentInput({ kind: "magnet", uri: "https://example.com/file" })).toThrow(
      "请输入有效的 magnet 链接。"
    );
  });

  it("normalizes supported magnet links", async () => {
    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => "."
      }
    }));

    const { validateTorrentInput } = await import("../main/download/downloadService");
    const magnet = "magnet:?xt=urn:btih:C5PPDMBT7OKFBO4A4MGUK3LLHSDP4BKG";

    expect(validateTorrentInput({ kind: "magnet", uri: `  ${magnet}  ` })).toEqual({
      kind: "magnet",
      uri: magnet
    });
  });
});
