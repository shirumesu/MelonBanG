import type {
  BangumiBridge,
  BangumiSession,
  BroadcastDay,
  BroadcastItem,
  CollectionFilter,
  CollectionListItem,
  EpisodeCollectionState,
  MutationResult,
  SubjectDetail,
  SubjectSearchResult,
  SyncState,
  TrackingMutation
} from "../../shared/contracts/bangumi";
import type { BangumiOAuthConfig } from "../config/bangumi";
import { CollectionStore } from "../store/collectionStore";
import { MutationQueueStore } from "../store/mutationQueueStore";
import { SyncStateStore } from "../store/syncStateStore";
import { BangumiClient } from "./BangumiClient";
import { MelonApiClient } from "./MelonApiClient";
import { BangumiOAuth } from "./BangumiOAuth";

export class BangumiRepository implements BangumiBridge {
  private readonly oauth: BangumiOAuth;
  private readonly collectionStore = new CollectionStore();
  private readonly mutationQueueStore = new MutationQueueStore();
  private readonly syncStateStore = new SyncStateStore();
  private readonly melonApi = new MelonApiClient();
  private calendarCache: { fetchedAt: number; days: BroadcastDay[] } | null = null;
  private todayScheduleCache: { fetchedAt: number; day: BroadcastDay } | null = null;
  private trendingCache: { fetchedAt: number; items: BroadcastItem[] } | null = null;

  constructor(private readonly config: BangumiOAuthConfig) {
    this.oauth = new BangumiOAuth(config);
  }

  async getSession(): Promise<BangumiSession | null> {
    return this.oauth.getStoredSession();
  }

  async signIn(): Promise<BangumiSession> {
    const session = await this.oauth.signIn();
    await this.refreshCollection(true);
    return session;
  }

  signOut(): Promise<void> {
    this.oauth.clearSession();
    return Promise.resolve();
  }

  listCollection(filter?: CollectionFilter): Promise<CollectionListItem[]> {
    return Promise.resolve(this.collectionStore.listCollection(filter));
  }

  async getSubject(subjectId: number): Promise<SubjectDetail> {
    const cached = this.collectionStore.getSubject(subjectId);

    try {
      const subject = await this.melonApi.getSubject(subjectId);
      const episodeCollections = await this.getOptionalClient()
        .then(
          (client) => client?.getUserSubjectEpisodeCollections(subjectId) ?? Promise.resolve([])
        )
        .catch(() => []);

      this.upsertSubject(subject);

      for (const episode of mergeEpisodeState(subject.episodes, episodeCollections)) {
        this.collectionStore.updateEpisodeStatus(episode);
      }

      const refreshed = this.collectionStore.getSubject(subjectId);
      if (!refreshed) {
        throw new Error(`Subject ${subjectId} could not be loaded.`);
      }

      return refreshed;
    } catch {
      if (cached) {
        return cached;
      }
    }

    const client = await this.getClient();
    const subject = await client.getSubject(subjectId);
    const episodes = await client.getEpisodes(subjectId);
    const episodeCollections = await client
      .getUserSubjectEpisodeCollections(subjectId)
      .catch(() => []);

    this.upsertSubject(subject);

    for (const episode of mergeEpisodeState(episodes, episodeCollections)) {
      this.collectionStore.updateEpisodeStatus(episode);
    }

    const refreshed = this.collectionStore.getSubject(subjectId);
    if (!refreshed) {
      throw new Error(`Subject ${subjectId} could not be loaded.`);
    }

    return refreshed;
  }

  async searchSubjects(keyword: string): Promise<SubjectSearchResult[]> {
    const remote = await this.melonApi.searchSubjects(keyword).catch(async () => {
      const client = await this.getClient();
      return client.searchSubjects(keyword);
    });

    for (const subject of remote) {
      this.upsertSubject(subject);
    }

    return this.collectionStore.searchSubjects(keyword);
  }

  async getTrendingCurrent(): Promise<BroadcastItem[]> {
    if (this.trendingCache && Date.now() - this.trendingCache.fetchedAt < 30 * 60 * 1000) {
      return this.trendingCache.items;
    }

    const items = await this.melonApi.getTrendingCurrent();
    this.trendingCache = { fetchedAt: Date.now(), items };
    return items;
  }

