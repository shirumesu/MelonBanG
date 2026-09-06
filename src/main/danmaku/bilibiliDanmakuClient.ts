import { z } from "zod";
import type { DanmakuItemView } from "../../shared/contracts/playback";

const BILIBILI_API_ORIGIN = "https://api.bilibili.com";
const REQUEST_TIMEOUT_MS = 10_000;
const SEGMENT_SECONDS = 6 * 60;
const SEGMENT_CONCURRENCY = 6;

const searchResponseSchema = z.object({
  code: z.number().int(),
  data: z
    .object({
      result: z
        .array(
          z.object({
            title: z.string(),
            org_title: z.string().optional().default(""),
            season_id: z.number().int().positive(),
            eps: z
              .array(
                z.object({
                  id: z.number().int().positive(),
                  title: z.string(),
                  index_title: z.string().optional().default(""),
                  long_title: z.string().optional().default("")
                })
              )
              .optional()
              .default([])
          })
        )
        .nullable()
        .optional()
    })
    .nullable()
    .optional()
});

const seasonEpisodeSchema = z.object({
  id: z.number().int().positive(),
  cid: z.number().int().nonnegative().nullable().optional(),
  duration: z.number().int().nonnegative().nullable().optional(),
  title: z.string(),
  long_title: z.string().nullable().optional()
});

const seasonResponseSchema = z.object({
  code: z.number().int(),
  result: z
    .object({
      title: z.string().optional().default(""),
      episodes: z.array(seasonEpisodeSchema),
      section: z
        .array(
          z.object({
            id: z.number().int().positive(),
            title: z.string(),
            episodes: z.array(seasonEpisodeSchema)
          })
        )
        .optional()
        .default([])
    })
    .nullable()
    .optional()
});

const videoResponseSchema = z.object({
  code: z.number().int(),
  data: z
    .object({
      bvid: z.string(),
      title: z.string(),
      pages: z.array(
        z.object({
          page: z.number().int().positive(),
          cid: z.number().int().positive(),
          part: z.string(),
          duration: z.number().int().positive()
        })
      )
    })
    .nullable()
    .optional()
});

const fingerprintResponseSchema = z.object({
  code: z.number().int(),
  data: z
    .object({
      b_3: z.string(),
      b_4: z.string()
    })
    .nullable()
    .optional()
});

export type AutomaticDanmakuInput = {
  animeTitles: string[];
  episodeNumber: number;
};

export type DirectDanmakuLoadResult = {
  provider: "bilibili" | "bahamut";
  locator: string;
  matchLabel: string;
  items: DanmakuItemView[];
};

type BilibiliDanmakuClientOptions = {
  fetchImpl?: typeof fetch;
  userAgent?: string;
};

export class BilibiliDanmakuClient {
  private readonly fetchImpl: typeof fetch;
  private anonymousCookiePromise: Promise<string | null> | null = null;

