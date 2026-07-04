import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

describe("renderer CSP", () => {
  it("allows local Web playback URLs and HLS MediaSource blobs", () => {
    const html = readFileSync(join(process.cwd(), "src", "renderer", "index.html"), "utf8");
    const content = /Content-Security-Policy"\s+content="([^"]+)"/.exec(html)?.[1] ?? "";

    expect(content).toContain("connect-src 'self' https: http://127.0.0.1:*");
    expect(content).toContain("media-src 'self' blob: http://127.0.0.1:*");
    expect(content).toContain("worker-src 'self' blob:");
  });
});
