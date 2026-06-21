import type {
  BangumiBridge,
  BangumiSession,
  CollectionFilter,
  CollectionListItem,
  EpisodeCollectionState,
  EpisodeStatus,
  MutationResult,
  SubjectCollectionState,
  SubjectDetail,
  SubjectSearchResult,
  SyncState,
  TrackingMutation
} from "../../shared/contracts/bangumi";

type CatalogSubject = {
  subjectId: number;
  name: string;
  nameCn: string;
  episodeTotal: number;
  summary: string;
  airDate: string;
  rank: number;
  score: number;
  coverUrl?: string;
};

const session: BangumiSession = {
  userId: "9527",
  username: "melonfan",
  nickname: "メロン汽水",
  avatarUrl: "https://api.dicebear.com/9.x/thumbs/svg?seed=melonbang"
};

const catalog: CatalogSubject[] = [
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
];

const collectionStore = new Map<number, SubjectCollectionState>([
  [1, { subjectId: 1, status: "watching", score: 8, updatedAt: isoNow() }],
  [2, { subjectId: 2, status: "wish", score: 0, updatedAt: isoNow() }],
  [3, { subjectId: 3, status: "completed", score: 9, updatedAt: isoNow() }],
  [4, { subjectId: 4, status: "on_hold", score: 7, updatedAt: isoNow() }],
  [5, { subjectId: 5, status: "dropped", score: 6, updatedAt: isoNow() }],
  [6, { subjectId: 6, status: "watching", score: 8, updatedAt: isoNow() }],
  [7, { subjectId: 7, status: "watching", score: 8, updatedAt: isoNow() }],
  [8, { subjectId: 8, status: "completed", score: 9, updatedAt: isoNow() }]
] satisfies Array<[number, SubjectCollectionState]>);

const episodeStore = new Map<number, Map<number, EpisodeStatus>>(
  catalog.map((subject) => [
    subject.subjectId,
    seedEpisodes(subject.subjectId, subject.episodeTotal)
  ])
);

let signedIn = true;
let syncState: SyncState = {
  stale: false,
  lastSuccessfulSyncAt: isoNow(),
  pendingMutationCount: 0
};

export function getMockBangumiService(): BangumiBridge {
  return {
    getSession() {
      return Promise.resolve(signedIn ? session : null);
    },
    signIn() {
      signedIn = true;
      return Promise.resolve(session);
    },
    signOut() {
      signedIn = false;
      return Promise.resolve();
    },
    listCollection(filter) {
      const items = Array.from(collectionStore.values())
        .map((collection) => buildCollectionItem(collection.subjectId))
        .filter((item): item is CollectionListItem => Boolean(item));

      const loweredSearch = filter?.search?.trim().toLowerCase();
      return Promise.resolve(
        items
          .filter((item) => matchesFilter(item, filter, loweredSearch))
          .sort(
            (left, right) =>
              Date.parse(right.collection.updatedAt) - Date.parse(left.collection.updatedAt)
          )
      );
    },
    getSubject(subjectId) {
      const detail = buildSubjectDetail(subjectId);
      if (!detail) {
        throw new Error(`Subject ${subjectId} not found.`);
      }
      return Promise.resolve(detail);
    },
    searchSubjects(keyword) {
      const lowered = keyword.trim().toLowerCase();
      return Promise.resolve(
        catalog
          .filter((subject) =>
            [subject.name, subject.nameCn, subject.summary].some((value) =>
              value.toLowerCase().includes(lowered)
            )
          )
          .map<SubjectSearchResult>((subject) => ({
            subjectId: subject.subjectId,
            name: subject.name,
            nameCn: subject.nameCn,
            episodeTotal: subject.episodeTotal,
            summary: subject.summary,
            coverUrl: subject.coverUrl
          }))
      );
    },
    updateTracking(input) {
      if (input.kind === "subjectCollection") {
        applySubjectCollectionMutation(input);
      } else {
        applyEpisodeMutation(input);
      }

      syncState = {
        stale: false,
        pendingMutationCount: 0,
        lastSuccessfulSyncAt: isoNow()
      };

      return Promise.resolve({
        mutationId: crypto.randomUUID(),
        mutationKey:
          input.kind === "subjectCollection"
            ? `subject:${input.subjectId}:collection`
            : `episode:${input.episodeId}:collection`,
        accepted: true,
        appliedLocally: true,
        syncState
      } satisfies MutationResult);
    },
    refreshCollection(force) {
      syncState = {
        ...syncState,
        stale: false,
        lastSuccessfulSyncAt: force ? isoNow() : syncState.lastSuccessfulSyncAt
      };
      return Promise.resolve(syncState);
    },
    getSyncState() {
      return Promise.resolve(syncState);
    }
  };
}

