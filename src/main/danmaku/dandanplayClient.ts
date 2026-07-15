import { createHash } from "node:crypto";
import { open } from "node:fs/promises";
import { basename, extname } from "node:path";
import { z } from "zod";
import type { DanmakuEpisodeSearchResult, DanmakuItemView } from "../../shared/contracts/playback";

const DANDANPLAY_API_ORIGIN = "https://api.dandanplay.net";
const HASH_PREFIX_BYTES = 16 * 1024 * 1024;
const REQUEST_TIMEOUT_MS = 15_000;

const matchItemSchema = z.object({
  episodeId: z.number().int().positive(),
  animeId: z.number().int().positive(),
  animeTitle: z.string().nullable().optional(),
  episodeTitle: z.string().nullable().optional(),
  shift: z.number().finite().optional().default(0)
});

const matchResponseSchema = z.object({
  success: z.boolean(),
  errorCode: z.number().int().optional(),
  isMatched: z.boolean(),
  matches: z.array(matchItemSchema).nullable().optional()
});

const commentResponseSchema = z.object({
  comments: z
    .array(
      z.object({
        p: z.string().nullable().optional(),
        m: z.string().nullable().optional()
      })
    )
    .nullable()
    .optional()
});

const searchResponseSchema = z.object({
  success: z.boolean(),
  errorCode: z.number().int().optional(),
  animes: z
    .array(
      z.object({
        animeId: z.number().int().positive(),
        animeTitle: z.string(),
        type: z.string(),
        typeDescription: z.string().nullable().optional(),
        episodes: z.array(
          z.object({
            episodeId: z.number().int().positive(),
            episodeTitle: z.string()
          })
        )
      })
    )
    .nullable()
    .optional()
});

export type DandanplayLoadInput = {
  filePath: string;
  videoDurationSeconds: number | null;
};

export type DandanplayLoadResult = {
  provider: "dandanplay";
  episodeId: number;
  animeTitle: string | null;
  episodeTitle: string | null;
  items: DanmakuItemView[];
};

export type DandanplayEpisodeSearchInput = {
  anime: string;
};

export type DandanplayEpisodeSearchResult = DanmakuEpisodeSearchResult;

type DandanplayClientOptions = {
  appId: string;
  appSecret: string;
  userAgent?: string;
  fetchImpl?: typeof fetch;
};

export class DandanplayClient {
  private readonly fetchImpl: typeof fetch;

  constructor(private readonly options: DandanplayClientOptions) {
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async loadForFile(input: DandanplayLoadInput): Promise<DandanplayLoadResult> {
    const file = await inspectMediaFile(input.filePath);
    const matchResponse = await this.requestJson(
      `${DANDANPLAY_API_ORIGIN}/api/v2/match`,
      {
        method: "POST",
        redirect: "follow",
        body: JSON.stringify({
          fileName: file.name,
          fileHash: file.hash,
          fileSize: file.size,
          videoDuration: normalizeDuration(input.videoDurationSeconds),
          matchMode: "hashAndFileName"
        })
      },
      "匹配"
    );
    const parsedMatch = parseResponse(matchResponseSchema, matchResponse, "匹配");
    if (!parsedMatch.success) {
      throw new Error("弹弹play匹配请求失败。");
    }

    const matches = parsedMatch.matches ?? [];
    const match = selectMatch(matches);
    return this.loadComments(
      match.episodeId,
      match.shift,
      match.animeTitle ?? null,
      match.episodeTitle ?? null
    );
  }

  async searchEpisodes(
    input: DandanplayEpisodeSearchInput
  ): Promise<DandanplayEpisodeSearchResult[]> {
    const url = new URL(`${DANDANPLAY_API_ORIGIN}/api/v2/search/episodes`);
    url.searchParams.set("anime", input.anime.trim());
    const response = await this.requestJson(
      url.toString(),
      { method: "GET", redirect: "follow" },
      "搜索"
    );
    const parsed = parseResponse(searchResponseSchema, response, "搜索");
    if (!parsed.success) {
      throw new Error("弹弹play剧集搜索请求失败。");
    }

    return (parsed.animes ?? []).flatMap((anime) =>
      anime.episodes.map((episode) => ({
        animeId: anime.animeId,
        animeTitle: anime.animeTitle,
        type: anime.type,
        typeDescription: anime.typeDescription ?? null,
        episodeId: episode.episodeId,
        episodeTitle: episode.episodeTitle
      }))
    );
  }

  loadForEpisode(episodeId: number): Promise<DandanplayLoadResult> {
    return this.loadComments(episodeId, 0, null, null);
  }

  private async loadComments(
    episodeId: number,
    shift: number,
    animeTitle: string | null,
    episodeTitle: string | null
  ): Promise<DandanplayLoadResult> {
    const commentResponse = await this.requestJson(
      `${DANDANPLAY_API_ORIGIN}/api/v2/comment/${episodeId}?withRelated=true&chConvert=1`,
      { method: "GET", redirect: "follow" },
      "弹幕"
    );
    const parsedComments = parseResponse(commentResponseSchema, commentResponse, "弹幕");

    return {
      provider: "dandanplay",
      episodeId,
      animeTitle,
      episodeTitle,
      items: (parsedComments.comments ?? []).flatMap((comment) =>
        normalizeComment(comment.p, comment.m, shift)
      )
    };
  }

  private async requestJson(
    url: string,
    init: RequestInit,
    operation: "匹配" | "搜索" | "弹幕"
  ): Promise<unknown> {
    let response: Response;
    try {
      response = await this.fetchImpl(url, {
        ...init,
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "User-Agent": this.options.userAgent ?? "melonbang",
          "X-AppId": this.options.appId,
          "X-AppSecret": this.options.appSecret,
          ...init.headers
        },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
      });
    } catch {
      throw new Error(`弹弹play${operation}请求暂时不可用。`);
    }

    if (!response.ok) {
      throw new Error(`弹弹play${operation}请求失败（HTTP ${response.status}）。`);
    }

    try {
      return await response.json();
    } catch {
      throw new Error(`弹弹play${operation}响应格式无效。`);
    }
  }
}

