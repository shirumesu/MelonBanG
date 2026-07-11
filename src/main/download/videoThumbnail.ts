import { spawn } from "node:child_process";
import bundledFfmpegPath from "ffmpeg-static";
import { MediaProbe, type MediaProbeLike } from "../media/mediaProbe";

const maximumThumbnailBytes = 2 * 1024 * 1024;

export interface VideoThumbnailGeneratorLike {
  generate(filePath: string): Promise<string>;
}

export class VideoThumbnailGenerator implements VideoThumbnailGeneratorLike {
  constructor(private readonly mediaProbe: MediaProbeLike = new MediaProbe()) {}

  async generate(filePath: string): Promise<string> {
    const durationSeconds = await this.probeDuration(filePath);
    const captureSeconds = durationSeconds
      ? Math.min(Math.max(durationSeconds * 0.1, 1), Math.max(1, durationSeconds - 1))
      : 10;
    const bytes = await captureJpegFrame(filePath, captureSeconds);
    return `data:image/jpeg;base64,${bytes.toString("base64")}`;
  }

  private async probeDuration(filePath: string): Promise<number | null> {
    try {
      return (await this.mediaProbe.probe(filePath)).durationSeconds;
    } catch {
      return null;
    }
  }
}

function captureJpegFrame(filePath: string, captureSeconds: number): Promise<Buffer> {
  const ffmpegPath = bundledFfmpegPath;
  if (!ffmpegPath) {
    return Promise.reject(new Error("当前平台缺少内置 FFmpeg 二进制。"));
  }

  return new Promise((resolvePromise, rejectPromise) => {
    const ffmpegProcess = spawn(
      ffmpegPath,
      [
        "-hide_banner",
        "-loglevel",
        "error",
        "-nostdin",
        "-ss",
        captureSeconds.toFixed(3),
        "-i",
        filePath,
        "-frames:v",
        "1",
        "-vf",
        "scale=640:-2:force_original_aspect_ratio=decrease",
        "-q:v",
        "3",
        "-f",
        "image2pipe",
        "-vcodec",
        "mjpeg",
        "pipe:1"
      ],
      { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] as const }
    );
    const chunks: Buffer[] = [];
    let byteLength = 0;
    let stderr = "";
    const timeout = setTimeout(() => {
      ffmpegProcess.kill("SIGTERM");
    }, 20_000);

    ffmpegProcess.stdout.on("data", (chunk: Buffer) => {
      byteLength += chunk.length;
      if (byteLength <= maximumThumbnailBytes) {
        chunks.push(chunk);
      } else {
        ffmpegProcess.kill("SIGTERM");
      }
    });
    ffmpegProcess.stderr.on("data", (chunk: Buffer) => {
      if (stderr.length < 4_000) {
        stderr += chunk.toString("utf8");
      }
    });
    ffmpegProcess.once("error", (error: Error) => {
      clearTimeout(timeout);
      rejectPromise(error);
    });
    ffmpegProcess.once("close", (code) => {
      clearTimeout(timeout);
      if (code !== 0 || byteLength === 0 || byteLength > maximumThumbnailBytes) {
        rejectPromise(new Error(stderr.trim() || "无法从本地视频生成封面。"));
        return;
      }
      resolvePromise(Buffer.concat(chunks));
    });
  });
}
