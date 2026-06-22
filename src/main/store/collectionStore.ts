import type {
  CollectionFilter,
  CollectionListItem,
  CollectionStatus,
  EpisodeCollectionState,
  EpisodeStatus,
  RelatedSubject,
  SubjectCharacterCredit,
  SubjectCollectionStats,
  SubjectCollectionState,
  SubjectComment,
  SubjectDetail,
  SubjectInfoBoxItem,
  SubjectSchedule,
  SubjectSearchResult,
  SubjectStaffCredit,
  SubjectTopic
} from "../../shared/contracts/bangumi";
import { getAppDatabase } from "./appDatabase";

type SubjectCacheRow = {
  subject_id: number;
  name: string;
  name_cn: string | null;
  cover_url: string | null;
  summary: string | null;
  air_date: string | null;
  platform: string | null;
  episode_total: number | null;
  rank: number | null;
  score: number | null;
  rating_count: number | null;
  collection_stats_json: string | null;
  meta_tags_json: string | null;
  tags_json: string | null;
  infobox_json: string | null;
  characters_json: string | null;
  staff_json: string | null;
  related_subjects_json: string | null;
  comments_json: string | null;
  topics_json: string | null;
  schedule_json: string | null;
  source_notes_json: string | null;
  updated_at: string;
};

type SubjectCollectionRow = {
  subject_id: number;
  status: CollectionStatus;
  score: number | null;
  ep_status: number;
  updated_at: string;
};

type EpisodeCollectionRow = {
  episode_id: number;
  subject_id: number;
  sort: number;
  name: string;
  name_cn: string | null;
  status: EpisodeStatus;
  updated_at: string | null;
};

type SubjectCacheInput = {
  subjectId: number;
  name: string;
  nameCn?: string;
  coverUrl?: string;
  summary?: string;
  airDate?: string;
  platform?: string;
  episodeTotal?: number;
  rank?: number;
  score?: number;
  ratingCount?: number;
  collectionStats?: SubjectCollectionStats;
  metaTags?: string[];
  tags?: Array<{ name: string; count?: number }>;
  infoBox?: SubjectInfoBoxItem[];
  characters?: SubjectCharacterCredit[];
  staff?: SubjectStaffCredit[];
  relatedSubjects?: RelatedSubject[];
  comments?: SubjectComment[];
  topics?: SubjectTopic[];
  schedule?: SubjectSchedule;
  sourceNotes?: string[];
};

type SubjectCollectionInput = SubjectCollectionState & { epStatus?: number };

type SubjectCollectionSnapshot = {
  subject: SubjectCacheInput;
  collection: SubjectCollectionInput;
};

type CollectionListRow = {
  subject_id: number;
  name: string;
  name_cn: string | null;
  cover_url: string | null;
  summary: string | null;
  episode_total: number | null;
  subject_score: number | null;
  status: CollectionStatus;
  collection_score: number | null;
  ep_status: number;
  collection_updated_at: string;
};

export class CollectionStore {
  private readonly database = getAppDatabase();

  listCollection(filter?: CollectionFilter): CollectionListItem[] {
    const subjectRows = this.database
      .prepare(
        `
      SELECT
        sc.subject_id,
        sc.name,
        sc.name_cn,
        sc.cover_url,
        sc.summary,
        sc.episode_total,
        sc.score AS subject_score,
        c.status,
        c.score AS collection_score,
        c.ep_status,
        c.updated_at AS collection_updated_at
      FROM subject_cache sc
      INNER JOIN subject_collections c ON c.subject_id = sc.subject_id
      ORDER BY c.updated_at DESC
    `
      )
      .all() as CollectionListRow[];

    const loweredSearch = filter?.search?.trim().toLowerCase();

    return subjectRows
      .map((row) => this.toCollectionListItem(row))
      .filter((item) => {
        if (filter?.status && item.collection.status !== filter.status) {
          return false;
        }

        if (!loweredSearch) {
          return true;
        }

        return [
          item.name,
          item.nameCn,
          item.summary,
          item.nextEpisode?.name,
          item.nextEpisode?.nameCn
        ]
          .filter(Boolean)
          .some((value) => value?.toLowerCase().includes(loweredSearch));
      });
  }

