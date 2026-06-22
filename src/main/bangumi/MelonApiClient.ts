import type {
  BroadcastDay,
  BroadcastItem,
  RelatedSubject,
  SeasonInfo,
  SubjectCharacterCredit,
  SubjectCollectionStats,
  SubjectComment,
  SubjectInfoBoxItem,
  SubjectPersonCredit,
  SubjectSchedule,
  SubjectStaffCredit,
  SubjectTag,
  SubjectTopic
} from "../../shared/contracts/bangumi";
import type { RemoteBangumiEpisode, RemoteBangumiSubject } from "./BangumiClient";

const MELON_API_BASE_URL = "https://melonapi.konataizumi.com";

export type RemoteMelonSubjectDetail = RemoteBangumiSubject & {
  season?: SeasonInfo;
  episodes: RemoteBangumiEpisode[];
  characters?: SubjectCharacterCredit[];
  staff?: SubjectStaffCredit[];
  relatedSubjects?: RelatedSubject[];
  comments?: SubjectComment[];
  topics?: SubjectTopic[];
  schedule?: SubjectSchedule;
  sourceNotes?: string[];
};

type ApiListResponse = {
  limit?: number;
  offset?: number;
  hasMore?: boolean;
  data: SubjectListItemResponse[];
};

type ApiSubjectResponse = {
  data: SubjectDetailResponse;
};

type ApiSubjectCommentsResponse = {
  data?: SubjectComment[];
};

type ApiSubjectTopicsResponse = {
  data?: SubjectTopic[];
};

type ApiTodayScheduleResponse = {
  date: string;
  items: ScheduleOccurrenceResponse[];
};

type ApiScheduleResponse = {
  centerDate: string;
  byDate: Record<string, ScheduleOccurrenceResponse[]>;
};

type SubjectListItemResponse = {
  subjectId: number;
  name: string;
  nameCn?: string;
  displayName?: string;
  coverUrl?: string;
  summary?: string;
  shortSummary?: string;
  airDate?: string;
  season?: SeasonInfoResponse;
  platform?: string;
  episodeTotal?: number;
  score?: number;
  rank?: number;
  nsfw?: boolean;
  tags?: SubjectTag[];
  metaTags?: string[];
  url?: string;
};

type SubjectDetailResponse = SubjectListItemResponse & {
  ratingCount?: number;
  rating?: {
    score?: number;
    rank?: number;
    total?: number;
  };
  collectionStats?: SubjectCollectionStats;
  infoBox?: SubjectInfoBoxItem[];
  episodes?: EpisodeResponse[];
  characters?: CharacterCreditResponse[];
  staff?: StaffCreditResponse[];
  relatedSubjects?: RelatedSubject[];
  comments?: SubjectComment[];
  topics?: SubjectTopic[];
  schedule?: SubjectSchedule;
  source?: {
    notes?: string[];
  };
};

type SeasonInfoResponse = {
  year: number;
  quarter: number;
  code: string;
  label: string;
  name: SeasonInfo["name"];
};

type EpisodeResponse = {
  episodeId: number;
  subjectId?: number;
  type?: string;
  sort: number;
  ep?: number;
  name: string;
  nameCn?: string;
  displayName?: string;
};

type CharacterCreditResponse = Omit<SubjectCharacterCredit, "actors"> & {
  actors?: PersonCreditResponse[];
};

type StaffCreditResponse = PersonCreditResponse & {
  role?: string;
};

type PersonCreditResponse = SubjectPersonCredit;

type ScheduleOccurrenceResponse = {
  airingAt: string;
  airingAtShanghai: string;
  weekday: string;
  subjectId?: number;
  name: string;
  nameCn?: string;
  displayName?: string;
  type?: string;
  coverUrl?: string;
  episodeTotal?: number;
  tags?: SubjectTag[];
  metaTags?: string[];
  nsfw?: boolean;
  nsfwStatus?: "safe" | "nsfw" | "unknown";
  hasSubjectId?: boolean;
  detailAvailable?: boolean;
  needsFallback?: {
    cover: boolean;
    episodeTotal: boolean;
    nsfw: boolean;
  };
  url?: string;
};

export class MelonApiClient {
  async searchSubjects(keyword: string): Promise<RemoteBangumiSubject[]> {
    const params = new URLSearchParams({
      q: keyword,
      limit: "20",
      offset: "0"
    });
    const response = await this.fetchJson<ApiListResponse>(
      `/v1/subjects/search?${params.toString()}`
    );
    return response.data.map(mapListSubject);
  }

  async getTrendingCurrent(): Promise<BroadcastItem[]> {
    const subjects = await this.fetchSubjectListPages("/v1/trending/current");
    return subjects.map(mapBroadcastSubject);
  }

  async getTodaySchedule(): Promise<BroadcastDay> {
    const response = await this.fetchJson<ApiTodayScheduleResponse>("/v1/schedule/today");
    return {
      weekday: weekdayFromDate(response.date),
      items: await this.enrichScheduleItems(response.items.map(mapScheduleOccurrence))
    };
  }