async function inspectMediaFile(filePath: string): Promise<{
  name: string;
  hash: string;
  size: number;
}> {
  const handle = await open(filePath, "r").catch(() => {
    throw new Error("无法读取本地媒体信息用于弹幕匹配。");
  });

  try {
    const stats = await handle.stat();
    const prefixLength = Math.min(Number(stats.size), HASH_PREFIX_BYTES);
    const prefix = Buffer.alloc(prefixLength);
    const { bytesRead } = await handle.read(prefix, 0, prefixLength, 0);
    return {
      name: basename(filePath, extname(filePath)),
      hash: createHash("md5").update(prefix.subarray(0, bytesRead)).digest("hex"),
      size: Number(stats.size)
    };
  } catch {
    throw new Error("无法读取本地媒体信息用于弹幕匹配。");
  } finally {
    await handle.close();
  }
}

function normalizeDuration(value: number | null): number {
  if (value === null || !Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(2_147_483_647, Math.round(value)));
}

function selectMatch(matches: z.infer<typeof matchItemSchema>[]): z.infer<typeof matchItemSchema> {
  if (matches.length === 0) {
    throw new Error("弹弹play没有匹配到当前媒体的弹幕库。");
  }
  if (matches.length > 1) {
    throw new Error("弹弹play返回了多个候选，暂未自动选择弹幕库。");
  }
  return matches[0];
}

function normalizeComment(
  parameters: string | null | undefined,
  message: string | null | undefined,
  shiftSeconds: number
): DanmakuItemView[] {
  const text = message?.trim();
  const parts = parameters?.split(",");
  if (!text || !parts || parts.length < 3) {
    return [];
  }

  const sourceTime = Number(parts[0]);
  const mode = toDanmakuMode(parts[1]);
  const color = Number(parts[2]);
  const timeSeconds = sourceTime + shiftSeconds;
  if (
    !Number.isFinite(sourceTime) ||
    !Number.isFinite(timeSeconds) ||
    timeSeconds < 0 ||
    !mode ||
    !Number.isInteger(color) ||
    color < 0 ||
    color > 0xffffff
  ) {
    return [];
  }

  return [
    {
      timeSeconds,
      text,
      mode,
      color: `#${color.toString(16).padStart(6, "0")}`
    }
  ];
}

function toDanmakuMode(value: string | undefined): DanmakuItemView["mode"] | null {
  if (value === "1") return "scroll";
  if (value === "4") return "bottom";
  if (value === "5") return "top";
  return null;
}

function parseResponse<T>(schema: z.ZodType<T>, value: unknown, operation: string): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    throw new Error(`弹弹play${operation}响应格式无效。`);
  }
  return parsed.data;
}