  async getTodaySchedule(): Promise<BroadcastDay> {
    if (
      this.todayScheduleCache &&
      Date.now() - this.todayScheduleCache.fetchedAt < 30 * 60 * 1000
    ) {
      return this.todayScheduleCache.day;
    }

    const day = await this.melonApi.getTodaySchedule();
    this.todayScheduleCache = { fetchedAt: Date.now(), day };
    return day;
  }

  async getCalendar(): Promise<BroadcastDay[]> {
    if (this.calendarCache && Date.now() - this.calendarCache.fetchedAt < 30 * 60 * 1000) {
      return this.calendarCache.days;
    }

    const days = await this.melonApi.getScheduleWeek();
    this.calendarCache = { fetchedAt: Date.now(), days };
    return days;
  }

  async updateTracking(input: TrackingMutation): Promise<MutationResult> {
    const updatedAt = new Date().toISOString();
    const queued = this.mutationQueueStore.enqueue(input);

    this.applyLocalMutation(input, updatedAt);

    try {
      const client = await this.getClient();
      await this.pushMutation(client, input);
      this.mutationQueueStore.markApplied(queued.mutationId);
      this.syncStateStore.markSuccess(updatedAt);
    } catch (error) {
      this.mutationQueueStore.markRetry(queued.mutationId, nextRetryAt(1));
      this.syncStateStore.markError(error instanceof Error ? error.message : "Unknown sync error");
    }

    return {
      mutationId: queued.mutationId,
      mutationKey: queued.mutationKey,
      accepted: true,
      appliedLocally: true,
      supersededMutationId: queued.supersededMutationId,
      syncState: this.readSyncState()
    };
  }

  async refreshCollection(force?: boolean): Promise<SyncState> {
    void force;

    try {
      const client = await this.getClient();
      const session = await this.oauth.getStoredSession();
      if (!session) {
        throw new Error("Bangumi session is missing.");
      }

      const collections = await client.getAllUserCollections(session.username);
      this.collectionStore.replaceSubjectCollections(
        collections.map((collection) => ({
          subject: {
            subjectId: collection.subject.id,
            name: collection.subject.name,
            nameCn: collection.subject.nameCn,
            summary: collection.subject.summary,
            coverUrl: collection.subject.coverUrl,
            airDate: collection.subject.date,
            episodeTotal: collection.subject.totalEpisodes,
            rank: collection.subject.rank,
            score: collection.subject.score
          },
          collection: {
            subjectId: collection.subjectId,
            status: collection.status,
            score: collection.score,
            updatedAt: collection.updatedAt,
            epStatus: collection.epStatus
          }
        }))
      );

      this.reapplyPendingMutations();
      const flushResult = await this.flushPendingMutations();
      if (flushResult.failed) {
        this.syncStateStore.markError(
          flushResult.lastError ?? "Some tracking changes are still waiting to sync."
        );
      } else {
        this.syncStateStore.markSuccess();
      }
    } catch (error) {
      this.syncStateStore.markError(
        error instanceof Error ? error.message : "Unknown refresh error"
      );
    }

    return this.readSyncState();
  }

  getSyncState(): Promise<SyncState> {
    return Promise.resolve(this.readSyncState());
  }

  private readSyncState(): SyncState {
    return this.syncStateStore.read(this.mutationQueueStore.getPendingCount());
  }

  private async getClient(): Promise<BangumiClient> {
    const token = await this.oauth.getValidAccessToken();
    if (!token) {
      throw new Error("Bangumi access token is unavailable.");
    }

    return new BangumiClient(this.config, token.accessToken);
  }

  private async getOptionalClient(): Promise<BangumiClient | null> {
    const token = await this.oauth.getValidAccessToken().catch(() => null);
    if (!token) {
      return null;
    }

    return new BangumiClient(this.config, token.accessToken);
  }

  private upsertSubject(subject: {
    id: number;
    name: string;
    nameCn?: string;
    summary?: string;
    coverUrl?: string;
    date?: string;
    platform?: string;
    totalEpisodes?: number;
    rank?: number;
    score?: number;
    ratingCount?: number;
    collectionStats?: SubjectDetail["collectionStats"];
    metaTags?: string[];
    tags?: SubjectDetail["tags"];
    infoBox?: SubjectDetail["infoBox"];
    characters?: SubjectDetail["characters"];
    staff?: SubjectDetail["staff"];
    relatedSubjects?: SubjectDetail["relatedSubjects"];
    comments?: SubjectDetail["comments"];
    topics?: SubjectDetail["topics"];
    schedule?: SubjectDetail["schedule"];
    sourceNotes?: string[];
  }): void {
    this.collectionStore.upsertSubjectCache({
      subjectId: subject.id,
      name: subject.name,
      nameCn: subject.nameCn,
      summary: subject.summary,
      coverUrl: subject.coverUrl,
      airDate: subject.date,
      platform: subject.platform,
      episodeTotal: subject.totalEpisodes,
      rank: subject.rank,
      score: subject.score,
      ratingCount: subject.ratingCount,
      collectionStats: subject.collectionStats,
      metaTags: subject.metaTags,
      tags: subject.tags,
      infoBox: subject.infoBox,
      characters: subject.characters,
      staff: subject.staff,
      relatedSubjects: subject.relatedSubjects,
      comments: subject.comments,
      topics: subject.topics,
      schedule: subject.schedule,
      sourceNotes: subject.sourceNotes
    });
  }