  constructor(private readonly options: BilibiliDanmakuClientOptions = {}) {
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async loadAutomatic(input: AutomaticDanmakuInput): Promise<DirectDanmakuLoadResult> {
    const titles = uniqueNonEmpty(input.animeTitles);
    if (titles.length === 0 || !Number.isFinite(input.episodeNumber)) {
      throw new Error("Bilibili自动匹配缺少番剧或章节信息，请手动输入 BV / EP。");
    }

    const expectedTitles = new Set(titles.map(normalizeTitle));
    for (const title of titles) {
      const result = await this.searchExactEpisode(title, expectedTitles, input.episodeNumber);
      if (result) {
        return this.loadEpisode(result.episodeId);
      }
    }

    throw new Error("Bilibili没有找到标题与集数都一致的番剧，请手动输入 BV / EP。");
  }

  async loadByLocator(locator: string): Promise<DirectDanmakuLoadResult> {
    const value = locator.trim();
    const episodeMatch = value.match(/(?:^|\/)ep(\d+)(?:\b|$)/i) ?? value.match(/^ep(\d+)$/i);
    if (episodeMatch) {
      return this.loadEpisode(Number(episodeMatch[1]));
    }

    const bvid = value.match(/BV[0-9A-Za-z]+/i)?.[0];
    if (!bvid) {
      throw new Error("请输入 Bilibili BV 号、EP 号或对应播放链接。");
    }
    const page = readPageNumber(value);
    return this.loadVideoPage(bvid, page);
  }

  private async searchExactEpisode(
    keyword: string,
    expectedTitles: Set<string>,
    episodeNumber: number
  ): Promise<{ episodeId: number } | null> {
    const url = new URL(`${BILIBILI_API_ORIGIN}/x/web-interface/wbi/search/type`);
    url.searchParams.set("search_type", "media_bangumi");
    url.searchParams.set("keyword", keyword);
    const response = parseJson(
      searchResponseSchema,
      await this.requestJson(url.toString()),
      "搜索"
    );
    if (response.code !== 0) {
      throw new Error(`Bilibili搜索请求失败（code ${response.code}）。`);
    }

    const candidates = (response.data?.result ?? [])
      .map((candidate) => {
        const title = stripHtml(candidate.title);
        const originalTitle = stripHtml(candidate.org_title);
        const titleScore = expectedTitles.has(normalizeTitle(title))
          ? 0
          : expectedTitles.has(normalizeTitle(originalTitle))
            ? 1
            : Number.POSITIVE_INFINITY;
        const episode = candidate.eps.find(
          (entry) =>
            parseEpisodeNumber(entry.title) === episodeNumber ||
            parseEpisodeNumber(entry.index_title) === episodeNumber
        );
        return { titleScore, episode };
      })
      .filter(
        (
          candidate
        ): candidate is typeof candidate & { episode: NonNullable<typeof candidate.episode> } =>
          Number.isFinite(candidate.titleScore) && Boolean(candidate.episode)
      )
      .sort((left, right) => left.titleScore - right.titleScore);

    const best = candidates[0];
    const ambiguous = candidates[1] && candidates[1].titleScore === best?.titleScore;
    if (!best || ambiguous) return null;
    return { episodeId: best.episode.id };
  }

  private async loadEpisode(episodeId: number): Promise<DirectDanmakuLoadResult> {
    const response = parseJson(
      seasonResponseSchema,
      await this.requestJson(
        `${BILIBILI_API_ORIGIN}/pgc/view/web/season?ep_id=${encodeURIComponent(episodeId)}`
      ),
      "剧集"
    );
    if (response.code !== 0 || !response.result) {
      throw new Error(`Bilibili剧集请求失败（code ${response.code}）。`);
    }
    const episode = [
      ...response.result.episodes,
      ...response.result.section.flatMap((section) => section.episodes)
    ].find((candidate) => candidate.id === episodeId);
    if (!episode?.cid || !episode.duration) {
      throw new Error("Bilibili响应中没有所选 EP 的播放信息。");
    }

    const title = response.result.title.trim() || "Bilibili番剧";
    const episodeLabel = formatEpisodeLabel(episode.title, episode.long_title ?? "");
    return {
      provider: "bilibili",
      locator: `ep${episode.id}`,
      matchLabel: `${title} · ${episodeLabel}`,
      items: await this.loadComments(episode.cid, episode.duration / 1000, `ep${episode.id}`)
    };
  }

  private async loadVideoPage(bvid: string, pageNumber: number): Promise<DirectDanmakuLoadResult> {
    const response = parseJson(
      videoResponseSchema,
      await this.requestJson(
        `${BILIBILI_API_ORIGIN}/x/web-interface/view?bvid=${encodeURIComponent(bvid)}`
      ),
      "视频"
    );
    if (response.code !== 0 || !response.data) {
      throw new Error(`Bilibili视频请求失败（code ${response.code}）。`);
    }
    const page = response.data.pages.find((candidate) => candidate.page === pageNumber);
    if (!page) {
      throw new Error(`该 BV 没有 P${pageNumber}，请检查链接中的分P编号。`);
    }

    return {
      provider: "bilibili",
      locator: `${response.data.bvid}?p=${page.page}`,
      matchLabel: `${response.data.title} · P${page.page} ${page.part}`,
      items: await this.loadComments(
        page.cid,
        page.duration,
        `${response.data.bvid}?p=${page.page}`
      )
    };
  }

  private async loadComments(
    cid: number,
    durationSeconds: number,
    refererLocator: string
  ): Promise<DanmakuItemView[]> {
    const anonymousCookie = await this.getAnonymousCookie();
    const [xmlResult, segmentResult] = await Promise.allSettled([
      this.loadXmlComments(cid, refererLocator),
      this.loadSegments(cid, durationSeconds, refererLocator, anonymousCookie)
    ]);
    const xmlItems = xmlResult.status === "fulfilled" ? xmlResult.value : [];
    const segmentItems = segmentResult.status === "fulfilled" ? segmentResult.value : [];
    const items = mergeDanmakuItems(xmlItems, segmentItems);
    if (
      items.length > 0 ||
      xmlResult.status === "fulfilled" ||
      segmentResult.status === "fulfilled"
    ) {
      return items;
    }
    throw new Error("Bilibili弹幕请求暂时不可用。");
  }

  private async loadXmlComments(cid: number, refererLocator: string): Promise<DanmakuItemView[]> {
    const response = await this.request(`https://comment.bilibili.com/${cid}.xml`, {
      headers: {
        Accept: "text/xml,application/xml;q=0.9,*/*;q=0.8",
        Referer: toBilibiliReferer(refererLocator)
      }
    });
    return decodeDanmakuXml(await response.text());
  }

  private async loadSegments(
    cid: number,
    durationSeconds: number,
    refererLocator: string,
    anonymousCookie: string | null
  ): Promise<DanmakuItemView[]> {
    const segmentCount = Math.max(1, Math.ceil(durationSeconds / SEGMENT_SECONDS));
    const segments = Array.from({ length: segmentCount }, (_, index) => index + 1);
    const items: DanmakuItemView[] = [];

    for (let offset = 0; offset < segments.length; offset += SEGMENT_CONCURRENCY) {
      const batch = segments.slice(offset, offset + SEGMENT_CONCURRENCY);
      const decoded = await Promise.allSettled(
        batch.map(async (segmentIndex) => {
          const url = new URL(`${BILIBILI_API_ORIGIN}/x/v2/dm/web/seg.so`);
          url.searchParams.set("type", "1");
          url.searchParams.set("oid", String(cid));
          url.searchParams.set("segment_index", String(segmentIndex));
          const response = await this.request(url.toString(), {
            headers: {
              Accept: "application/octet-stream,application/protobuf;q=0.9,*/*;q=0.8",
              ...(anonymousCookie ? { Cookie: anonymousCookie } : {}),
              Origin: "https://www.bilibili.com",
              Referer: toBilibiliReferer(refererLocator)
            }
          });
          return decodeDanmakuSegment(new Uint8Array(await response.arrayBuffer()));
        })
      );
      items.push(
        ...decoded.flatMap((result) => (result.status === "fulfilled" ? result.value : []))
      );
    }

    if (items.length === 0) {
      throw new Error("Bilibili分段弹幕请求暂时不可用。");
    }
    return items.sort((left, right) => left.timeSeconds - right.timeSeconds);
  }

  private getAnonymousCookie(): Promise<string | null> {
    this.anonymousCookiePromise ??= this.loadAnonymousCookie();
    return this.anonymousCookiePromise;
  }

  private async loadAnonymousCookie(): Promise<string | null> {
    try {
      const response = parseJson(
        fingerprintResponseSchema,
        await this.requestJson(`${BILIBILI_API_ORIGIN}/x/frontend/finger/spi`),
        "匿名标识"
      );
      if (response.code !== 0 || !response.data?.b_3 || !response.data.b_4) return null;
      return [
        `buvid3=${response.data.b_3}`,
        `buvid4=${response.data.b_4}`,
        `b_nut=${Math.floor(Date.now() / 1000)}`
      ].join("; ");
    } catch {
      return null;
    }
  }

  private async requestJson(url: string): Promise<unknown> {
    const response = await this.request(url, { headers: { Accept: "application/json" } });
    try {
      return await response.json();
    } catch {
      throw new Error("Bilibili响应格式无效。");
    }
  }

  private async request(url: string, init: RequestInit): Promise<Response> {
    let response: Response;
    try {
      response = await this.fetchImpl(url, {
        ...init,
        headers: {
          "User-Agent":
            this.options.userAgent ??
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
              "(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36",
          "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
          Referer: "https://www.bilibili.com/",
          ...init.headers
        },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
      });
    } catch {
      throw new Error("Bilibili弹幕请求暂时不可用。");
    }
    if (!response.ok) {
      throw new Error(`Bilibili弹幕请求失败（HTTP ${response.status}）。`);
    }
    return response;
  }
}

function decodeDanmakuSegment(bytes: Uint8Array): DanmakuItemView[] {
  const reader = new ProtobufReader(bytes);
  const items: DanmakuItemView[] = [];
  while (!reader.done) {
    const key = reader.readVarintNumber();
    const field = key >>> 3;
    const wireType = key & 7;
    if (field === 1 && wireType === 2) {
      const item = decodeDanmakuElement(reader.readBytes());
      if (item) items.push(item);
    } else {
      reader.skip(wireType);
    }
  }
  return items;
}

function mergeDanmakuItems(...groups: DanmakuItemView[][]): DanmakuItemView[] {
  const seen = new Set<string>();
  return groups
    .flat()
    .filter((item) => {
      const key = `${Math.round(item.timeSeconds * 1000)}\u0000${item.mode}\u0000${item.color}\u0000${item.text}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .sort((left, right) => left.timeSeconds - right.timeSeconds);
}

function decodeDanmakuXml(xml: string): DanmakuItemView[] {
  if (!/<i(?:\s|>)/i.test(xml)) {
    throw new Error("Bilibili XML 弹幕响应格式无效。");
  }
  const items: DanmakuItemView[] = [];
  const pattern = /<d\b[^>]*\bp=["']([^"']+)["'][^>]*>([\s\S]*?)<\/d>/gi;
  for (const match of xml.matchAll(pattern)) {
    const parameters = match[1].split(",");
    const timeSeconds = Number(parameters[0]);
    const mode = toBilibiliMode(Number(parameters[1]));
    const color = Number(parameters[3]);
    const text = decodeXmlText(match[2]).trim();
    if (
      !Number.isFinite(timeSeconds) ||
      timeSeconds < 0 ||
      !mode ||
      !Number.isInteger(color) ||
      color < 0 ||
      color > 0xffffff ||
      !text
    ) {
      continue;
    }
    items.push({
      timeSeconds,
      text,
      mode,
      color: `#${color.toString(16).padStart(6, "0")}`
    });
  }
  return items.sort((left, right) => left.timeSeconds - right.timeSeconds);
}