  getSubject(subjectId: number): SubjectDetail | null {
    const subject = this.database
      .prepare(
        `
      SELECT
        subject_id,
        name,
        name_cn,
        cover_url,
        summary,
        air_date,
        platform,
        episode_total,
        rank,
        score,
        rating_count,
        collection_stats_json,
        meta_tags_json,
        tags_json,
        infobox_json,
        characters_json,
        staff_json,
        related_subjects_json,
        comments_json,
        topics_json,
        schedule_json,
        source_notes_json,
        updated_at
      FROM subject_cache
      WHERE subject_id = ?
    `
      )
      .get(subjectId) as SubjectCacheRow | undefined;

    if (!subject) {
      return null;
    }

    const collection = this.database
      .prepare(
        `
      SELECT subject_id, status, score, ep_status, updated_at
      FROM subject_collections
      WHERE subject_id = ?
    `
      )
      .get(subjectId) as SubjectCollectionRow | undefined;

    const episodes = this.database
      .prepare(
        `
      SELECT episode_id, subject_id, sort, name, name_cn, status, updated_at
      FROM episode_collections
      WHERE subject_id = ?
      ORDER BY sort ASC
    `
      )
      .all(subjectId) as EpisodeCollectionRow[];

    return {
      subjectId: subject.subject_id,
      name: subject.name,
      nameCn: subject.name_cn ?? undefined,
      coverUrl: subject.cover_url ?? undefined,
      summary: subject.summary ?? undefined,
      airDate: subject.air_date ?? undefined,
      platform: subject.platform ?? undefined,
      episodeTotal: subject.episode_total ?? undefined,
      rank: subject.rank ?? undefined,
      score: subject.score ?? undefined,
      ratingCount: subject.rating_count ?? undefined,
      collectionStats: parseJson<SubjectCollectionStats>(subject.collection_stats_json),
      metaTags: parseJson<string[]>(subject.meta_tags_json),
      tags: parseJson<Array<{ name: string; count?: number }>>(subject.tags_json),
      infoBox: parseJson<SubjectInfoBoxItem[]>(subject.infobox_json),
      characters: parseJson<SubjectCharacterCredit[]>(subject.characters_json),
      staff: parseJson<SubjectStaffCredit[]>(subject.staff_json),
      relatedSubjects: parseJson<RelatedSubject[]>(subject.related_subjects_json),
      comments: parseJson<SubjectComment[]>(subject.comments_json),
      topics: parseJson<SubjectTopic[]>(subject.topics_json),
      schedule: parseJson<SubjectSchedule>(subject.schedule_json),
      sourceNotes: parseJson<string[]>(subject.source_notes_json),
      collection: collection ? this.toSubjectCollectionState(collection) : null,
      episodes: episodes.map((episode) => this.toEpisodeCollectionState(episode))
    };
  }

  getEpisode(episodeId: number): EpisodeCollectionState | null {
    const row = this.database
      .prepare(
        `
      SELECT episode_id, subject_id, sort, name, name_cn, status, updated_at
      FROM episode_collections
      WHERE episode_id = ?
    `
      )
      .get(episodeId) as EpisodeCollectionRow | undefined;

    return row ? this.toEpisodeCollectionState(row) : null;
  }

