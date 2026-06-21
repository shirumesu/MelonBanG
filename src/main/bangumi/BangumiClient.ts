import type { CollectionStatus, EpisodeStatus } from "../../shared/contracts/bangumi";
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
  totalEpisodes?: number;
  eps?: number;
  rank?: number;
  score?: number;
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

export type RemoteUserEpisodeCollection = {
  episode: RemoteBangumiEpisode;
  status: EpisodeStatus;
  updatedAt?: string;
};

type SearchSubjectsResponse = {
  data: Array<{
    id: number;
    name: string;
    name_cn: string;
    summary: string;
    eps: number;
    total_episodes: number;
    date: string;
    images: {
      small?: string;
      medium?: string;
      large?: string;
      common?: string;
    };
    rating?: {
      rank?: number;
      score?: number;
    };
  }>;
};

type SubjectResponse = {
  id: number;
  name: string;
  name_cn: string;
  summary: string;
  date: string;
  eps: number;
  total_episodes: number;
  images: {
    small?: string;
    medium?: string;
    large?: string;
    common?: string;
  };
  rating?: {
    rank?: number;
    score?: number;
  };
};

type EpisodesResponse = {
  data: Array<{
    id: number;
    subject_id: number;
    sort: number;
    ep?: number;
    name: string;
    name_cn: string;
  }>;
};

type UserCollectionsResponse = {
  data: Array<{
    subject_id: number;
    type: number;
    rate: number;
    ep_status: number;
    updated_at: string;
    subject: {
      id: number;
      name: string;
      name_cn: string;
      summary: string;
      date: string;
      eps: number;
      images: {
        small?: string;
        medium?: string;
        large?: string;
        common?: string;
      };
      rating?: {
        rank?: number;
        score?: number;
      };
    };
  }>;
};

type UserEpisodeCollectionsResponse = {
  data: Array<{
    type: number;
    updated_at: number;
    episode: {
      id: number;
      subject_id: number;
      sort: number;
      ep?: number;
      name: string;
      name_cn: string;
    };
  }>;
};

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
      summary: subject.summary || undefined,
      date: subject.date || undefined,
      totalEpisodes: subject.total_episodes || subject.eps || undefined,
      eps: subject.eps || undefined,
      rank: subject.rating?.rank,
      score: subject.rating?.score,
      coverUrl:
        subject.images.common ??
        subject.images.medium ??
        subject.images.large ??
        subject.images.small
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
      totalEpisodes: subject.total_episodes || subject.eps || undefined,
      eps: subject.eps || undefined,
      rank: subject.rating?.rank,
      score: subject.rating?.score,
      coverUrl:
        subject.images.common ??
        subject.images.medium ??
        subject.images.large ??
        subject.images.small
    };
  }

  async getEpisodes(subjectId: number): Promise<RemoteBangumiEpisode[]> {
    const response = await this.fetchJson<EpisodesResponse>(
      `/v0/episodes?subject_id=${subjectId}&limit=200&offset=0`
    );
    return response.data
      .filter((episode) => episode.id > 0)
      .map((episode) => ({
        id: episode.id,
        subjectId: episode.subject_id,
        sort:
          Number.isFinite(episode.ep) && episode.ep && episode.ep > 0 ? episode.ep : episode.sort,
        ep: episode.ep,
        name: episode.name,
        nameCn: episode.name_cn || undefined
      }));
  }

  async getUserCollections(username: string): Promise<RemoteUserSubjectCollection[]> {
    const response = await this.fetchJson<UserCollectionsResponse>(
      `/v0/users/${encodeURIComponent(username)}/collections?subject_type=2&limit=200&offset=0`
    );

    return response.data.map((collection) => ({
      subjectId: collection.subject_id,
      status: mapSubjectCollectionType(collection.type),
      score: collection.rate > 0 ? collection.rate : undefined,
      epStatus: collection.ep_status,
      updatedAt: collection.updated_at,
      subject: {
        id: collection.subject.id,
        name: collection.subject.name,
        nameCn: collection.subject.name_cn || undefined,
        summary: collection.subject.summary || undefined,
        date: collection.subject.date || undefined,
        totalEpisodes: collection.subject.eps || undefined,
        eps: collection.subject.eps || undefined,
        rank: collection.subject.rating?.rank,
        score: collection.subject.rating?.score,
        coverUrl:
          collection.subject.images.common ??
          collection.subject.images.medium ??
          collection.subject.images.large ??
          collection.subject.images.small
      }
    }));
  }

  async getUserSubjectEpisodeCollections(
    subjectId: number
  ): Promise<RemoteUserEpisodeCollection[]> {
    const response = await this.fetchJson<UserEpisodeCollectionsResponse>(
      `/v0/users/-/collections/${subjectId}/episodes?limit=1000&offset=0`
    );

    return response.data.map((item) => ({
      episode: {
        id: item.episode.id,
        subjectId: item.episode.subject_id,
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

  private headers(headers?: HeadersInit): Record<string, string> {
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

function normalizeHeaders(headers?: HeadersInit): Record<string, string> {
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
