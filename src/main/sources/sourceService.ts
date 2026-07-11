import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { DownloadTaskView, TorrentInput } from "../../shared/contracts/download";
import type {
  SourceCandidateView,
  SourceEnqueueInput,
  SourceProviderDiagnostic,
  SourceSearchInput,
  SourceSearchResult
} from "../../shared/contracts/source";
import dmhyPack from "../../../source-packs/builtin/dmhy.json";
import mikanPack from "../../../source-packs/builtin/mikan.json";
import { getDownloadService } from "../download/downloadService";
import { parseRssItems, type RssItem } from "./rssParser";

export type BuiltInSourcePack = {
  id: string;
  name: string;
  origin: string;
  searchUrlTemplate: string;
  resultKind: "torrent-enclosure" | "magnet-enclosure";
  capabilities: Array<"http.get" | "parse.rss">;
};

export type SourceDownloadService = {
  create(input: TorrentInput): DownloadTaskView | Promise<DownloadTaskView>;
};

type CandidateRef = {
  candidate: SourceCandidateView;
  downloadRef: string;
  expiresAt: number;
};

type SourceServiceOptions = {
  packs?: BuiltInSourcePack[];
  fetchImpl?: (url: string, init?: RequestInit) => Promise<Response>;
  downloadService?: SourceDownloadService;
  now?: () => Date;
};

const rssBodyLimitBytes = 6 * 1024 * 1024;
const torrentBodyLimitBytes = 5 * 1024 * 1024;
const candidateTtlMs = 10 * 60 * 1000;
const requestTimeoutMs = 15_000;
const allowedCapabilities = new Set(["http.get", "parse.rss"]);
const sourcePackSchema = z.object({
  id: z.string(),
  name: z.string(),
  origin: z.string(),
  searchUrlTemplate: z.string(),
  resultKind: z.enum(["torrent-enclosure", "magnet-enclosure"]),
  capabilities: z.array(z.enum(["http.get", "parse.rss"]))
});

let serviceInstance: SourceService | null = null;

export function getSourceService(): SourceService {
  serviceInstance ??= new SourceService();
  return serviceInstance;
}

export class SourceService {
  private readonly packs: BuiltInSourcePack[];
  private readonly fetchImpl: (url: string, init?: RequestInit) => Promise<Response>;
  private readonly downloadService: SourceDownloadService;
  private readonly now: () => Date;
  private readonly candidates = new Map<string, CandidateRef>();

  constructor(options: SourceServiceOptions = {}) {
    const packs: unknown[] = options.packs ?? [mikanPack, dmhyPack];
    this.packs = packs.map(validatePack);
    this.fetchImpl = options.fetchImpl ?? fetch;
    this.downloadService = options.downloadService ?? getDownloadService();
    this.now = options.now ?? (() => new Date());
  }

  async search(input: SourceSearchInput): Promise<SourceSearchResult> {
    const keyword = input.keyword.trim();
    if (!Number.isSafeInteger(input.subjectId) || input.subjectId <= 0) {
      throw new Error("条目编号无效。");
    }
    if (!keyword || keyword.length > 120) {
      throw new Error("搜索关键词长度应为 1 到 120 个字符。");
    }

    this.removeExpiredCandidates();
    const providerResults = await Promise.all(
      this.packs.map(async (pack) => {
        try {
          const candidates = await this.searchProvider(pack, keyword);
          return {
            candidates,
            diagnostic: {
              providerId: pack.id,
              providerName: pack.name,
              status: "ok",
              resultCount: candidates.length
            } satisfies SourceProviderDiagnostic
          };
        } catch (error) {
          return {
            candidates: [],
            diagnostic: {
              providerId: pack.id,
              providerName: pack.name,
              status: "error",
              resultCount: 0,
              message: toProviderError(pack.name, error)
            } satisfies SourceProviderDiagnostic
          };
        }
      })
    );

    return {
      candidates: providerResults.flatMap((result) => result.candidates),
      providers: providerResults.map((result) => result.diagnostic),
      searchedAt: this.now().toISOString()
    };
  }

