import { spawn } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync
} from "node:fs";
import { basename, dirname, extname, join, parse } from "node:path";
import bundledFfmpegPath from "ffmpeg-static";
import type { SubtitleTrackView } from "../../shared/contracts/playback";
import { getAppDataDirectory } from "../store/appDatabase";
import type { RegisterLocalMediaInput } from "../media/localMediaServer";

type MediaServerLike = {
  registerMediaFile(input: RegisterLocalMediaInput): Promise<{ url: string }>;
};

type SubtitleCandidate = {
  id: string;
  filePath: string | null;
  label: string;
  language: string | null;
  source: SubtitleTrackView["source"];
  format: SubtitleTrackView["format"];
  streamIndex: number | null;
  codec: string | null;
  supported: boolean;
  errorMessage: string | null;
};

const subtitleExtensions = new Set([".vtt", ".srt", ".ass", ".ssa"]);

export class SubtitleService {
  constructor(private readonly mediaServer: MediaServerLike) {}

  async prepareSubtitles(input: {
    sessionId: string;
    mediaPath: string;
  }): Promise<SubtitleTrackView[]> {
    const candidates = [
      ...discoverExternalSubtitleCandidates(input.mediaPath),
      ...(await discoverEmbeddedSubtitleCandidates(input.mediaPath))
    ];
    const tracks: SubtitleTrackView[] = [];

    for (const [index, candidate] of candidates.entries()) {
      tracks.push(await this.prepareCandidate(input.sessionId, input.mediaPath, candidate, index));
    }

    return tracks;
  }

  private async prepareCandidate(
    sessionId: string,
    mediaPath: string,
    candidate: SubtitleCandidate,
    index: number
  ): Promise<SubtitleTrackView> {
    const baseTrack = createBaseTrack(candidate, index);

    if (!candidate.supported) {
      return {
        ...baseTrack,
        errorMessage: candidate.errorMessage ?? "当前字幕格式暂不支持。"
      };
    }

    try {
      const sourcePath =
        candidate.source === "embedded"
          ? await extractEmbeddedSubtitle(sessionId, mediaPath, candidate)
          : candidate.filePath;
      if (!sourcePath) {
        throw new Error("字幕文件不存在。");
      }

      const vttPath =
        candidate.format === "vtt" ? sourcePath : convertSubtitleFileToVtt(sessionId, sourcePath);
      const source = await this.mediaServer.registerMediaFile({
        sessionId,
        filePath: vttPath,
        title: `${candidate.label}.vtt`,
        mimeType: "text/vtt"
      });

      return {
        ...baseTrack,
        renderMode: "native-vtt",
        url: source.url,
        errorMessage:
          candidate.format === "ass" || candidate.format === "ssa"
            ? "ASS/SSA 样式已降级为文本字幕。"
            : null
      };
    } catch (error) {
      return {
        ...baseTrack,
        renderMode: "unsupported",
        url: null,
        errorMessage: error instanceof Error ? error.message : "字幕准备失败。"
      };
    }
  }
}

function discoverExternalSubtitleCandidates(mediaPath: string): SubtitleCandidate[] {
  const directory = dirname(mediaPath);
  if (!existsSync(directory)) {
    return [];
  }

  const mediaStem = parse(mediaPath).name.toLowerCase();
  return readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => {
      const extension = extname(name).toLowerCase();
      return subtitleExtensions.has(extension) && parse(name).name.toLowerCase().startsWith(mediaStem);
    })
    .sort((left, right) => left.localeCompare(right))
    .map((name) => {
      const filePath = join(directory, name);
      const label = parse(name).name;
      return {
        id: `external:${basename(filePath)}`,
        filePath,
        label,
        language: inferLanguage(label),
        source: "external",
        format: toSubtitleFormat(extname(name)),
        streamIndex: null,
        codec: null,
        supported: true,
        errorMessage: null
      };
    });
}

