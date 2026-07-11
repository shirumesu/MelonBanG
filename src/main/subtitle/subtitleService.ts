import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
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

type FontAttachmentCandidate = {
  streamIndex: number;
  fileName: string;
  mimeType: string | null;
};

type EmbeddedMediaInspection = {
  subtitles: SubtitleCandidate[];
  fontAttachments: FontAttachmentCandidate[];
};

const subtitleExtensions = new Set([".vtt", ".srt", ".ass", ".ssa"]);

export class SubtitleService {
  constructor(private readonly mediaServer: MediaServerLike) {}

  async prepareSubtitles(input: {
    sessionId: string;
    mediaPath: string;
  }): Promise<SubtitleTrackView[]> {
    const embedded = await inspectEmbeddedMedia(input.mediaPath);
    const candidates = [
      ...discoverExternalSubtitleCandidates(input.mediaPath),
      ...embedded.subtitles
    ];
    const embeddedFontUrls = embedded.subtitles.some(
      (candidate) => candidate.format === "ass" || candidate.format === "ssa"
    )
      ? await this.prepareEmbeddedFonts(input.sessionId, input.mediaPath, embedded.fontAttachments)
      : [];
    const tracks: SubtitleTrackView[] = [];

    for (const [index, candidate] of candidates.entries()) {
      tracks.push(
        await this.prepareCandidate(
          input.sessionId,
          input.mediaPath,
          candidate,
          index,
          candidate.source === "embedded" ? embeddedFontUrls : []
        )
      );
    }

    return tracks;
  }

