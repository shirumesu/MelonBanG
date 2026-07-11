import { describe, expect, it } from "vitest";
import { parseMediaProbeOutput } from "../main/media/mediaProbe";

describe("media playback planning", () => {
  it.each([
    {
      name: "directly serves Web-compatible MP4",
      filePath: "episode.mp4",
      output: probeOutput("00:24:10.50", "h264 (High)", "aac (LC)"),
      expected: {
        deliveryMode: "direct",
        durationSeconds: 1450.5,
        videoCodec: "h264",
        audioCodec: "aac"
      }
    },
    {
      name: "remuxes compatible Matroska streams without decoding",
      filePath: "episode.mkv",
      output: probeOutput("00:23:40.08", "h264 (High)", "aac (LC)"),
      expected: {
        deliveryMode: "remux",
        durationSeconds: 1420.08,
        videoCodec: "h264",
        audioCodec: "aac"
      }
    },
    {
      name: "transcodes HEVC only when Web playback cannot decode it",
      filePath: "episode.mp4",
      output: probeOutput("00:01:30.09", "hevc (Main)", "aac (LC)"),
      expected: {
        deliveryMode: "transcode",
        durationSeconds: 90.09,
        videoCodec: "hevc",
        audioCodec: "aac"
      }
    },
    {
      name: "transcodes H.264 High 10 profile instead of treating it as normal AVC",
      filePath: "episode.mkv",
      output: probeOutput("00:24:00.00", "h264 (High 10)", "aac (LC)", "yuv420p10le"),
      expected: {
        deliveryMode: "transcode",
        durationSeconds: 1440,
        videoCodec: "h264",
        audioCodec: "aac"
      }
    }
  ])("$name", ({ filePath, output, expected }) => {
    expect(parseMediaProbeOutput(filePath, output)).toMatchObject(expected);
  });
});

function probeOutput(
  duration: string,
  videoCodec: string,
  audioCodec: string,
  pixelFormat = "yuv420p"
): string {
  return [
    `Duration: ${duration}, start: 0.000000, bitrate: 2500 kb/s`,
    `Stream #0:0: Video: ${videoCodec}, ${pixelFormat}, 1920x1080`,
    `Stream #0:1: Audio: ${audioCodec}, 48000 Hz, stereo`
  ].join("\n");
}
