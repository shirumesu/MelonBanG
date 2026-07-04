import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { RegisterLocalMediaInput } from "../main/media/localMediaServer";

afterEach(() => {
  vi.resetModules();
  delete process.env.MELONBANG_DATA_DIR;
});

describe("SubtitleService", () => {
  it("prepares external SRT and ASS subtitles as WebVTT assets", async () => {
    const appRoot = mkdtempSync(join(tmpdir(), "melonbang-subtitles-"));
    process.env.MELONBANG_DATA_DIR = join(appRoot, "data");

    vi.doMock("electron", () => ({
      app: {
        getAppPath: () => appRoot
      }
    }));

    const mediaPath = join(appRoot, "Episode 01.mkv");
    writeFileSync(mediaPath, "not a real media fixture");
    writeFileSync(
      join(appRoot, "Episode 01.zh.srt"),
      "1\n00:00:01,000 --> 00:00:02,000\n你好\n",
      "utf8"
    );
    writeFileSync(
      join(appRoot, "Episode 01.ass"),
      [
        "[Script Info]",
        "Title: sample",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
        "Dialogue: 0,0:00:03.00,0:00:04.25,Default,,0,0,0,,{\\pos(1,2)}ASS\\N字幕"
      ].join("\n"),
      "utf8"
    );

    const { SubtitleService } = await import("../main/subtitle/subtitleService");
    const mediaServer = new FakeMediaServer();
    const tracks = await new SubtitleService(mediaServer).prepareSubtitles({
      sessionId: "session-1",
      mediaPath
    });

    expect(tracks).toHaveLength(2);
    const srtTrack = tracks.find((track) => track.language === "zh");
    const assTrack = tracks.find((track) => track.format === "ass");
    expect(srtTrack).toMatchObject({
      language: "zh",
      renderMode: "native-vtt",
    });
    expect(assTrack).toMatchObject({
      format: "ass",
      renderMode: "native-vtt",
      errorMessage: "ASS/SSA 样式已降级为文本字幕。"
    });
    expect(
      mediaServer.registered.some((input) =>
        readFileSync(input.filePath, "utf8").includes("WEBVTT")
      )
    ).toBe(true);
    expect(
      mediaServer.registered.some((input) =>
        readFileSync(input.filePath, "utf8").includes("ASS\n字幕")
      )
    ).toBe(true);
  });
});

class FakeMediaServer {
  readonly registered: RegisterLocalMediaInput[] = [];

  registerMediaFile(input: RegisterLocalMediaInput): Promise<{ url: string }> {
    const index = this.registered.length;
    this.registered.push(input);
    return Promise.resolve({ url: `http://127.0.0.1/subtitle/${index}` });
  }
}
