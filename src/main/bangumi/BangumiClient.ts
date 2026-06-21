import type {
  BroadcastDay,
  CollectionStatus,
  EpisodeStatus,
  SubjectCollectionStats,
  SubjectInfoBoxItem,
  SubjectTag
} from "../../shared/contracts/bangumi";
import type { BangumiOAuthConfig } from "../config/bangumi";

export type RemoteBangumiUser = {
  id: number;
  username: string;
  nickname: string;
  avatarUrl?: string;
};

export type RemoteBangumiSubject = {
  id: number;
  name: string;
  nameCn?: string;
  summary?: string;
  date?: string;
  platform?: string;
  totalEpisodes?: number;
  eps?: number;
  rank?: number;
  score?: number;
  ratingCount?: number;
  collectionStats?: SubjectCollectionStats;
  metaTags?: string[];
  tags?: SubjectTag[];
  infoBox?: SubjectInfoBoxItem[];
  coverUrl?: string;
};

export type RemoteBangumiEpisode = {
  id: number;
  subjectId: number;
  sort: number;
  ep?: number;
  name: string;
  nameCn?: string;
};

export type RemoteUserSubjectCollection = {
  subjectId: number;
  status: CollectionStatus;
  score?: number;
  epStatus?: number;
  updatedAt: string;
  subject: RemoteBangumiSubject;
};

export type RemoteUserSubjectCollectionPage = {
  total: number;
  limit: number;
  offset: number;
  items: RemoteUserSubjectCollection[];
};

export type RemoteUserEpisodeCollection = {
  episode: RemoteBangumiEpisode;
  status: EpisodeStatus;
  updatedAt?: string;
};

type SearchSubjectsResponse = {
  total?: number;
  limit?: number;
  offset?: number;
  data: Array<{
    id: number;
    name: string;
    name_cn: string;
    summary?: string;
    short_summary?: string;
    eps?: number;
    total_episodes?: number;
    date?: string;
    images?: {
      small?: string;
      medium?: string;
      large?: string;
      common?: string;
      grid?: string;
    } | null;
    rating?: {
      rank?: number;
      score?: number;
    };
    rank?: number;
    score?: number;
  }>;
};

type SubjectResponse = {
  id: number;
  type?: number;
  name: string;
  name_cn: string;
  summary?: string;
  date?: string;
  platform?: string;
  meta_tags?: string[];
  eps?: number;
  total_episodes?: number;
  images?: {
    small?: string;
    medium?: string;
    large?: string;
    common?: string;
    grid?: string;
  } | null;
  rating?: {
    rank?: number;
    total?: number;
    score?: number;
    count?: Record<string, number>;
  };
  collection?: {
    wish?: number;
    collect?: number;
    doing?: number;
    on_hold?: number;
    dropped?: number;
  };
  tags?: Array<{
    name: string;
    count?: number;
  }>;
  infobox?: InfoboxResponseItem[];
};

type InfoboxResponseItem = {
  key: string;
  value:
    | string
    | Array<
        | {
            k?: string;
            v: string;
          }
        | {
            v: string;
          }
      >;
};

type EpisodesResponse = {
  total?: number;
  limit?: number;
  offset?: number;
  data: Array<{
    id: number;
    subject_id?: number;
    type: number;
    sort: number;
    ep?: number;
    name: string;
    name_cn: string;
  }>;
};

type UserCollectionsResponse = {
  total: number;
  limit: number;
  offset: number;
  data: Array<{
    subject_id: number;
    subject_type: number;
    type: number;
    rate: number;
    ep_status: number;
    updated_at: string;
    subject?: {
      id: number;
      type: number;
      name: string;
      name_cn: string;
      short_summary?: string;
      summary?: string;
      date?: string;
      eps?: number;
      total_episodes?: number;
      images?: {
        small?: string;
        medium?: string;
        large?: string;
        common?: string;
        grid?: string;
      } | null;
      rating?: {
        rank?: number;
        score?: number;
      };
      rank?: number;
      score?: number;
    };
  }>;
};