function matchesFilter(
  item: CollectionListItem,
  filter: CollectionFilter | undefined,
  loweredSearch: string | undefined
): boolean {
  const matchesStatus = filter?.status ? item.collection.status === filter.status : true;
  const matchesSearch = loweredSearch
    ? [item.name, item.nameCn, item.summary, item.nextEpisode?.name, item.nextEpisode?.nameCn]
        .filter(Boolean)
        .some((value) => value?.toLowerCase().includes(loweredSearch))
    : true;
  return matchesStatus && matchesSearch;
}

function buildCollectionItem(subjectId: number): CollectionListItem | null {
  const subject = catalog.find((entry) => entry.subjectId === subjectId);
  const collection = collectionStore.get(subjectId);
  if (!subject || !collection) {
    return null;
  }

  const nextEpisode = buildEpisodes(subject).find(
    (episode) => episode.status === "queue" || episode.status === "unwatched"
  );

  return {
    subjectId: subject.subjectId,
    name: subject.name,
    nameCn: subject.nameCn,
    coverUrl: subject.coverUrl,
    episodeTotal: subject.episodeTotal,
    summary: subject.summary,
    collection,
    nextEpisode,
    pendingMutationKeys: []
  };
}

function buildSubjectDetail(subjectId: number): SubjectDetail | null {
  const subject = catalog.find((entry) => entry.subjectId === subjectId);
  if (!subject) {
    return null;
  }

  return {
    subjectId: subject.subjectId,
    name: subject.name,
    nameCn: subject.nameCn,
    coverUrl: subject.coverUrl,
    summary: subject.summary,
    episodeTotal: subject.episodeTotal,
    airDate: subject.airDate,
    score: subject.score,
    rank: subject.rank,
    collection: collectionStore.get(subject.subjectId) ?? null,
    episodes: buildEpisodes(subject)
  };
}

function buildEpisodes(subject: CatalogSubject): EpisodeCollectionState[] {
  const stateMap = episodeStore.get(subject.subjectId) ?? new Map<number, EpisodeStatus>();
  return Array.from({ length: subject.episodeTotal }, (_, index) => {
    const sort = index + 1;
    return {
      episodeId: subject.subjectId * 100 + sort,
      subjectId: subject.subjectId,
      sort,
      name: `Episode ${sort}`,
      nameCn: `第 ${sort} 话`,
      status: stateMap.get(sort) ?? "unwatched",
      updatedAt: isoNow()
    };
  });
}

function applySubjectCollectionMutation(
  input: Extract<TrackingMutation, { kind: "subjectCollection" }>
): void {
  const subject = catalog.find((entry) => entry.subjectId === input.subjectId);
  if (!subject) {
    return;
  }

  const previous = collectionStore.get(input.subjectId);
  const nextStatus = input.status ?? previous?.status;
  if (!nextStatus) {
    return;
  }

  collectionStore.set(input.subjectId, {
    subjectId: input.subjectId,
    status: nextStatus,
    score: typeof input.score === "number" ? input.score : previous?.score,
    updatedAt: isoNow()
  });

  episodeStore.set(
    input.subjectId,
    episodeStore.get(input.subjectId) ?? seedEpisodes(subject.subjectId, subject.episodeTotal)
  );
}

function applyEpisodeMutation(
  input: Extract<TrackingMutation, { kind: "episodeCollection" }>
): void {
  const subjectId = Math.floor(input.episodeId / 100);
  const episodeSort = input.episodeId % 100;
  const subject = catalog.find((entry) => entry.subjectId === subjectId);
  if (!subject) {
    return;
  }

  const episodes =
    episodeStore.get(subjectId) ?? seedEpisodes(subject.subjectId, subject.episodeTotal);
  episodes.set(episodeSort, input.status);

  if (!collectionStore.has(subjectId)) {
    collectionStore.set(subjectId, {
      subjectId,
      status: "watching",
      score: 0,
      updatedAt: isoNow()
    });
  } else {
    const collection = collectionStore.get(subjectId)!;
    collection.updatedAt = isoNow();
    if (collection.status === "wish" && input.status === "watched") {
      collection.status = "watching";
    }
  }
}

function seedEpisodes(subjectId: number, total: number): Map<number, EpisodeStatus> {
  const map = new Map<number, EpisodeStatus>();
  const collection = collectionStore.get(subjectId);

  for (let sort = 1; sort <= total; sort += 1) {
    map.set(sort, "unwatched");
  }

  if (!collection) {
    return map;
  }

  if (collection.status === "watching") {
    const watchedUntil = subjectId === 1 ? 7 : subjectId === 6 ? 5 : 3;
    for (let sort = 1; sort < watchedUntil; sort += 1) {
      map.set(sort, "watched");
    }
    map.set(watchedUntil, "queue");
  } else if (collection.status === "completed") {
    for (let sort = 1; sort <= total; sort += 1) {
      map.set(sort, "watched");
    }
  } else if (collection.status === "on_hold") {
    for (let sort = 1; sort <= Math.min(4, total); sort += 1) {
      map.set(sort, "watched");
    }
    if (total >= 5) {
      map.set(5, "queue");
    }
  } else if (collection.status === "dropped") {
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