  private async prepareCandidate(
    sessionId: string,
    mediaPath: string,
    candidate: SubtitleCandidate,
    index: number,
    fontUrls: string[]
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

      if (candidate.format === "ass" || candidate.format === "ssa") {
        const source = await this.mediaServer.registerMediaFile({
          sessionId,
          filePath: sourcePath,
          title: `${candidate.label}.${candidate.format}`,
          mimeType: "text/x-ssa"
        });
        return {
          ...baseTrack,
          renderMode: "ass",
          url: source.url,
          fontUrls,
          errorMessage: null
        };
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
        errorMessage: null
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

  private async prepareEmbeddedFonts(
    sessionId: string,
    mediaPath: string,
    attachments: FontAttachmentCandidate[]
  ): Promise<string[]> {
    const fontUrls: string[] = [];
    for (const attachment of attachments) {
      try {
        const fontPath = await extractEmbeddedFont(sessionId, mediaPath, attachment);
        const source = await this.mediaServer.registerMediaFile({
          sessionId,
          filePath: fontPath,
          title: attachment.fileName,
          mimeType: inferFontMimeType(fontPath)
        });
        fontUrls.push(source.url);
      } catch {
        // Missing fonts degrade the affected ASS track but should not hide other subtitle tracks.
      }
    }
    return fontUrls;
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
      return (
        subtitleExtensions.has(extension) && parse(name).name.toLowerCase().startsWith(mediaStem)
      );
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

async function inspectEmbeddedMedia(mediaPath: string): Promise<EmbeddedMediaInspection> {
  const result = await runFfmpeg(["-hide_banner", "-i", mediaPath]);
  return parseFfmpegInspectionOutput(`${result.stderr}\n${result.stdout}`);
}

export function parseFfmpegInspectionOutput(output: string): EmbeddedMediaInspection {
  const streams: Array<{
    streamIndex: number;
    language: string | null;
    kind: "subtitle" | "attachment";
    codec: string;
    title: string | null;
    fileName: string | null;
    mimeType: string | null;
  }> = [];
  let current: (typeof streams)[number] | null = null;

  const flush = (): void => {
    if (current) {
      streams.push(current);
      current = null;
    }
  };

  for (const line of output.split(/\r?\n/)) {
    const subtitle = /Stream #\d+:(\d+)(?:\(([^)]+)\))?: Subtitle: ([^,\r\n]+)/i.exec(line);
    const attachment = /Stream #\d+:(\d+): Attachment: ([^,\r\n]+)/i.exec(line);
    if (subtitle) {
      flush();
      current = {
        streamIndex: Number(subtitle[1]),
        language: subtitle[2] ?? null,
        kind: "subtitle",
        codec: subtitle[3].trim().toLowerCase(),
        title: null,
        fileName: null,
        mimeType: null
      };
      continue;
    }
    if (attachment) {
      flush();
      current = {
        streamIndex: Number(attachment[1]),
        language: null,
        kind: "attachment",
        codec: attachment[2].trim().toLowerCase(),
        title: null,
        fileName: null,
        mimeType: null
      };
      continue;
    }
    if (!current) {
      continue;
    }

    const metadata = /^\s*([A-Za-z0-9_-]+)\s*:\s*(.+?)\s*$/.exec(line);
    if (!metadata) {
      continue;
    }
    const key = metadata[1].toLowerCase();
    const value = metadata[2].trim();
    if (key === "title") {
      current.title = value;
    } else if (key === "filename") {
      current.fileName = value;
    } else if (key === "mimetype") {
      current.mimeType = value;
    }
  }
  flush();

  const subtitleStreams = streams.filter((stream) => stream.kind === "subtitle");
  return {
    subtitles: subtitleStreams.map((stream, index) => {
      const format = subtitleFormatFromCodec(stream.codec);
      const supported = format !== "unknown";
      return {
        id: `embedded:${stream.streamIndex}`,
        filePath: null,
        label:
          stream.title ??
          `${stream.language ? stream.language.toUpperCase() : "内嵌"} 字幕 ${index + 1}`,
        language: stream.language ? normalizeLanguage(stream.language) : null,
        source: "embedded" as const,
        format,
        streamIndex: stream.streamIndex,
        codec: stream.codec,
        supported,
        errorMessage: supported ? null : `内嵌字幕编码 ${stream.codec} 暂不支持 Web-native 渲染。`
      };
    }),
    fontAttachments: streams
      .filter(
        (stream) =>
          stream.kind === "attachment" &&
          (stream.codec.includes("ttf") || stream.codec.includes("otf"))
      )
      .map((stream) => ({
        streamIndex: stream.streamIndex,
        fileName: sanitizeAttachmentFileName(
          stream.fileName ??
            `font-${stream.streamIndex}.${stream.codec.includes("otf") ? "otf" : "ttf"}`
        ),
        mimeType: stream.mimeType
      }))
  };
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

async function extractEmbeddedFont(
  sessionId: string,
  mediaPath: string,
  attachment: FontAttachmentCandidate
): Promise<string> {
  const outputDirectory = join(getAppDataDirectory(), "subtitles", sessionId, "fonts");
  mkdirSync(outputDirectory, { recursive: true });
  const outputPath = join(outputDirectory, attachment.fileName);
  const result = await runFfmpeg([
    "-hide_banner",
    "-loglevel",
    "error",
    "-y",
    `-dump_attachment:${attachment.streamIndex}`,
    outputPath,
    "-i",
    mediaPath,
    "-t",
    "0",
    "-f",
    "null",
    "-"
  ]);

  if (result.code !== 0 || !existsSync(outputPath)) {
    throw new Error(result.stderr.trim() || "内嵌字幕字体抽取失败。");
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
    extension === ".ass" || extension === ".ssa"
      ? convertAssToVtt(content)
      : convertSrtToVtt(content);
  writeFileSync(outputPath, vtt, "utf8");
  return outputPath;
}

function convertSrtToVtt(content: string): string {
  const normalized = content
    .replace(/^\uFEFF/, "")
    .replace(/\r\n?/g, "\n")
    .trim();
  if (!normalized) {
    return "WEBVTT\n";
  }

  return `WEBVTT\n\n${normalized.replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, "$1.$2")}\n`;
}

function convertAssToVtt(content: string): string {
  const lines = content
    .replace(/^\uFEFF/, "")
    .replace(/\r\n?/g, "\n")
    .split("\n");
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
    values
      .slice(fieldCount - 1)
      .join(",")
      .trim()
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

function sanitizeAttachmentFileName(value: string): string {
  const sanitized = basename(value)
    .replace(/[^\p{L}\p{N}._ -]+/gu, "_")
    .trim();
  return sanitized || "subtitle-font.ttf";
}

function inferFontMimeType(filePath: string): string {
  return extname(filePath).toLowerCase() === ".otf" ? "font/otf" : "font/ttf";
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