function decodeDanmakuElement(bytes: Uint8Array): DanmakuItemView | null {
  const reader = new ProtobufReader(bytes);
  let progress: number | null = null;
  let mode: DanmakuItemView["mode"] | null = null;
  let color: number | null = null;
  let content = "";
  while (!reader.done) {
    const key = reader.readVarintNumber();
    const field = key >>> 3;
    const wireType = key & 7;
    if (field === 2 && wireType === 0) progress = reader.readVarintNumber();
    else if (field === 3 && wireType === 0) mode = toBilibiliMode(reader.readVarintNumber());
    else if (field === 5 && wireType === 0) color = reader.readVarintNumber();
    else if (field === 7 && wireType === 2) content = new TextDecoder().decode(reader.readBytes());
    else reader.skip(wireType);
  }
  const text = content.trim();
  if (progress === null || progress < 0 || !mode || color === null || !text) return null;
  return {
    timeSeconds: progress / 1000,
    text,
    mode,
    color: `#${Math.min(0xffffff, Math.max(0, color)).toString(16).padStart(6, "0")}`
  };
}

class ProtobufReader {
  private offset = 0;

  constructor(private readonly bytes: Uint8Array) {}

  get done(): boolean {
    return this.offset >= this.bytes.length;
  }

  readVarintNumber(): number {
    let value = 0n;
    let shift = 0n;
    for (let index = 0; index < 10; index += 1) {
      const byte = this.bytes[this.offset++];
      if (byte === undefined) throw new Error("Bilibili弹幕分段格式无效。");
      value |= BigInt(byte & 0x7f) << shift;
      if ((byte & 0x80) === 0) return Number(value);
      shift += 7n;
    }
    throw new Error("Bilibili弹幕分段格式无效。");
  }

