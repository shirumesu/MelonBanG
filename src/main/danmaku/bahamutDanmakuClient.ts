import { z } from "zod";
import type { DanmakuItemView } from "../../shared/contracts/playback";
import type { AutomaticDanmakuInput, DirectDanmakuLoadResult } from "./bilibiliDanmakuClient";

const BAHAMUT_ORIGIN = "https://ani.gamer.com.tw";
const REQUEST_TIMEOUT_MS = 10_000;

const commentsSchema = z.array(
  z.object({
    text: z.string().nullable().optional(),
    color: z.string().nullable().optional(),
    position: z.number().int().nullable().optional(),
    time: z.number().finite().nullable().optional()
  })
);

type BahamutDanmakuClientOptions = {
  fetchImpl?: typeof fetch;
  userAgent?: string;
};

export class BahamutDanmakuClient {
  private readonly fetchImpl: typeof fetch;

  constructor(private readonly options: BahamutDanmakuClientOptions = {}) {
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async loadAutomatic(input: AutomaticDanmakuInput): Promise<DirectDanmakuLoadResult> {
    const titles = [...new Set(input.animeTitles.map((title) => title.trim()).filter(Boolean))];
    if (titles.length === 0 || !Number.isFinite(input.episodeNumber)) {
      throw new Error("巴哈自动匹配缺少番剧或章节信息，请手动输入动画疯 sn。");
    }
    const expectedTitles = new Set(titles.map(normalizeTitle));

    for (const title of titles) {
      const searchBody = new URLSearchParams({ keyword: title }).toString();
      const searchHtml = await this.requestText(`${BAHAMUT_ORIGIN}/search.php`, {
        method: "POST",
        body: searchBody,
        headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" }
      });
      const searchResults = parseSearchResults(searchHtml);
      const exact = searchResults.filter((candidate) =>
        expectedTitles.has(normalizeTitle(candidate.title))
      );
      const selected =
        exact.length === 1 ? exact[0] : searchResults.length === 1 ? searchResults[0] : null;
      if (!selected) continue;

      const seriesHtml = await this.requestText(
        `${BAHAMUT_ORIGIN}/animeRef.php?sn=${selected.seriesSn}`,
        { headers: { Referer: `${BAHAMUT_ORIGIN}/search.php` } }
      );
      const episode = parseEpisodes(seriesHtml).find(
        (candidate) => candidate.episodeNumber === input.episodeNumber
      );
      if (!episode) continue;

      const result = await this.loadSn(episode.sn);
      return {
        ...result,
        matchLabel: `${selected.title} · 第${input.episodeNumber}话${
          episode.title ? ` ${episode.title}` : ""
        }`
      };
    }

    throw new Error("巴哈没有自动匹配到标题与集数都一致的动画，请手动输入动画疯 sn。");
  }

  loadByLocator(locator: string): Promise<DirectDanmakuLoadResult> {
    const match = locator.trim().match(/(?:sn=)?(\d+)/i);
    if (!match) {
      return Promise.reject(new Error("请输入巴哈动画疯 sn 或对应播放链接。"));
    }
    return this.loadSn(Number(match[1]));
  }

  private async loadSn(sn: number): Promise<DirectDanmakuLoadResult> {
    if (!Number.isInteger(sn) || sn <= 0) {
      throw new Error("巴哈动画疯 sn 无效。");
    }
    const body = new URLSearchParams({ sn: String(sn) }).toString();
    const value = await this.requestJson(`${BAHAMUT_ORIGIN}/ajax/danmuGet.php`, {
      method: "POST",
      body,
      headers: {
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
        Origin: BAHAMUT_ORIGIN,
        Referer: `${BAHAMUT_ORIGIN}/animeVideo.php?sn=${sn}`
      }
    });
    const parsed = commentsSchema.safeParse(value);
    if (!parsed.success) throw new Error("巴哈弹幕响应格式无效。");

    return {
      provider: "bahamut",
      locator: `sn=${sn}`,
      matchLabel: `巴哈动画疯 sn=${sn}`,
      items: parsed.data
        .flatMap(normalizeComment)
        .sort((left, right) => left.timeSeconds - right.timeSeconds)
    };
  }

  private async requestJson(url: string, init: RequestInit): Promise<unknown> {
    const response = await this.request(url, init);
    try {
      return await response.json();
    } catch {
      throw new Error("巴哈弹幕响应格式无效。");
    }
  }

  private async requestText(url: string, init: RequestInit): Promise<string> {
    const response = await this.request(url, init);
    return response.text();
  }

  private async request(url: string, init: RequestInit): Promise<Response> {
    let response: Response;
    try {
      response = await this.fetchImpl(url, {
        ...init,
        headers: {
          Accept: "text/html,application/json;q=0.9,*/*;q=0.8",
          "User-Agent":
            this.options.userAgent ??
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 melonbang",
          Referer: `${BAHAMUT_ORIGIN}/`,
          ...init.headers
        },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
      });
    } catch {
      throw new Error("巴哈弹幕请求暂时不可用，可能受地区或站点限制。");
    }
    if (!response.ok) {
      throw new Error(`巴哈弹幕请求失败（HTTP ${response.status}）。`);
    }
    return response;
  }
}

function parseSearchResults(html: string): Array<{ title: string; seriesSn: number }> {
  const results: Array<{ title: string; seriesSn: number }> = [];
  const pattern =
    /<img[^>]*alt=["']([^"']+)["'][^>]*>[\s\S]{0,2000}?<a[^>]*href=["'][^"']*animeRef\.php\?sn=(\d+)["'][^>]*>/gi;
  for (const match of html.matchAll(pattern)) {
    const title = decodeHtml(match[1]).trim();
    const seriesSn = Number(match[2]);
    if (title && Number.isInteger(seriesSn) && seriesSn > 0) results.push({ title, seriesSn });
  }
  return results;
}

function parseEpisodes(html: string): Array<{ sn: number; episodeNumber: number; title: string }> {
  const results: Array<{ sn: number; episodeNumber: number; title: string }> = [];
  const pattern = /<a[^>]*href=["'][^"']*animeVideo\.php\?sn=(\d+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  for (const match of html.matchAll(pattern)) {
    const label = decodeHtml(stripHtml(match[2])).trim();
    const episodeMatch = label.match(/(?:\[|【|\()?\s*(\d+(?:\.\d+)?)\s*(?:\]|】|\))?/);
    if (!episodeMatch) continue;
    const sn = Number(match[1]);
    const episodeNumber = Number(episodeMatch[1]);
    if (!Number.isInteger(sn) || sn <= 0 || !Number.isFinite(episodeNumber)) continue;
    const title = label
      .replace(episodeMatch[0], "")
      .replace(/^[\s·:：\-–—]+/, "")
      .trim();
    results.push({ sn, episodeNumber, title });
  }
  return results;
}

function normalizeComment(comment: z.infer<typeof commentsSchema>[number]): DanmakuItemView[] {
  const text = comment.text?.trim();
  const time = comment.time;
  const mode = toBahamutMode(comment.position);
  const color = normalizeColor(comment.color);
  if (!text || time === null || time === undefined || time < 0 || !mode || !color) return [];
  return [{ timeSeconds: time / 10, text, mode, color }];
}

function toBahamutMode(value: number | null | undefined): DanmakuItemView["mode"] | null {
  if (value === 0) return "scroll";
  if (value === 1) return "top";
  if (value === 2) return "bottom";
  return null;
}

function normalizeColor(value: string | null | undefined): string | null {
  const match = value?.trim().match(/^#?([0-9a-f]{6})$/i);
  return match ? `#${match[1].toLocaleLowerCase()}` : null;
}

function normalizeTitle(value: string): string {
  return decodeHtml(stripHtml(value))
    .normalize("NFKC")
    .toLocaleLowerCase()
    .replace(/[\s\p{P}\p{S}]+/gu, "");
}

function stripHtml(value: string): string {
  return value.replace(/<[^>]+>/g, "");
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}