  async getScheduleWeek(): Promise<BroadcastDay[]> {
    const response = await this.fetchJson<ApiScheduleResponse>("/v1/schedule/latest?days=7");
    const weekDates = weekDateKeys(response.centerDate);
    const byDate = new Map(
      await Promise.all(
        weekDates.map(
          async (date) =>
            [
              date,
              await this.enrichScheduleItems(
                (response.byDate[date] ?? []).map(mapScheduleOccurrence)
              )
            ] as const
        )
      )
    );

    return weekDates.map((date) => ({
      weekday: weekdayFromDate(date),
      items: byDate.get(date) ?? []
    }));
  }

  async getSubject(subjectId: number): Promise<RemoteMelonSubjectDetail> {
    const [response, comments, topics] = await Promise.all([
      this.fetchJson<ApiSubjectResponse>(`/v1/subjects/${subjectId}`),
      this.fetchOptionalList<SubjectComment, ApiSubjectCommentsResponse>(
        `/v1/subjects/${subjectId}/comments`
      ),
      this.fetchOptionalList<SubjectTopic, ApiSubjectTopicsResponse>(
        `/v1/subjects/${subjectId}/topics`
      )
    ]);
    const subject = response.data;

    return {
      ...mapListSubject(subject),
      ratingCount: positiveNumber(subject.ratingCount ?? subject.rating?.total),
      score: positiveNumber(subject.rating?.score ?? subject.score),
      rank: positiveNumber(subject.rating?.rank ?? subject.rank),
      collectionStats: subject.collectionStats,
      infoBox: subject.infoBox?.filter((item) => item.key && item.value),
      season: normalizeSeason(subject.season),
      episodes: (subject.episodes ?? [])
        .filter((episode) => episode.episodeId > 0 && (!episode.type || episode.type === "main"))
        .map((episode) => ({
          id: episode.episodeId,
          subjectId: episode.subjectId ?? subject.subjectId,
          sort:
            Number.isFinite(episode.ep) && episode.ep && episode.ep > 0 ? episode.ep : episode.sort,
          ep: episode.ep,
          name: episode.name,
          nameCn: episode.nameCn || episode.displayName || undefined
        })),
      characters: subject.characters?.map((character) => ({
        ...character,
        actors: character.actors ?? []
      })),
      staff: subject.staff,
      relatedSubjects: subject.relatedSubjects,
      comments: comments ?? subject.comments,
      topics: topics ?? subject.topics,
      schedule: subject.schedule,
      sourceNotes: subject.source?.notes
    };
  }

  private async fetchJson<T>(path: string): Promise<T> {
    const response = await fetch(`${MELON_API_BASE_URL}${path}`, {
      headers: {
        Accept: "application/json"
      }
    });

    if (!response.ok) {
      throw new Error(`Melon API request failed: ${response.status} ${path}`);
    }

    return (await response.json()) as T;
  }

  private async fetchOptionalList<T, Response extends { data?: T[] }>(
    path: string
  ): Promise<T[] | undefined> {
    try {
      const response = await this.fetchJson<Response>(path);
      return response.data;
    } catch {
      return undefined;
    }
  }

  private async fetchSubjectListPages(path: string): Promise<SubjectListItemResponse[]> {
    const limit = 100;
    let offset = 0;
    const subjects: SubjectListItemResponse[] = [];

    for (;;) {
      const params = new URLSearchParams({ limit: String(limit), offset: String(offset) });
      const response = await this.fetchJson<ApiListResponse>(`${path}?${params.toString()}`);
      subjects.push(...response.data);

      if (!response.hasMore || response.data.length === 0) {
        return subjects;
      }

      offset =
        response.offset !== undefined ? response.offset + response.data.length : offset + limit;
    }
  }

  private async enrichScheduleItems(items: BroadcastItem[]): Promise<BroadcastItem[]> {
    const ids = Array.from(
      new Set(
        items
          .filter(
            (item): item is BroadcastItem & { subjectId: number } =>
              typeof item.subjectId === "number" && (!item.coverUrl || !item.episodeTotal)
          )
          .map((item) => item.subjectId)
      )
    );

    if (ids.length === 0) {
      return items;
    }

    const briefs = new Map<number, BroadcastItem>();
    await mapWithConcurrency(ids, 6, async (subjectId) => {
      try {
        const response = await this.fetchJson<ApiSubjectResponse>(
          `/v1/subjects/${subjectId}?full=false`
        );
        briefs.set(subjectId, mapBroadcastSubject(response.data));
      } catch {
        // Keep the schedule item unchanged when the Melon API cannot provide brief subject data.
      }
    });

    return items.map((item) => {
      if (typeof item.subjectId !== "number") {
        return item;
      }

      const brief = briefs.get(item.subjectId);
      if (!brief) {
        return item;
      }

      return {
        ...item,
        nameCn: item.nameCn || brief.nameCn,
        displayName: item.displayName || brief.displayName,
        coverUrl: item.coverUrl || brief.coverUrl,
        summary: item.summary || brief.summary,
        airDate: item.airDate || brief.airDate,
        season: item.season || brief.season,
        platform: item.platform || brief.platform,
        episodeTotal: item.episodeTotal ?? brief.episodeTotal,
        score: item.score ?? brief.score,
        rank: item.rank ?? brief.rank,
        tags: item.tags?.length ? item.tags : brief.tags,
        metaTags: item.metaTags?.length ? item.metaTags : brief.metaTags,
        nsfw: item.nsfw ?? brief.nsfw,
        url: item.url || brief.url
      };
    });
  }
}