async function discoverEmbeddedSubtitleCandidates(mediaPath: string): Promise<SubtitleCandidate[]> {
  const result = await runFfmpeg(["-hide_banner", "-i", mediaPath]);
  const output = `${result.stderr}\n${result.stdout}`;
  const candidates: SubtitleCandidate[] = [];
  const streamPattern = /Stream #0:(\d+)(?:\(([^)]+)\))?[^:]*: Subtitle: ([^,\r\n]+)([^\r\n]*)/g;

  for (const match of output.matchAll(streamPattern)) {
    const streamIndex = Number(match[1]);
    const language = match[2] ?? null;
    const codec = match[3]?.trim().toLowerCase() ?? "unknown";
    const title = extractStreamTitle(match[4] ?? "");
    const format = subtitleFormatFromCodec(codec);
    const supported = format !== "unknown";
    candidates.push({
      id: `embedded:${streamIndex}`,
      filePath: null,
      label: title ?? `${language ? language.toUpperCase() : "内嵌"} 字幕 ${candidates.length + 1}`,
      language: language ? normalizeLanguage(language) : null,
      source: "embedded",
      format,
      streamIndex,
      codec,
      supported,
      errorMessage: supported
        ? null
        : `内嵌字幕编码 ${codec} 暂不支持 Web-native 渲染。`
    });
  }

  return candidates;
}

function createBaseTrack(candidate: SubtitleCandidate, index: number): SubtitleTrackView {
  return {
    id: candidate.id,
    label: candidate.label,
    language: candidate.language,
    source: candidate.source,
    format: candidate.format,
    renderMode: "unsupported",
    url: null,
    fontUrls: [],
    default: index === 0,
    errorMessage: candidate.errorMessage
  };
}

async function extractEmbeddedSubtitle(
  sessionId: string,
  mediaPath: string,
  candidate: SubtitleCandidate
): Promise<string> {
  if (candidate.streamIndex === null) {
    throw new Error("内嵌字幕轨道缺少 stream index。");
  }

  const outputDirectory = join(getAppDataDirectory(), "subtitles", sessionId, "embedded");
  mkdirSync(outputDirectory, { recursive: true });
  const extension = candidate.format === "ass" || candidate.format === "ssa" ? ".ass" : ".srt";
  const outputPath = join(outputDirectory, `stream-${candidate.streamIndex}${extension}`);
  const result = await runFfmpeg([
    "-hide_banner",
    "-loglevel",
    "error",
    "-y",
    "-nostdin",
    "-i",
    mediaPath,
    "-map",
    `0:${candidate.streamIndex}`,
    outputPath
  ]);

  if (result.code !== 0 || !existsSync(outputPath)) {
    throw new Error(result.stderr.trim() || "内嵌字幕抽取失败。");
  }

  return outputPath;
}

function convertSubtitleFileToVtt(sessionId: string, filePath: string): string {
  const outputDirectory = join(getAppDataDirectory(), "subtitles", sessionId);
  mkdirSync(outputDirectory, { recursive: true });
  const outputPath = join(outputDirectory, `${parse(filePath).name}.vtt`);
  const content = readTextFile(filePath);
  const extension = extname(filePath).toLowerCase();
  const vtt =
    extension === ".ass" || extension === ".ssa" ? convertAssToVtt(content) : convertSrtToVtt(content);
  writeFileSync(outputPath, vtt, "utf8");
  return outputPath;
}

function convertSrtToVtt(content: string): string {
  const normalized = content.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n").trim();
  if (!normalized) {
    return "WEBVTT\n";
  }

  return `WEBVTT\n\n${normalized.replace(
    /(\d{2}:\d{2}:\d{2}),(\d{3})/g,
    "$1.$2"
  )}\n`;
}

function convertAssToVtt(content: string): string {
  const lines = content.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n").split("\n");
  const events: string[] = [];
  let fields: string[] = [];
  let inEvents = false;

  for (const line of lines) {
    const trimmed = line.trim();
    if (/^\[events\]$/i.test(trimmed)) {
      inEvents = true;
      continue;
    }
    if (inEvents && /^\[.+\]$/.test(trimmed)) {
      inEvents = false;
    }
    if (!inEvents) {
      continue;
    }
    if (/^format:/i.test(trimmed)) {
      fields = trimmed
        .slice(trimmed.indexOf(":") + 1)
        .split(",")
        .map((field) => field.trim().toLowerCase());
      continue;
    }
    if (!/^dialogue:/i.test(trimmed) || fields.length === 0) {
      continue;
    }

    const values = splitAssDialogue(trimmed.slice(trimmed.indexOf(":") + 1), fields.length);
    const start = values[fields.indexOf("start")];
    const end = values[fields.indexOf("end")];
    const text = values[fields.indexOf("text")];
    if (!start || !end || !text) {
      continue;
    }
    events.push(`${assTimeToVtt(start)} --> ${assTimeToVtt(end)}\n${cleanAssText(text)}`);
  }

  return events.length ? `WEBVTT\n\n${events.join("\n\n")}\n` : "WEBVTT\n";
}

