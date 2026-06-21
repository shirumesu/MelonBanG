export type CollectionStatus = "wish" | "watching" | "completed" | "on_hold" | "dropped";

export type EpisodeStatus = "unwatched" | "queue" | "watched" | "dropped";

export type CollectionFilter = {
  status?: CollectionStatus;
  search?: string;
};

export type BangumiSession = {
  userId: string;
  username: string;
  nickname: string;
  avatarUrl?: string;
};

export type SubjectCollectionState = {
  subjectId: number;
  status: CollectionStatus;
  score?: number;
  updatedAt: string;
};

export type EpisodeCollectionState = {
  episodeId: number;
  subjectId: number;
  sort: number;
  name: string;
  nameCn?: string;
  status: EpisodeStatus;
  updatedAt?: string;
};

export type CollectionListItem = {
  subjectId: number;
  name: string;
  nameCn?: string;
  coverUrl?: string;
  episodeTotal?: number;
  summary?: string;
  collection: SubjectCollectionState;
  nextEpisode?: EpisodeCollectionState;
  pendingMutationKeys: string[];
};

export type SubjectSearchResult = {
  subjectId: number;
  name: string;
  nameCn?: string;
  coverUrl?: string;
  episodeTotal?: number;
  summary?: string;
};

export type SubjectDetail = {
  subjectId: number;
  name: string;
  nameCn?: string;
  coverUrl?: string;
  summary?: string;
  episodeTotal?: number;
  airDate?: string;
  score?: number;
  rank?: number;
  collection: SubjectCollectionState | null;
  episodes: EpisodeCollectionState[];
};

export type SubjectCollectionMutation = {
  kind: "subjectCollection";
  subjectId: number;
  status?: CollectionStatus;
  score?: number;
};

export type EpisodeCollectionMutation = {
  kind: "episodeCollection";
  episodeId: number;
  status: EpisodeStatus;
};

export type TrackingMutation = SubjectCollectionMutation | EpisodeCollectionMutation;

export type SyncState = {
  stale: boolean;
  lastSuccessfulSyncAt?: string;
  pendingMutationCount: number;
  lastSyncError?: string;
};

export type MutationResult = {
  mutationId: string;
  mutationKey: string;
  accepted: boolean;
  appliedLocally: boolean;
  syncState: SyncState;
  supersededMutationId?: string;
};

export interface BangumiBridge {
  getSession(): Promise<BangumiSession | null>;
  signIn(): Promise<BangumiSession>;
  signOut(): Promise<void>;
  listCollection(filter?: CollectionFilter): Promise<CollectionListItem[]>;
  getSubject(subjectId: number): Promise<SubjectDetail>;
  searchSubjects(keyword: string): Promise<SubjectSearchResult[]>;
  updateTracking(input: TrackingMutation): Promise<MutationResult>;
  refreshCollection(force?: boolean): Promise<SyncState>;
  getSyncState(): Promise<SyncState>;
}
