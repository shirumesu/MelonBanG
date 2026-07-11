import { spawnSync } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import bundledFfmpegPath from "ffmpeg-static";
import { describe, expect, it } from "vitest";
import { VideoThumbnailGenerator } from "../main/download/videoThumbnail";
import type { MediaProbeLike } from "../main/media/mediaProbe";

describe("VideoThumbnailGenerator", () => {
  it("captures a bounded JPEG data URL from the local video timeline", async () => {
    if (!bundledFfmpegPath) {
      throw new Error("FFmpeg fixture generation is unavailable on this platform.");
    }

    const root = mkdtempSync(join(tmpdir(), "melonbang-thumbnail-"));
    const filePath = join(root, "source.mp4");
    const fixture = spawnSync(
      bundledFfmpegPath,
      [
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "lavfi",
        "-i",
        "color=c=0x55aa88:s=320x180:r=24",
        "-t",
        "2",
        "-an",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        filePath
      ],
      { windowsHide: true }
    );
    expect(fixture.status).toBe(0);

    const generator = new VideoThumbnailGenerator(new FixedDurationProbe());
    const imageUrl = await generator.generate(filePath);
    const bytes = Buffer.from(imageUrl.slice(imageUrl.indexOf(",") + 1), "base64");

    expect(imageUrl.startsWith("data:image/jpeg;base64,")).toBe(true);
    expect(bytes.subarray(0, 3)).toEqual(Buffer.from([0xff, 0xd8, 0xff]));
    expect(bytes.length).toBeLessThan(2 * 1024 * 1024);
  });
});

class FixedDurationProbe implements MediaProbeLike {
  probe(): Promise<{
    durationSeconds: number;
    videoCodec: string;
    audioCodec: null;
    deliveryMode: "direct";
  }> {
    return Promise.resolve({
      durationSeconds: 2,
      videoCodec: "h264",
      audioCodec: null,
      deliveryMode: "direct"
    });
  }
}