type UserEpisodeCollectionsResponse = {
  total?: number;
  limit?: number;
  offset?: number;
  data: Array<{
    type: number;
    updated_at: number;
    episode: {
      id: number;
      subject_id?: number;
      sort: number;
      ep?: number;
      name: string;
      name_cn: string;
    };
  }>;
};

type CalendarResponse = Array<{
  weekday: {
    en: string;
    cn: string;
    ja?: string;
    id: number;
  };
  items: SubjectResponse[];
}>;

const USER_COLLECTION_PAGE_SIZE = 50;
const EPISODE_PAGE_SIZE = 200;
const USER_EPISODE_COLLECTION_PAGE_SIZE = 1000;

export class BangumiClient {
  constructor(
    private readonly config: BangumiOAuthConfig,
    private readonly accessToken: string
  ) {}

  async getMyself(): Promise<RemoteBangumiUser> {
    const response = await this.fetchJson<{
      id: number;
      username: string;
      nickname: string;
      avatar: { medium: string };
    }>("/v0/me");

    return {
      id: response.id,
      username: response.username,
      nickname: response.nickname,
      avatarUrl: response.avatar.medium
    };
  }

  async searchSubjects(keyword: string): Promise<RemoteBangumiSubject[]> {
    const response = await this.fetchJson<SearchSubjectsResponse>(
      "/v0/search/subjects?limit=20&offset=0",
      {
        method: "POST",
        body: JSON.stringify({
          keyword,
          sort: "match",
          filter: {
            type: [2]
          }
        })
      }
    );

    return response.data.map((subject) => ({
      id: subject.id,
      name: subject.name,
      nameCn: subject.name_cn || undefined,
      summary: subject.summary || subject.short_summary || undefined,
      date: subject.date || undefined,
      totalEpisodes: subject.total_episodes || subject.eps || undefined,
      eps: subject.eps || undefined,
      rank: positiveNumber(subject.rating?.rank ?? subject.rank),
      score: positiveNumber(subject.rating?.score ?? subject.score),
      coverUrl: pickImage(subject.images)
    }));
  }

  async getSubject(subjectId: number): Promise<RemoteBangumiSubject> {
    const subject = await this.fetchJson<SubjectResponse>(`/v0/subjects/${subjectId}`);
    return {
      id: subject.id,
      name: subject.name,
      nameCn: subject.name_cn || undefined,
      summary: subject.summary || undefined,
      date: subject.date || undefined,
      platform: subject.platform || undefined,
      totalEpisodes: subject.total_episodes || subject.eps || undefined,
      eps: subject.eps || undefined,
      rank: positiveNumber(subject.rating?.rank),
      score: positiveNumber(subject.rating?.score),
      ratingCount: positiveNumber(subject.rating?.total),
      collectionStats: mapSubjectCollectionStats(subject.collection),
      metaTags: subject.meta_tags?.filter(Boolean),
      tags: subject.tags?.map((tag) => ({ name: tag.name, count: tag.count })),
      infoBox: mapInfobox(subject.infobox),
      coverUrl: pickImage(subject.images)
    };
  }

  async getCalendar(): Promise<BroadcastDay[]> {
    const response = await this.fetchJson<CalendarResponse>("/calendar");
    return response.map((day) => ({
      weekday: {
        id: day.weekday.id,
        cn: day.weekday.cn,
        en: day.weekday.en,
        ja: day.weekday.ja
      },
      items: day.items
        .filter((subject) => subject.type === 2 || typeof subject.type === "undefined")
        .map((subject) => ({
          subjectId: subject.id,
          name: subject.name,
          nameCn: subject.name_cn || undefined,
          summary: subject.summary || undefined,
          airDate: subject.date || undefined,
          episodeTotal: subject.total_episodes || subject.eps || undefined,
          rank: positiveNumber(subject.rating?.rank),
          score: positiveNumber(subject.rating?.score),
          coverUrl: pickImage(subject.images)
        }))
    }));
  }