  readBytes(): Uint8Array {
    const length = this.readVarintNumber();
    const end = this.offset + length;
    if (!Number.isSafeInteger(length) || length < 0 || end > this.bytes.length) {
      throw new Error("Bilibili弹幕分段格式无效。");
    }
    const value = this.bytes.subarray(this.offset, end);
    this.offset = end;
    return value;
  }

  skip(wireType: number): void {
    if (wireType === 0) {
      this.readVarintNumber();
      return;
    }
    if (wireType === 1) {
      this.offset += 8;
    } else if (wireType === 2) {
      this.readBytes();
    } else if (wireType === 5) {
      this.offset += 4;
    } else {
      throw new Error("Bilibili弹幕分段格式无效。");
    }
    if (this.offset > this.bytes.length) throw new Error("Bilibili弹幕分段格式无效。");
  }
}

function parseJson<T>(schema: z.ZodType<T>, value: unknown, operation: string): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) throw new Error(`Bilibili${operation}响应格式无效。`);
  return parsed.data;
}

function toBilibiliMode(value: number): DanmakuItemView["mode"] | null {
  if (value === 4) return "bottom";
  if (value === 5) return "top";
  if (value >= 1 && value <= 3) return "scroll";
  if (value === 6) return "scroll";
  return null;
}

