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
  SubjectDetail,
  SubjectInfoBoxItem,
  SubjectSchedule,
  SubjectSearchResult,
  SubjectStaffCredit,
  TrackingMutation
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

type PendingMutationRow = {
  mutation_key: string;
  payload_json: string;
};

export class CollectionStore {
  private readonly database = getAppDatabase();

  listCollection(filter?: CollectionFilter): CollectionListItem[] {
    const where: string[] = [];
    const params: unknown[] = [];
    if (filter?.status) {
      where.push("c.status = ?");
      params.push(filter.status);
    }

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
      ${where.length > 0 ? `WHERE ${where.join(" AND ")}` : ""}
      ORDER BY c.updated_at DESC
    `
      )
      .all(...params) as CollectionListRow[];

    const subjectIds = subjectRows.map((row) => row.subject_id);
    const nextEpisodes = this.listNextEpisodesBySubjectId(subjectIds);
    const pendingMutationKeys = this.listPendingMutationKeysBySubjectId(subjectIds);
    const loweredSearch = filter?.search?.trim().toLowerCase();

    return subjectRows
      .map((row) =>
        this.toCollectionListItem(
          row,
          nextEpisodes.get(row.subject_id),
          pendingMutationKeys.get(row.subject_id) ?? []
        )
      )
      .filter((item) => {
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
      comments: undefined,
      topics: undefined,
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
        comments_json = excluded.comments_json,
        topics_json = excluded.topics_json,
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
        null,
        null,
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

  private toCollectionListItem(
    row: CollectionListRow,
    nextEpisode: EpisodeCollectionState | undefined,
    pendingMutationKeys: string[]
  ): CollectionListItem {
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
      nextEpisode,
      pendingMutationKeys
    };
  }

  private listNextEpisodesBySubjectId(subjectIds: number[]): Map<number, EpisodeCollectionState> {
    if (subjectIds.length === 0) {
      return new Map();
    }

    const placeholders = placeholdersFor(subjectIds);
    const rows = this.database
      .prepare(
        `
      SELECT episode_id, subject_id, sort, name, name_cn, status, updated_at
      FROM (
        SELECT
          episode_id,
          subject_id,
          sort,
          name,
          name_cn,
          status,
          updated_at,
          ROW_NUMBER() OVER (
            PARTITION BY subject_id
            ORDER BY sort ASC, episode_id ASC
          ) AS row_number
        FROM episode_collections
        WHERE subject_id IN (${placeholders})
          AND status IN ('queue', 'unwatched')
      )
      WHERE row_number = 1
    `
      )
      .all(...subjectIds) as EpisodeCollectionRow[];

    return new Map(rows.map((row) => [row.subject_id, this.toEpisodeCollectionState(row)]));
  }

  private listPendingMutationKeysBySubjectId(subjectIds: number[]): Map<number, string[]> {
    const subjectIdSet = new Set(subjectIds);
    const pendingKeys = new Map<number, string[]>();
    if (subjectIdSet.size === 0) {
      return pendingKeys;
    }

    const pendingMutations = this.database
      .prepare(
        `
      SELECT mutation_key, payload_json
      FROM mutation_queue
      WHERE state IN ('pending', 'retry')
      ORDER BY created_at ASC
    `
      )
      .all() as PendingMutationRow[];

    const parsedMutations = pendingMutations.flatMap((row) => {
      const payload = parseJson<TrackingMutation>(row.payload_json);
      return payload ? [{ mutationKey: row.mutation_key, payload }] : [];
    });
    const episodeIds = parsedMutations.flatMap(({ payload }) =>
      payload.kind === "episodeCollection" ? [payload.episodeId] : []
    );
    const episodeSubjectIds = this.listSubjectIdsByEpisodeId(episodeIds);

    for (const { mutationKey, payload } of parsedMutations) {
      if (payload.kind === "subjectCollection") {
        if (subjectIdSet.has(payload.subjectId)) {
          appendPendingKey(pendingKeys, payload.subjectId, mutationKey);
        }
        continue;
      }

      const subjectId = episodeSubjectIds.get(payload.episodeId);
      if (typeof subjectId === "number" && subjectIdSet.has(subjectId)) {
        appendPendingKey(pendingKeys, subjectId, mutationKey);
      }
    }

    return pendingKeys;
  }

  private listSubjectIdsByEpisodeId(episodeIds: number[]): Map<number, number> {
    if (episodeIds.length === 0) {
      return new Map();
    }

    const uniqueEpisodeIds = Array.from(new Set(episodeIds));
    const rows = this.database
      .prepare(
        `
      SELECT episode_id, subject_id
      FROM episode_collections
      WHERE episode_id IN (${placeholdersFor(uniqueEpisodeIds)})
    `
      )
      .all(...uniqueEpisodeIds) as Array<{ episode_id: number; subject_id: number }>;

    return new Map(rows.map((row) => [row.episode_id, row.subject_id]));
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

function placeholdersFor(values: unknown[]): string {
  return values.map(() => "?").join(", ");
}

function appendPendingKey(
  keysBySubjectId: Map<number, string[]>,
  subjectId: number,
  mutationKey: string
): void {
  const keys = keysBySubjectId.get(subjectId);
  if (keys) {
    keys.push(mutationKey);
    return;
  }

  keysBySubjectId.set(subjectId, [mutationKey]);
}
