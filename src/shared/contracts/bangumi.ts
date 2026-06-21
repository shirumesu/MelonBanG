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
  watchedEpisodeCount?: number;
  summary?: string;
  collection: SubjectCollectionState;
  nextEpisode?: EpisodeCollectionState;
  pendingMutationKeys: string[];
};

export type SubjectCollectionStats = {
  wish: number;
  watching: number;
  completed: number;
  on_hold: number;
  dropped: number;
};

export type SubjectTag = {
  name: string;
  count?: number;
};

export type SubjectInfoBoxItem = {
  key: string;
  value: string;
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
  platform?: string;
  score?: number;
  rank?: number;
  ratingCount?: number;
  collectionStats?: SubjectCollectionStats;
  metaTags?: string[];
  tags?: SubjectTag[];
  infoBox?: SubjectInfoBoxItem[];
  collection: SubjectCollectionState | null;
  episodes: EpisodeCollectionState[];
};

export type BroadcastItem = {
  subjectId: number;
  name: string;
  nameCn?: string;
  coverUrl?: string;
  summary?: string;
  airDate?: string;
  episodeTotal?: number;
  score?: number;
  rank?: number;
};

export type BroadcastDay = {
  weekday: {
    id: number;
    cn: string;
    en: string;
    ja?: string;
  };
  items: BroadcastItem[];
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
  getCalendar(): Promise<BroadcastDay[]>;
  updateTracking(input: TrackingMutation): Promise<MutationResult>;
  refreshCollection(force?: boolean): Promise<SyncState>;
  getSyncState(): Promise<SyncState>;
}