async function mapWithConcurrency<T>(
  items: T[],
  concurrency: number,
  task: (item: T) => Promise<void>
): Promise<void> {
  let next = 0;
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (next < items.length) {
      const item = items[next++];
      await task(item);
    }
  });
  await Promise.all(workers);
}

function mapListSubject(subject: SubjectListItemResponse): RemoteBangumiSubject {
  return {
    id: subject.subjectId,
    name: subject.name,
    nameCn: subject.nameCn || subject.displayName || undefined,
    summary: subject.summary || subject.shortSummary || undefined,
    date: subject.airDate || undefined,
    platform: subject.platform || undefined,
    totalEpisodes: positiveNumber(subject.episodeTotal),
    rank: positiveNumber(subject.rank),
    score: positiveNumber(subject.score),
    metaTags: subject.metaTags?.filter(Boolean),
    tags: subject.tags?.filter((tag) => tag.name),
    coverUrl: subject.coverUrl || undefined
  };
}

function mapBroadcastSubject(subject: SubjectListItemResponse): BroadcastItem {
  return {
    subjectId: subject.subjectId,
    name: subject.name,
    nameCn: subject.nameCn || undefined,
    displayName: subject.displayName,
    coverUrl: subject.coverUrl,
    summary: subject.summary || subject.shortSummary,
    airDate: subject.airDate,
    season: normalizeSeason(subject.season),
    platform: subject.platform,
    episodeTotal: positiveNumber(subject.episodeTotal),
    score: positiveNumber(subject.score),
    rank: positiveNumber(subject.rank),
    tags: subject.tags?.filter((tag) => tag.name),
    metaTags: subject.metaTags?.filter(Boolean),
    nsfw: subject.nsfw,
    url: subject.url
  };
}

function mapScheduleOccurrence(item: ScheduleOccurrenceResponse): BroadcastItem {
  return {
    subjectId: item.subjectId,
    name: item.name,
    nameCn: item.nameCn,
    displayName: item.displayName,
    coverUrl: item.coverUrl,
    airingAt: item.airingAt,
    airingAtShanghai: item.airingAtShanghai,
    weekday: item.weekday,
    episodeTotal: positiveNumber(item.episodeTotal),
    tags: item.tags?.filter((tag) => tag.name),
    metaTags: item.metaTags?.filter(Boolean),
    nsfw: item.nsfw,
    nsfwStatus: item.nsfwStatus,
    hasSubjectId: item.hasSubjectId,
    detailAvailable: item.detailAvailable,
    needsFallback: item.needsFallback,
    url: item.url
  };
}

function normalizeSeason(season: SeasonInfoResponse | undefined): SeasonInfo | undefined {
  if (!season || ![1, 2, 3, 4].includes(season.quarter)) {
    return undefined;
  }

  return {
    year: season.year,
    quarter: season.quarter as 1 | 2 | 3 | 4,
    code: season.code,
    label: season.label,
    name: season.name
  };
}

function weekdayFromDate(date: string): BroadcastDay["weekday"] {
  const parsed = parseDateKey(date);
  const day = parsed.getUTCDay();
  const id = day === 0 ? 7 : day;
  const labels = [
    ["MON", "周一", "月曜日"],
    ["TUE", "周二", "火曜日"],
    ["WED", "周三", "水曜日"],
    ["THU", "周四", "木曜日"],
    ["FRI", "周五", "金曜日"],
    ["SAT", "周六", "土曜日"],
    ["SUN", "周日", "日曜日"]
  ] as const;
  const [en, cn, ja] = labels[id - 1];

  return { id, cn, en, ja };
}

function weekDateKeys(centerDate: string): string[] {
  const center = parseDateKey(centerDate);
  const day = center.getUTCDay();
  const weekdayId = day === 0 ? 7 : day;
  const monday = addDays(center, 1 - weekdayId);

  return Array.from({ length: 7 }, (_, index) => formatDateKey(addDays(monday, index)));
}

function parseDateKey(date: string): Date {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function formatDateKey(date: Date): string {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function positiveNumber(value: number | undefined): number | undefined {
  return typeof value === "number" && value > 0 ? value : undefined;
}