  searchSubjects(keyword: string): SubjectSearchResult[] {
    const like = `%${keyword.trim().toLowerCase()}%`;
    const rows = this.database
      .prepare(
        `
      SELECT subject_id, name, name_cn, cover_url, summary, air_date, platform, episode_total, rank, score, rating_count, collection_stats_json, meta_tags_json, tags_json, infobox_json, updated_at
      FROM subject_cache
      WHERE lower(name) LIKE ? OR lower(COALESCE(name_cn, '')) LIKE ? OR lower(COALESCE(summary, '')) LIKE ?
      ORDER BY updated_at DESC
      LIMIT 30
    `
      )
      .all(like, like, like) as SubjectCacheRow[];

    return rows.map((row) => ({
      subjectId: row.subject_id,
      name: row.name,
      nameCn: row.name_cn ?? undefined,
      coverUrl: row.cover_url ?? undefined,
      summary: row.summary ?? undefined,
      episodeTotal: row.episode_total ?? undefined
    }));
  }

  upsertSubjectCache(input: SubjectCacheInput): void {
    this.database
      .prepare(
        `
      INSERT INTO subject_cache (
        subject_id,
        name,
        name_cn,
        cover_url,
        summary,
        air_date,
        platform,
        episode_total,
        rank,
        score,
        rating_count,
        collection_stats_json,
        meta_tags_json,
        tags_json,
        infobox_json,
        characters_json,
        staff_json,
        related_subjects_json,
        comments_json,
        topics_json,
        schedule_json,
        source_notes_json,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(subject_id) DO UPDATE SET
        name = excluded.name,
        name_cn = excluded.name_cn,
        cover_url = excluded.cover_url,
        summary = excluded.summary,
        air_date = excluded.air_date,
        platform = COALESCE(excluded.platform, subject_cache.platform),
        episode_total = excluded.episode_total,
        rank = excluded.rank,
        score = excluded.score,
        rating_count = COALESCE(excluded.rating_count, subject_cache.rating_count),
        collection_stats_json = COALESCE(excluded.collection_stats_json, subject_cache.collection_stats_json),
        meta_tags_json = COALESCE(excluded.meta_tags_json, subject_cache.meta_tags_json),
        tags_json = COALESCE(excluded.tags_json, subject_cache.tags_json),
        infobox_json = COALESCE(excluded.infobox_json, subject_cache.infobox_json),
        characters_json = COALESCE(excluded.characters_json, subject_cache.characters_json),
        staff_json = COALESCE(excluded.staff_json, subject_cache.staff_json),
        related_subjects_json = COALESCE(excluded.related_subjects_json, subject_cache.related_subjects_json),
        comments_json = COALESCE(excluded.comments_json, subject_cache.comments_json),
        topics_json = COALESCE(excluded.topics_json, subject_cache.topics_json),
        schedule_json = COALESCE(excluded.schedule_json, subject_cache.schedule_json),
        source_notes_json = COALESCE(excluded.source_notes_json, subject_cache.source_notes_json),
        updated_at = excluded.updated_at
    `
      )
      .run(
        input.subjectId,
        input.name,
        input.nameCn ?? null,
        input.coverUrl ?? null,
        input.summary ?? null,
        input.airDate ?? null,
        input.platform ?? null,
        input.episodeTotal ?? null,
        input.rank ?? null,
        input.score ?? null,
        input.ratingCount ?? null,
        jsonOrNull(input.collectionStats),
        jsonOrNull(input.metaTags),
        jsonOrNull(input.tags),
        jsonOrNull(input.infoBox),
        jsonOrNull(input.characters),
        jsonOrNull(input.staff),
        jsonOrNull(input.relatedSubjects),
        jsonOrNull(input.comments),
        jsonOrNull(input.topics),
        jsonOrNull(input.schedule),
        jsonOrNull(input.sourceNotes),
        isoNow()
      );
  }

  upsertSubjectCollection(input: SubjectCollectionState): void {
    this.upsertStoredSubjectCollection(input);
  }