  async enqueue(input: SourceEnqueueInput): Promise<DownloadTaskView> {
    this.removeExpiredCandidates();
    const stored = this.candidates.get(input.candidateId);
    if (!stored) {
      throw new Error("资源已过期，请重新搜索。");
    }

    if (stored.candidate.downloadKind === "magnet") {
      const task = await this.downloadService.create({ kind: "magnet", uri: stored.downloadRef });
      this.candidates.delete(input.candidateId);
      return task;
    }

    const pack = this.requirePack(stored.candidate.providerId);
    const torrentUrl = requireAllowedUrl(stored.downloadRef, pack);
    const response = await this.fetchWithTimeout(torrentUrl.href);
    if (!response.ok) {
      throw new Error(`种子文件获取失败（HTTP ${response.status}）。`);
    }
    if (response.url) {
      requireAllowedUrl(response.url, pack);
    }
    const declaredLength = Number(response.headers.get("content-length"));
    if (Number.isFinite(declaredLength) && declaredLength > torrentBodyLimitBytes) {
      throw new Error("种子文件超过允许大小。");
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > torrentBodyLimitBytes) {
      throw new Error(bytes.byteLength === 0 ? "种子文件内容为空。" : "种子文件超过允许大小。");
    }

    const task = await this.downloadService.create({
      kind: "torrentFile",
      name: `${sanitizeFileName(stored.candidate.title)}.torrent`,
      bytes
    });
    this.candidates.delete(input.candidateId);
    return task;
  }

  private async searchProvider(
    pack: BuiltInSourcePack,
    keyword: string
  ): Promise<SourceCandidateView[]> {
    const searchUrl = requireAllowedUrl(
      pack.searchUrlTemplate.replace("{keyword}", encodeURIComponent(keyword)),
      pack
    );
    const response = await this.fetchWithTimeout(searchUrl.href);
    if (!response.ok) {
      throw new HttpSourceError(response.status);
    }
    const declaredLength = Number(response.headers.get("content-length"));
    if (Number.isFinite(declaredLength) && declaredLength > rssBodyLimitBytes) {
      throw new Error("RSS 响应超过允许大小。");
    }
    const xml = await response.text();
    if (Buffer.byteLength(xml, "utf8") > rssBodyLimitBytes) {
      throw new Error("RSS 响应超过允许大小。");
    }

    return parseRssItems(xml).flatMap((item) => {
      const normalized = normalizeItem(pack, item);
      if (!normalized) {
        return [];
      }
      const candidateId = randomUUID();
      const candidate: SourceCandidateView = { candidateId, ...normalized.candidate };
      this.candidates.set(candidateId, {
        candidate,
        downloadRef: normalized.downloadRef,
        expiresAt: this.now().getTime() + candidateTtlMs
      });
      return [candidate];
    });
  }

  private fetchWithTimeout(url: string): Promise<Response> {
    return this.fetchImpl(url, {
      method: "GET",
      redirect: "follow",
      signal: AbortSignal.timeout(requestTimeoutMs),
      headers: {
        Accept: "application/rss+xml, application/xml, text/xml, application/x-bittorrent",
        "User-Agent": "melonbang/0.1.0 (desktop RSS client)"
      }
    });
  }

  private requirePack(providerId: string): BuiltInSourcePack {
    const pack = this.packs.find((entry) => entry.id === providerId);
    if (!pack) {
      throw new Error("资源来源不可用。");
    }
    return pack;
  }

  private removeExpiredCandidates(): void {
    const now = this.now().getTime();
    for (const [candidateId, candidate] of this.candidates) {
      if (candidate.expiresAt <= now) {
        this.candidates.delete(candidateId);
      }
    }
  }
}

function validatePack(input: unknown): BuiltInSourcePack {
  const pack = sourcePackSchema.parse(input);
  if (!/^[a-z][a-z0-9-]*$/.test(pack.id) || !pack.name.trim()) {
    throw new Error("内置数据源定义无效。");
  }
  const origin = new URL(pack.origin);
  const templateUrl = new URL(pack.searchUrlTemplate.replace("{keyword}", "test"));
  if (
    origin.protocol !== "https:" ||
    origin.origin !== pack.origin ||
    templateUrl.origin !== origin.origin ||
    !pack.searchUrlTemplate.includes("{keyword}") ||
    pack.capabilities.some((capability) => !allowedCapabilities.has(capability))
  ) {
    throw new Error(`${pack.name}的数据源定义请求了不受支持的能力。`);
  }
  return { ...pack, name: pack.name.trim() };
}

