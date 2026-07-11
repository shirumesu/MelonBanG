import { spawn } from "node:child_process";
import { extname } from "node:path";
import bundledFfmpegPath from "ffmpeg-static";

export type MediaDeliveryMode = "direct" | "remux" | "transcode";

export type MediaProbeResult = {
  durationSeconds: number | null;
  videoCodec: string;
  audioCodec: string | null;
  deliveryMode: MediaDeliveryMode;
};

export interface MediaProbeLike {
  probe(filePath: string): Promise<MediaProbeResult>;
}

export class MediaProbe implements MediaProbeLike {
  async probe(filePath: string): Promise<MediaProbeResult> {
    const output = await runFfmpegProbe(filePath);
    return parseMediaProbeOutput(filePath, output);
  }
}

export function parseMediaProbeOutput(filePath: string, output: string): MediaProbeResult {
  const videoLine = output
    .split(/\r?\n/)
    .find((line) => /Stream #.*Video:/i.test(line));
  if (!videoLine) {
    throw new Error("缓存文件中没有可播放的视频流。");
  }

  const videoCodec = matchCodec(videoLine, "Video");
  const audioLine = output
    .split(/\r?\n/)
    .find((line) => /Stream #.*Audio:/i.test(line));
  const audioCodec = audioLine ? matchCodec(audioLine, "Audio") : null;
  const durationSeconds = parseDuration(output);

  return {
    durationSeconds,
    videoCodec,
    audioCodec,
    deliveryMode: chooseDeliveryMode(filePath, videoCodec, audioCodec, videoLine)
  };
}

function chooseDeliveryMode(
  filePath: string,
  videoCodec: string,
  audioCodec: string | null,
  videoLine: string
): MediaDeliveryMode {
  const extension = extname(filePath).toLowerCase();
  const highBitDepthH264 =
    videoCodec === "h264" && /(?:High 10|High 4:2:2|High 4:4:4|yuv\d+p10|10\s*bit|hi10p)/i.test(videoLine);

  if (highBitDepthH264) {
    return "transcode";
  }

  const audioIsMp4Compatible = audioCodec === null || ["aac", "mp3"].includes(audioCodec);
  const audioIsWebmCompatible = audioCodec === null || ["opus", "vorbis"].includes(audioCodec);

  if (
    [".mp4", ".m4v", ".mov"].includes(extension) &&
    ["h264", "av1"].includes(videoCodec) &&
    audioIsMp4Compatible
  ) {
    return "direct";
  }

  if (extension === ".webm" && ["vp8", "vp9", "av1"].includes(videoCodec) && audioIsWebmCompatible) {
    return "direct";
  }

  if (videoCodec === "h264" && audioIsMp4Compatible) {
    return "remux";
  }

  return "transcode";
}

function matchCodec(line: string, streamType: "Video" | "Audio"): string {
  const match = new RegExp(`${streamType}:\\s*([^\\s,(]+)`, "i").exec(line);
  if (!match?.[1]) {
    throw new Error(`无法识别缓存文件的${streamType === "Video" ? "视频" : "音频"}编码。`);
  }
  return match[1].toLowerCase();
}

function parseDuration(output: string): number | null {
  const match = /Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/i.exec(output);
  if (!match) {
    return null;
  }

  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  const seconds = Number(match[3]);
  const duration = hours * 3600 + minutes * 60 + seconds;
  return Number.isFinite(duration) && duration > 0 ? duration : null;
}

function runFfmpegProbe(filePath: string): Promise<string> {
  const ffmpegPath = bundledFfmpegPath;
  if (!ffmpegPath) {
    return Promise.reject(new Error("当前平台缺少内置 FFmpeg 二进制。"));
  }

  return new Promise((resolvePromise, rejectPromise) => {
    const probeProcess = spawn(
      ffmpegPath,
      ["-hide_banner", "-nostdin", "-i", filePath],
      { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] }
    );
    let stderr = "";
    let settled = false;
    const timeout = setTimeout(() => {
      if (!settled) {
        probeProcess.kill("SIGTERM");
        settled = true;
        rejectPromise(new Error("读取缓存媒体信息超时。"));
      }
    }, 15_000);

    probeProcess.stderr.on("data", (chunk: Buffer) => {
      if (stderr.length < 256_000) {
        stderr += chunk.toString("utf8");
      }
    });
    probeProcess.stdout.resume();
    probeProcess.once("error", (error) => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        rejectPromise(new Error(error.message || "无法读取缓存媒体信息。"));
      }
    });
    probeProcess.once("close", () => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        resolvePromise(stderr);
      }
    });
  });
}