function splitAssDialogue(raw: string, fieldCount: number): string[] {
  const values = raw.split(",");
  if (values.length <= fieldCount) {
    return values.map((value) => value.trim());
  }
  return [
    ...values.slice(0, fieldCount - 1).map((value) => value.trim()),
    values.slice(fieldCount - 1).join(",").trim()
  ];
}

function assTimeToVtt(value: string): string {
  const match = /(\d+):(\d{2}):(\d{2})[.](\d{1,2})/.exec(value.trim());
  if (!match) {
    return "00:00:00.000";
  }

  const hours = match[1].padStart(2, "0");
  const centiseconds = match[4].padEnd(2, "0");
  return `${hours}:${match[2]}:${match[3]}.${centiseconds}0`;
}

function cleanAssText(value: string): string {
  return value
    .replace(/\{[^}]*\}/g, "")
    .replace(/\\[Nn]/g, "\n")
    .replace(/\\h/g, " ")
    .replace(/\\[A-Za-z]+\([^)]*\)/g, "")
    .replace(/\\[A-Za-z]+-?\d*\.?\d*/g, "")
    .trim();
}

function readTextFile(filePath: string): string {
  return readFileSync(filePath, "utf8");
}

function toSubtitleFormat(extension: string): SubtitleTrackView["format"] {
  switch (extension.toLowerCase()) {
    case ".vtt":
      return "vtt";
    case ".srt":
      return "srt";
    case ".ass":
      return "ass";
    case ".ssa":
      return "ssa";
    default:
      return "unknown";
  }
}

function subtitleFormatFromCodec(codec: string): SubtitleTrackView["format"] {
  if (codec.includes("webvtt")) {
    return "vtt";
  }
  if (codec.includes("ass")) {
    return "ass";
  }
  if (codec.includes("ssa")) {
    return "ssa";
  }
  if (codec.includes("subrip") || codec.includes("srt") || codec.includes("mov_text")) {
    return "srt";
  }
  return "unknown";
}

function extractStreamTitle(raw: string): string | null {
  const match = /title\s*:\s*([^\r\n]+)/i.exec(raw);
  return match?.[1]?.trim() || null;
}

function inferLanguage(label: string): string | null {
  const lower = label.toLowerCase();
  if (/(^|[._ -])(zh|chs|cht|sc|tc|cn)([._ -]|$)/.test(lower)) {
    return "zh";
  }
  if (/(^|[._ -])(ja|jp|jpn)([._ -]|$)/.test(lower)) {
    return "ja";
  }
  if (/(^|[._ -])(en|eng)([._ -]|$)/.test(lower)) {
    return "en";
  }
  return null;
}

function normalizeLanguage(value: string): string {
  const lower = value.toLowerCase();
  if (lower === "jpn") {
    return "ja";
  }
  if (lower === "eng") {
    return "en";
  }
  if (lower === "chi" || lower === "zho") {
    return "zh";
  }
  return lower;
}

function getFfmpegPath(): string {
  if (!bundledFfmpegPath) {
    throw new Error("当前平台缺少内置 FFmpeg 二进制。");
  }
  return bundledFfmpegPath;
}

async function runFfmpeg(args: string[]): Promise<{
  code: number | null;
  stdout: string;
  stderr: string;
}> {
  return new Promise((resolvePromise, rejectPromise) => {
    const process = spawn(getFfmpegPath(), args, {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    process.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString("utf8");
    });
    process.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString("utf8");
    });
    process.once("error", rejectPromise);
    process.once("close", (code) => {
      resolvePromise({ code, stdout, stderr });
    });
  });
}