function normalizeItem(
  pack: BuiltInSourcePack,
  item: RssItem
): { candidate: Omit<SourceCandidateView, "candidateId">; downloadRef: string } | null {
  const detailUrl = normalizeDetailUrl(item.link, pack);
  if (!detailUrl) {
    return null;
  }
  const publishedAt = normalizeDate(item.publishedAt);

  if (pack.resultKind === "torrent-enclosure") {
    const torrentUrl = safeAllowedUrl(item.enclosureUrl, pack);
    const hash = extractInfoHash(`${detailUrl} ${item.enclosureUrl}`);
    if (!torrentUrl || !hash || !torrentUrl.pathname.toLowerCase().endsWith(".torrent")) {
      return null;
    }
    return {
      candidate: {
        providerId: pack.id,
        providerName: pack.name,
        providerItemId: hash.toLowerCase(),
        title: item.title,
        detailUrl,
        publishedAt,
        sizeBytes: item.enclosureLength,
        downloadKind: "torrentFile"
      },
      downloadRef: torrentUrl.href
    };
  }

  const topicId = /\/topics\/view\/(\d+)(?:_|\/|$)/i.exec(detailUrl)?.[1];
  if (!topicId || !isValidMagnet(item.enclosureUrl)) {
    return null;
  }
  return {
    candidate: {
      providerId: pack.id,
      providerName: pack.name,
      providerItemId: topicId,
      title: item.title,
      detailUrl,
      publishedAt,
      sizeBytes: null,
      downloadKind: "magnet"
    },
    downloadRef: item.enclosureUrl
  };
}

function normalizeDetailUrl(value: string, pack: BuiltInSourcePack): string | null {
  try {
    const url = new URL(value);
    const origin = new URL(pack.origin);
    if (url.hostname !== origin.hostname || (url.protocol !== "https:" && url.protocol !== "http:")) {
      return null;
    }
    url.protocol = "https:";
    url.port = "";
    return url.href;
  } catch {
    return null;
  }
}

function safeAllowedUrl(value: string, pack: BuiltInSourcePack): URL | null {
  try {
    return requireAllowedUrl(value, pack);
  } catch {
    return null;
  }
}

function requireAllowedUrl(value: string, pack: BuiltInSourcePack): URL {
  const url = new URL(value);
  const origin = new URL(pack.origin);
  if (url.protocol !== "https:" || url.hostname !== origin.hostname || url.port) {
    throw new Error("资源地址不在受信来源范围内。");
  }
  return url;
}

function normalizeDate(value: string | null): string | null {
  if (!value) return null;
  const normalized = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?$/.test(value)
    ? `${value}Z`
    : value;
  const date = new Date(normalized);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function extractInfoHash(value: string): string | null {
  return /(?:\/|\b)([a-f0-9]{40})(?:\.|\/|\b)/i.exec(value)?.[1] ?? null;
}

function isValidMagnet(value: string): boolean {
  try {
    const url = new URL(value);
    const topic = url.searchParams.get("xt") ?? "";
    return url.protocol === "magnet:" && /^urn:btih:(?:[a-z2-7]{32}|[a-f0-9]{40})$/i.test(topic);
  } catch {
    return false;
  }
}

function sanitizeFileName(value: string): string {
  const safe = [...value]
    .map((character) =>
      character.charCodeAt(0) < 32 || '<>:"/\\|?*'.includes(character) ? " " : character
    )
    .join("")
    .replace(/\s+/g, " ")
    .trim();
  return (safe || "melonbang-resource").slice(0, 160);
}

class HttpSourceError extends Error {
  constructor(readonly status: number) {
    super(`HTTP ${status}`);
  }
}

function toProviderError(providerName: string, error: unknown): string {
  if (error instanceof HttpSourceError) {
    return `${providerName}暂时不可用（HTTP ${error.status}）。`;
  }
  if (error instanceof Error && error.name === "TimeoutError") {
    return `${providerName}请求超时。`;
  }
  return `${providerName}返回的数据无法使用。`;
}