  upsertStoredSubjectCollection(input: SubjectCollectionState & { epStatus?: number }): void {
    this.database
      .prepare(
        `
      INSERT INTO subject_collections (subject_id, status, score, ep_status, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(subject_id) DO UPDATE SET
        status = excluded.status,
        score = excluded.score,
        ep_status = excluded.ep_status,
        updated_at = excluded.updated_at
    `
      )
      .run(
        input.subjectId,
        input.status,
        input.score ?? null,
        input.epStatus ?? 0,
        input.updatedAt
      );
  }

  replaceSubjectCollections(input: SubjectCollectionSnapshot[]): void {
    this.database.exec(`
      CREATE TEMP TABLE IF NOT EXISTS temp_subject_collection_refresh (
        subject_id INTEGER PRIMARY KEY
      ) STRICT;
    `);

    this.database.prepare("BEGIN").run();
    try {
      this.database.prepare("DELETE FROM temp_subject_collection_refresh").run();

      for (const entry of input) {
        this.upsertSubjectCache(entry.subject);
        this.upsertStoredSubjectCollection(entry.collection);
        this.database
          .prepare("INSERT OR REPLACE INTO temp_subject_collection_refresh (subject_id) VALUES (?)")
          .run(entry.collection.subjectId);
      }

      this.database
        .prepare(
          `
        DELETE FROM subject_collections
        WHERE subject_id NOT IN (SELECT subject_id FROM temp_subject_collection_refresh)
      `
        )
        .run();

      this.database.prepare("DELETE FROM temp_subject_collection_refresh").run();
      this.database.prepare("COMMIT").run();
    } catch (error) {
      this.database.prepare("ROLLBACK").run();
      throw error;
    }
  }

  updateEpisodeStatus(input: EpisodeCollectionState): void {
    this.database
      .prepare(
        `
      INSERT INTO episode_collections (episode_id, subject_id, sort, name, name_cn, status, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(episode_id) DO UPDATE SET
        subject_id = excluded.subject_id,
        sort = excluded.sort,
        name = excluded.name,
        name_cn = excluded.name_cn,
        status = excluded.status,
        updated_at = excluded.updated_at
    `
      )
      .run(
        input.episodeId,
        input.subjectId,
        input.sort,
        input.name,
        input.nameCn ?? null,
        input.status,
        input.updatedAt ?? null
      );
  }

