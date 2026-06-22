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
  score?: number;
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

export type SeasonName = "WINTER" | "SPRING" | "SUMMER" | "FALL";

export type SeasonInfo = {
  year: number;
  quarter: 1 | 2 | 3 | 4;
  code: string;
  label: string;
  name: SeasonName;
};

export type SubjectPersonCredit = {
  personId?: number;
  name: string;
  nameCn?: string;
  displayName: string;
  imageUrl?: string;
  relation?: string;
  career?: string[];
  url?: string;
};

export type SubjectCharacterCredit = {
  characterId: number;
  name: string;
  nameCn?: string;
  displayName: string;
  role?: string;
  imageUrl?: string;
  actors: SubjectPersonCredit[];
  url?: string;
};

export type SubjectStaffCredit = SubjectPersonCredit & {
  role?: string;
};

export type RelatedSubject = {
  subjectId: number;
  name: string;
  nameCn?: string;
  displayName: string;
  relation?: string;
  coverUrl?: string;
  url?: string;
};

export type SubjectComment = {
  id?: string;
  user: {
    username?: string;
    nickname: string;
    avatarUrl?: string;
  };
  score?: number;
  status?: string;
  createdAt?: string;
  text: string;
  url?: string;
};

export type SubjectTopic = {
  topicId?: number;
  title: string;
  author?: string;
  replies?: number;
  updatedAt?: string;
  url?: string;
};

export type SubjectSchedule = {
  firstAiringAt?: string;
  firstAiringAtShanghai?: string;
  weekday?: string;
  recurrence?: "P0D" | "P1D" | "P7D" | "P1M";
  nextAiringAt?: string;
  nextAiringAtShanghai?: string;
  source?: "bangumi-data" | "bangumi-date" | "unknown";
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
  season?: SeasonInfo;
  characters?: SubjectCharacterCredit[];
  staff?: SubjectStaffCredit[];
  relatedSubjects?: RelatedSubject[];
  comments?: SubjectComment[];
  topics?: SubjectTopic[];
  schedule?: SubjectSchedule;
  sourceNotes?: string[];
  collection: SubjectCollectionState | null;
  episodes: EpisodeCollectionState[];
};

export type BroadcastItem = {
  subjectId?: number;
  name: string;
  nameCn?: string;
  displayName?: string;
  coverUrl?: string;
  summary?: string;
  airDate?: string;
  airingAt?: string;
  airingAtShanghai?: string;
  weekday?: string;
  season?: SeasonInfo;
  platform?: string;
  episodeTotal?: number;
  score?: number;
  rank?: number;
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
  getCachedSubject(subjectId: number): Promise<SubjectDetail | null>;
  getSubject(subjectId: number): Promise<SubjectDetail>;
  searchSubjects(keyword: string): Promise<SubjectSearchResult[]>;
  getTrendingCurrent(): Promise<BroadcastItem[]>;
  getTodaySchedule(): Promise<BroadcastDay>;
  getCalendar(): Promise<BroadcastDay[]>;
  updateTracking(input: TrackingMutation): Promise<MutationResult>;
  refreshCollection(force?: boolean): Promise<SyncState>;
  getSyncState(): Promise<SyncState>;
}