  private applyLocalMutation(input: TrackingMutation, updatedAt: string): void {
    if (input.kind === "subjectCollection") {
      const current = this.collectionStore.getSubject(input.subjectId);
      const nextStatus = input.status ?? current?.collection?.status;
      if (!nextStatus) {
        return;
      }

      this.collectionStore.upsertSubjectCollection({
        subjectId: input.subjectId,
        status: nextStatus,
        score: typeof input.score === "number" ? input.score : current?.collection?.score,
        updatedAt
      });
      return;
    }

    const episode = this.collectionStore.getEpisode(input.episodeId);
    if (!episode) {
      return;
    }

    this.collectionStore.updateEpisodeStatus({
      ...episode,
      status: input.status,
      updatedAt
    });

    const detail = this.collectionStore.getSubject(episode.subjectId);
    const currentCollection = detail?.collection;

    if (!currentCollection) {
      this.collectionStore.upsertSubjectCollection({
        subjectId: episode.subjectId,
        status: "watching",
        updatedAt
      });
      return;
    }

    if (currentCollection.status === "wish" && input.status === "watched") {
      this.collectionStore.upsertSubjectCollection({
        subjectId: episode.subjectId,
        status: "watching",
        score: currentCollection.score,
        updatedAt
      });
    }
  }

  private async pushMutation(client: BangumiClient, input: TrackingMutation): Promise<void> {
    if (input.kind === "subjectCollection") {
      await client.updateSubjectCollection(input.subjectId, {
        status: input.status,
        score: input.score
      });
      return;
    }

    await client.updateEpisodeCollection(input.episodeId, input.status);
  }

  private reapplyPendingMutations(): void {
    for (const mutation of this.mutationQueueStore.listPending()) {
      this.applyLocalMutation(mutation.payload, mutation.updatedAt);
    }
  }

  private async flushPendingMutations(): Promise<{ failed: boolean; lastError?: string }> {
    const client = await this.getClient();
    let lastError: string | undefined;

    for (const mutation of this.mutationQueueStore.listReady()) {
      try {
        await this.pushMutation(client, mutation.payload);
        this.mutationQueueStore.markApplied(mutation.mutationId);
      } catch (error) {
        this.mutationQueueStore.markRetry(
          mutation.mutationId,
          nextRetryAt(mutation.attemptCount + 1)
        );
        lastError = error instanceof Error ? error.message : "Unknown mutation sync error";
      }
    }

    return {
      failed: Boolean(lastError),
      lastError
    };
  }
}

function mergeEpisodeState(
  episodes: Array<{ id: number; subjectId: number; sort: number; name: string; nameCn?: string }>,
  remoteCollections: Array<{
    episode: { id: number; subjectId: number; sort: number; name: string; nameCn?: string };
    status: EpisodeCollectionState["status"];
    updatedAt?: string;
  }>
): EpisodeCollectionState[] {
  const remoteMap = new Map<
    number,
    { status: EpisodeCollectionState["status"]; updatedAt?: string }
  >(
    remoteCollections.map((item) => [
      item.episode.id,
      { status: item.status, updatedAt: item.updatedAt }
    ])
  );

  return episodes.map((episode) => ({
    episodeId: episode.id,
    subjectId: episode.subjectId,
    sort: episode.sort,
    name: episode.name,
    nameCn: episode.nameCn,
    status: remoteMap.get(episode.id)?.status ?? "unwatched",
    updatedAt: remoteMap.get(episode.id)?.updatedAt
  }));
}

function nextRetryAt(attemptCount: number): string {
  const delayMs = Math.min(60_000, 2 ** attemptCount * 1000);
  return new Date(Date.now() + delayMs).toISOString();
}
