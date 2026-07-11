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
  it("keeps external ASS styling while converting only SRT subtitles to WebVTT", async () => {
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
      renderMode: "native-vtt"
    });
    expect(assTrack).toMatchObject({
      format: "ass",
      renderMode: "ass",
      errorMessage: null
    });
    expect(
      mediaServer.registered.some((input) =>
        readFileSync(input.filePath, "utf8").includes("WEBVTT")
      )
    ).toBe(true);
    const registeredAss = mediaServer.registered.find((input) => input.filePath.endsWith(".ass"));
    expect(registeredAss).toMatchObject({ mimeType: "text/x-ssa" });
    expect(readFileSync(registeredAss?.filePath ?? "", "utf8")).toContain("{\\pos(1,2)}ASS\\N字幕");
  });

  it("maps embedded ASS titles and font attachments from FFmpeg inspection output", async () => {
    const { parseFfmpegInspectionOutput } = await import("../main/subtitle/subtitleService");
    const inspection = parseFfmpegInspectionOutput(`
      Stream #0:2(chi): Subtitle: ass (default)
        Metadata:
          title           : 简体
      Stream #0:3(chi): Subtitle: ass
        Metadata:
          title           : 繁体
      Stream #0:4: Attachment: ttf
        Metadata:
          filename        : Arial Unicode MS.ttf
          mimetype        : application/x-truetype-font
    `);

    expect(inspection.subtitles).toMatchObject([
      { id: "embedded:2", label: "简体", language: "zh", format: "ass" },
      { id: "embedded:3", label: "繁体", language: "zh", format: "ass" }
    ]);
    expect(inspection.fontAttachments).toEqual([
      {
        streamIndex: 4,
        fileName: "Arial Unicode MS.ttf",
        mimeType: "application/x-truetype-font"
      }
    ]);
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