  async getEpisodes(subjectId: number): Promise<RemoteBangumiEpisode[]> {
    const response = await this.fetchJson<EpisodesResponse>(
      `/v0/episodes?subject_id=${subjectId}&type=0&limit=${EPISODE_PAGE_SIZE}&offset=0`
    );
    return response.data
      .filter((episode) => episode.id > 0 && episode.type === 0)
      .map((episode) => ({
        id: episode.id,
        subjectId: episode.subject_id ?? subjectId,
        sort:
          Number.isFinite(episode.ep) && episode.ep && episode.ep > 0 ? episode.ep : episode.sort,
        ep: episode.ep,
        name: episode.name,
        nameCn: episode.name_cn || undefined
      }));
  }

  async getUserCollections(username: string, offset = 0): Promise<RemoteUserSubjectCollectionPage> {
    const response = await this.fetchJson<UserCollectionsResponse>(
      `/v0/users/${encodeURIComponent(username)}/collections?subject_type=2&limit=${USER_COLLECTION_PAGE_SIZE}&offset=${offset}`
    );

    return {
      total: response.total,
      limit: response.limit,
      offset: response.offset,
      items: response.data.flatMap((collection) => {
        const subject = collection.subject;
        if (collection.subject_type !== 2 || !subject) {
          return [];
        }

        return [
          {
            subjectId: collection.subject_id,
            status: mapSubjectCollectionType(collection.type),
            score: collection.rate > 0 ? collection.rate : undefined,
            epStatus: collection.ep_status,
            updatedAt: collection.updated_at,
            subject: {
              id: subject.id,
              name: subject.name,
              nameCn: subject.name_cn || undefined,
              summary: subject.summary || subject.short_summary || undefined,
              date: subject.date || undefined,
              totalEpisodes: subject.total_episodes || subject.eps || undefined,
              eps: subject.eps || undefined,
              rank: positiveNumber(subject.rating?.rank ?? subject.rank),
              score: positiveNumber(subject.rating?.score ?? subject.score),
              coverUrl: pickImage(subject.images)
            }
          }
        ];
      })
    };
  }

  async getAllUserCollections(username: string): Promise<RemoteUserSubjectCollection[]> {
    const items: RemoteUserSubjectCollection[] = [];
    let offset = 0;
    let total = Number.POSITIVE_INFINITY;

    while (offset < total) {
      const page = await this.getUserCollections(username, offset);
      items.push(...page.items);
      total = page.total;

      const nextOffset = page.offset + (page.limit || USER_COLLECTION_PAGE_SIZE);
      if (nextOffset <= offset || page.items.length === 0) {
        break;
      }

      offset = nextOffset;
    }

    return items;
  }

  async getUserSubjectEpisodeCollections(
    subjectId: number
  ): Promise<RemoteUserEpisodeCollection[]> {
    const response = await this.fetchJson<UserEpisodeCollectionsResponse>(
      `/v0/users/-/collections/${subjectId}/episodes?episode_type=0&limit=${USER_EPISODE_COLLECTION_PAGE_SIZE}&offset=0`
    );

    return response.data.map((item) => ({
      episode: {
        id: item.episode.id,
        subjectId: item.episode.subject_id ?? subjectId,
        sort:
          Number.isFinite(item.episode.ep) && item.episode.ep && item.episode.ep > 0
            ? item.episode.ep
            : item.episode.sort,
        ep: item.episode.ep,
        name: item.episode.name,
        nameCn: item.episode.name_cn || undefined
      },
      status: mapEpisodeCollectionType(item.type),
      updatedAt: item.updated_at > 0 ? new Date(item.updated_at * 1000).toISOString() : undefined
    }));
  }

  async updateSubjectCollection(
    subjectId: number,
    input: { status?: CollectionStatus; score?: number }
  ): Promise<void> {
    const body: Record<string, unknown> = {};
    if (input.status) {
      body.type = subjectCollectionTypeValue(input.status);
    }
    if (typeof input.score === "number") {
      body.rate = input.score;
    }

    await this.fetchVoid(`/v0/users/-/collections/${subjectId}`, {
      method: "POST",
      body: JSON.stringify(body)
    });
  }

  async updateEpisodeCollection(episodeId: number, status: EpisodeStatus): Promise<void> {
    await this.fetchVoid(`/v0/users/-/collections/-/episodes/${episodeId}`, {
      method: "PUT",
      body: JSON.stringify({
        type: episodeCollectionTypeValue(status)
      })
    });
  }