function stripHtml(value: string): string {
  return value
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/gi, "&")
    .trim();
}

function normalizeTitle(value: string): string {
  return stripHtml(value)
    .normalize("NFKC")
    .toLocaleLowerCase()
    .replace(/[\s\p{P}\p{S}]+/gu, "");
}

function uniqueNonEmpty(values: string[]): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function parseEpisodeNumber(value: string): number | null {
  const match = stripHtml(value).match(/(?:^|[^\d])(\d+(?:\.\d+)?)(?:[^\d]|$)/);
  if (!match) return null;
  const number = Number(match[1]);
  return Number.isFinite(number) ? number : null;
}

function formatEpisodeLabel(title: string, longTitle: string): string {
  const normalizedTitle = stripHtml(title).trim();
  const numericTitle = normalizedTitle.match(/^\d+(?:\.\d+)?$/);
  const prefix = numericTitle ? `第${numericTitle[0]}话` : normalizedTitle;
  return longTitle.trim() ? `${prefix} ${longTitle.trim()}` : prefix;
}

function decodeXmlText(value: string): string {
  return value
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&#x([0-9a-f]+);/gi, (_match, hex: string) =>
      String.fromCodePoint(Number.parseInt(hex, 16))
    )
    .replace(/&#(\d+);/g, (_match, decimal: string) =>
      String.fromCodePoint(Number.parseInt(decimal, 10))
    )
    .replace(/&quot;/gi, '"')
    .replace(/&apos;|&#39;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&amp;/gi, "&");
}

function readPageNumber(locator: string): number {
  const match = locator.match(/[?&]p=(\d+)/i);
  if (!match) return 1;
  const value = Number(match[1]);
  return Number.isInteger(value) && value > 0 ? value : 1;
}

function toBilibiliReferer(locator: string): string {
  if (/^ep\d+$/i.test(locator)) return `https://www.bilibili.com/bangumi/play/${locator}`;
  return `https://www.bilibili.com/video/${locator}`;
}