  seedMockData(): void {
    const hasRows = this.database.prepare("SELECT COUNT(*) as count FROM subject_cache").get() as {
      count: number;
    };
    if (hasRows.count > 0) {
      return;
    }

    const subjects = [
      {
        subjectId: 1,
        name: "夏日终幕的我们",
        nameCn: "夏日终幕的我们",
        episodeTotal: 24,
        summary: "当蝉鸣盖过心跳，三个少女在最后一个夏天许下不会褪色的约定。",
        airDate: "2026-07-03",
        rank: 14,
        score: 8.7
      },
      {
        subjectId: 2,
        name: "缔造神话的少女们",
        nameCn: "缔造神话的少女们",
        episodeTotal: 12,
        summary: "传说的尽头，是被遗忘的名字。少女们以歌声为剑，在崩坏的神域里重写神话。",
        airDate: "2026-07-10",
        rank: 62,
        score: 8.1
      },
      {
        subjectId: 3,
        name: "刀锋上的舞者",
        nameCn: "刀锋上的舞者",
        episodeTotal: 11,
        summary: "每一次出鞘都是一次告别。流浪剑客与失忆少女在樱雨间缓缓前行。",
        airDate: "2026-04-08",
        rank: 7,
        score: 9.1
      },
      {
        subjectId: 4,
        name: "天空彼端的信",
        nameCn: "天空彼端的信",
        episodeTotal: 13,
        summary: "一封寄往未来的信件，牵出空岛与地面之间的双线青春剧。",
        airDate: "2026-04-16",
        rank: 35,
        score: 8.3
      },
      {
        subjectId: 5,
        name: "星之追忆",
        nameCn: "星之追忆",
        episodeTotal: 24,
        summary: "在无重力殖民地中回望失落故乡的太空抒情诗。",
        airDate: "2025-10-02",
        rank: 89,
        score: 7.8
      },
      {
        subjectId: 6,
        name: "创世笔记",
        nameCn: "创世笔记",
        episodeTotal: 12,
        summary: "当记录现实的笔记本开始重写世界，少年必须学会给神话划边界。",
        airDate: "2026-07-01",
        rank: 28,
        score: 8.4
      },
      {
        subjectId: 7,
        name: "千里旅人",
        nameCn: "千里旅人",
        episodeTotal: 13,
        summary: "一列不停站的夜行列车，把陌生人的人生缝成同一趟旅程。",
        airDate: "2026-07-06",
        rank: 41,
        score: 8.0
      },
      {
        subjectId: 8,
        name: "幻夜咖啡馆",
        nameCn: "幻夜咖啡馆",
        episodeTotal: 10,
        summary: "只在深夜营业的咖啡馆，收留那些还没来得及告别的人。",
        airDate: "2025-12-15",
        rank: 19,
        score: 8.8
      },
      {
        subjectId: 9,
        name: "焰之魔导书",
        nameCn: "焰之魔导书",
        episodeTotal: 24,
        summary: "旧帝国遗留的禁书库重新开启，魔法与工业的平衡再度崩塌。",
        airDate: "2026-10-02",
        rank: 77,
        score: 7.9
      },
      {
        subjectId: 10,
        name: "无声的旋律",
        nameCn: "无声的旋律",
        episodeTotal: 11,
        summary: "听障钢琴家与天才作曲家的室内乐故事，靠振动和眼神完成演出。",
        airDate: "2026-10-20",
        rank: 56,
        score: 8.2
      }
    ] as const;

    const collections = [
      { subjectId: 1, status: "watching", score: 8 },
      { subjectId: 2, status: "wish", score: 0 },
      { subjectId: 3, status: "completed", score: 9 },
      { subjectId: 4, status: "on_hold", score: 7 },
      { subjectId: 5, status: "dropped", score: 6 },
      { subjectId: 6, status: "watching", score: 8 },
      { subjectId: 7, status: "watching", score: 8 },
      { subjectId: 8, status: "completed", score: 9 }
    ] as const satisfies Array<{ subjectId: number; status: CollectionStatus; score: number }>;

    const subjectStatement = this.database.prepare(`
      INSERT INTO subject_cache (subject_id, name, name_cn, cover_url, summary, air_date, episode_total, rank, score, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const collectionStatement = this.database.prepare(`
      INSERT INTO subject_collections (subject_id, status, score, ep_status, updated_at)
      VALUES (?, ?, ?, ?, ?)
    `);
    const episodeStatement = this.database.prepare(`
      INSERT INTO episode_collections (episode_id, subject_id, sort, name, name_cn, status, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);

    this.database.prepare("BEGIN").run();
    try {
      for (const subject of subjects) {
        subjectStatement.run(
          subject.subjectId,
          subject.name,
          subject.nameCn,
          null,
          subject.summary,
          subject.airDate,
          subject.episodeTotal,
          subject.rank,
          subject.score,
          isoNow()
        );
      }

      for (const collection of collections) {
        const epStatus =
          collection.status === "watching"
            ? collection.subjectId === 1
              ? 6
              : collection.subjectId === 6
                ? 4
                : 2
            : 0;

        collectionStatement.run(
          collection.subjectId,
          collection.status,
          collection.score,
          epStatus,
          isoNow()
        );
      }

      for (const subject of subjects) {
        const collection = collections.find((entry) => entry.subjectId === subject.subjectId);
        const episodeStatusMap = seedEpisodes(
          subject.subjectId,
          subject.episodeTotal,
          collection?.status
        );
        for (let sort = 1; sort <= subject.episodeTotal; sort += 1) {
          episodeStatement.run(
            subject.subjectId * 100 + sort,
            subject.subjectId,
            sort,
            `Episode ${sort}`,
            `第 ${sort} 话`,
            episodeStatusMap.get(sort) ?? "unwatched",
            isoNow()
          );
        }
      }

      this.database.prepare("COMMIT").run();
    } catch (error) {
      this.database.prepare("ROLLBACK").run();
      throw error;
    }
  }

  private toCollectionListItem(row: CollectionListRow): CollectionListItem {
    const episodes = this.database
      .prepare(
        `
      SELECT episode_id, subject_id, sort, name, name_cn, status, updated_at
      FROM episode_collections
      WHERE subject_id = ?
      ORDER BY sort ASC
    `
      )
      .all(row.subject_id) as EpisodeCollectionRow[];

    const nextEpisode = episodes.find(
      (episode) => episode.status === "queue" || episode.status === "unwatched"
    );

    return {
      subjectId: row.subject_id,
      name: row.name,
      nameCn: row.name_cn ?? undefined,
      coverUrl: row.cover_url ?? undefined,
      episodeTotal: row.episode_total ?? undefined,
      score: row.subject_score ?? undefined,
      watchedEpisodeCount: row.ep_status > 0 ? row.ep_status : undefined,
      summary: row.summary ?? undefined,
      collection: this.toSubjectCollectionState({
        subject_id: row.subject_id,
        status: row.status,
        score: row.collection_score,
        ep_status: row.ep_status,
        updated_at: row.collection_updated_at
      }),
      nextEpisode: nextEpisode ? this.toEpisodeCollectionState(nextEpisode) : undefined,
      pendingMutationKeys: []
    };
  }

  private toSubjectCollectionState(row: SubjectCollectionRow): SubjectCollectionState {
    return {
      subjectId: row.subject_id,
      status: row.status,
      score: row.score ?? undefined,
      updatedAt: row.updated_at
    };
  }

  private toEpisodeCollectionState(row: EpisodeCollectionRow): EpisodeCollectionState {
    return {
      episodeId: row.episode_id,
      subjectId: row.subject_id,
      sort: row.sort,
      name: row.name,
      nameCn: row.name_cn ?? undefined,
      status: row.status,
      updatedAt: row.updated_at ?? undefined
    };
  }
}

function seedEpisodes(
  subjectId: number,
  total: number,
  collectionStatus?: CollectionStatus
): Map<number, EpisodeStatus> {
  const map = new Map<number, EpisodeStatus>();

  for (let sort = 1; sort <= total; sort += 1) {
    map.set(sort, "unwatched");
  }

  if (!collectionStatus) {
    return map;
  }

  if (collectionStatus === "watching") {
    const watchedUntil = subjectId === 1 ? 7 : subjectId === 6 ? 5 : 3;
    for (let sort = 1; sort < watchedUntil; sort += 1) {
      map.set(sort, "watched");
    }
    map.set(watchedUntil, "queue");
  } else if (collectionStatus === "completed") {
    for (let sort = 1; sort <= total; sort += 1) {
      map.set(sort, "watched");
    }
  } else if (collectionStatus === "on_hold") {
    for (let sort = 1; sort <= Math.min(4, total); sort += 1) {
      map.set(sort, "watched");
    }
    if (total >= 5) {
      map.set(5, "queue");
    }
  } else if (collectionStatus === "dropped") {
    for (let sort = 1; sort <= Math.min(2, total); sort += 1) {
      map.set(sort, "watched");
    }
    if (total >= 3) {
      map.set(3, "dropped");
    }
  }

  return map;
}

function isoNow(): string {
  return new Date().toISOString();
}

function jsonOrNull(value: unknown): string | null {
  return typeof value === "undefined" ? null : JSON.stringify(value);
}

function parseJson<T>(value: string | null): T | undefined {
  if (!value) {
    return undefined;
  }

  try {
    return JSON.parse(value) as T;
  } catch {
    return undefined;
  }
}