  private async fetchJson<T>(path: string, init?: RequestInit): Promise<T> {
    const mergedHeaders = this.headers(init?.headers);
    const response = await fetch(`https://api.bgm.tv${path}`, {
      ...init,
      headers: mergedHeaders
    });

    if (!response.ok) {
      throw new Error(`Bangumi API request failed: ${response.status} ${path}`);
    }

    return (await response.json()) as T;
  }

  private async fetchVoid(path: string, init?: RequestInit): Promise<void> {
    const mergedHeaders = this.headers(init?.headers);
    const response = await fetch(`https://api.bgm.tv${path}`, {
      ...init,
      headers: mergedHeaders
    });

    if (!response.ok) {
      throw new Error(`Bangumi API request failed: ${response.status} ${path}`);
    }
  }

  private headers(headers?: RequestInit["headers"]): Record<string, string> {
    const overrides = normalizeHeaders(headers);

    return {
      Accept: "application/json",
      "Content-Type": "application/json",
      "User-Agent": this.config.userAgent,
      Authorization: `Bearer ${this.accessToken}`,
      ...overrides
    };
  }
}

function normalizeHeaders(headers?: RequestInit["headers"]): Record<string, string> {
  if (!headers) {
    return {};
  }

  if (headers instanceof Headers) {
    return Object.fromEntries(headers.entries());
  }

  if (Array.isArray(headers)) {
    return Object.fromEntries(headers);
  }

  const normalized: Record<string, string> = {};
  const plainHeaders = headers as Record<string, string>;
  for (const key in plainHeaders) {
    normalized[key] = plainHeaders[key];
  }

  return normalized;
}

function pickImage(
  images?: {
    common?: string;
    medium?: string;
    large?: string;
    small?: string;
    grid?: string;
  } | null
): string | undefined {
  return images?.common ?? images?.medium ?? images?.large ?? images?.small ?? images?.grid;
}

function positiveNumber(value: number | undefined): number | undefined {
  return typeof value === "number" && value > 0 ? value : undefined;
}

function mapSubjectCollectionType(value: number): CollectionStatus {
  switch (value) {
    case 1:
      return "wish";
    case 2:
      return "completed";
    case 3:
      return "watching";
    case 4:
      return "on_hold";
    case 5:
      return "dropped";
    default:
      return "watching";
  }
}

function subjectCollectionTypeValue(value: CollectionStatus): number {
  switch (value) {
    case "wish":
      return 1;
    case "completed":
      return 2;
    case "watching":
      return 3;
    case "on_hold":
      return 4;
    case "dropped":
      return 5;
  }
}

function mapEpisodeCollectionType(value: number): EpisodeStatus {
  switch (value) {
    case 0:
      return "unwatched";
    case 1:
      return "queue";
    case 2:
      return "watched";
    case 3:
      return "dropped";
    default:
      return "unwatched";
  }
}

function mapSubjectCollectionStats(
  collection: SubjectResponse["collection"]
): SubjectCollectionStats | undefined {
  if (!collection) {
    return undefined;
  }

  return {
    wish: collection.wish ?? 0,
    watching: collection.doing ?? 0,
    completed: collection.collect ?? 0,
    on_hold: collection.on_hold ?? 0,
    dropped: collection.dropped ?? 0
  };
}

function mapInfobox(infobox: SubjectResponse["infobox"]): SubjectInfoBoxItem[] | undefined {
  if (!infobox?.length) {
    return undefined;
  }

  return infobox.flatMap((item) => {
    const value = infoboxValueToString(item.value);
    if (!value) {
      return [];
    }

    return [{ key: item.key, value }];
  });
}

function infoboxValueToString(value: InfoboxResponseItem["value"]): string {
  if (typeof value === "string") {
    return value.trim();
  }

  return value
    .map((entry) => ("k" in entry && entry.k ? `${entry.k}: ${entry.v}` : entry.v))
    .filter(Boolean)
    .join(" / ");
}

function episodeCollectionTypeValue(value: EpisodeStatus): number {
  switch (value) {
    case "unwatched":
      return 0;
    case "queue":
      return 1;
    case "watched":
      return 2;
    case "dropped":
      return 3;
  }
}
