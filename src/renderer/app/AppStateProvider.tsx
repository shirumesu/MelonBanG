import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState
} from "react";
import type { ReactNode } from "react";
import type {
  BangumiSession,
  BroadcastDay,
  BroadcastItem,
  CollectionFilter,
  CollectionListItem,
  SubjectDetail,
  SubjectSearchResult,
  SyncState,
  TrackingMutation
} from "@shared/contracts/bangumi";

type AppStateValue = {
  session: BangumiSession | null;
  syncState: SyncState | null;
  isBootstrapping: boolean;
  collectionItems: CollectionListItem[];
  collectionLoaded: boolean;
  homeItems: CollectionListItem[];
  trendingItems: BroadcastItem[];
  todaySchedule: BroadcastDay | null;
  calendarDays: BroadcastDay[];
  isPublicDataLoading: boolean;
  refreshSession: () => Promise<void>;
  signIn: () => Promise<void>;
  cancelSignIn: () => Promise<void>;
  signOut: () => Promise<void>;
  listCollection: (filter?: CollectionFilter) => Promise<CollectionListItem[]>;
  getCachedSubject: (subjectId: number) => Promise<SubjectDetail | null>;
  getSubject: (subjectId: number) => Promise<SubjectDetail>;
  searchSubjects: (keyword: string) => Promise<SubjectSearchResult[]>;
  refreshCalendar: (force?: boolean) => Promise<void>;
  updateTracking: (input: TrackingMutation) => Promise<void>;
  refreshCollection: (force?: boolean) => Promise<void>;
};

const AppStateContext = createContext<AppStateValue | null>(null);
const PUBLIC_DATA_TTL_MS = 5 * 60 * 1000;

export function AppStateProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<BangumiSession | null>(null);
  const [syncState, setSyncState] = useState<SyncState | null>(null);
  const [collectionItems, setCollectionItems] = useState<CollectionListItem[]>([]);
  const [collectionLoaded, setCollectionLoaded] = useState(false);
  const [homeItems, setHomeItems] = useState<CollectionListItem[]>([]);
  const [trendingItems, setTrendingItems] = useState<BroadcastItem[]>([]);
  const [todaySchedule, setTodaySchedule] = useState<BroadcastDay | null>(null);
  const [calendarDays, setCalendarDays] = useState<BroadcastDay[]>([]);
  const [isBootstrapping, setIsBootstrapping] = useState(true);
  const [isPublicDataLoading, setIsPublicDataLoading] = useState(false);
  const publicHomeRequestRef = useRef<Promise<void> | null>(null);
  const publicHomeLoadedAtRef = useRef(0);
  const calendarRequestRef = useRef<Promise<void> | null>(null);
  const calendarLoadedAtRef = useRef(0);
  const postMutationSyncTimersRef = useRef<number[]>([]);

  const applyCollectionSnapshot = useCallback((nextItems: CollectionListItem[]): void => {
    setCollectionItems(nextItems);
    setCollectionLoaded(true);
    setHomeItems(nextItems.filter((item) => item.collection.status === "watching"));
  }, []);

  const clearCollectionSnapshot = useCallback((): void => {
    setCollectionItems([]);
    setCollectionLoaded(false);
    setHomeItems([]);
  }, []);

  const loadCollectionSnapshot = useCallback(async (): Promise<CollectionListItem[]> => {
    const nextItems = await window.melonbang.bangumi.listCollection();
    applyCollectionSnapshot(nextItems);
    return nextItems;
  }, [applyCollectionSnapshot]);

  const refreshPublicHomeData = useCallback(async (force = false): Promise<void> => {
    if (!force && publicHomeRequestRef.current) {
      return publicHomeRequestRef.current;
    }
    if (
      !force &&
      publicHomeLoadedAtRef.current > 0 &&
      Date.now() - publicHomeLoadedAtRef.current < PUBLIC_DATA_TTL_MS
    ) {
      return;
    }

    setIsPublicDataLoading(true);
    const request = (async () => {
      if (!force && publicHomeLoadedAtRef.current === 0) {
        const cachedPublicData = await loadCachedPublicHomeData();
        if (cachedPublicData.trendingItems.length > 0) {
          setTrendingItems(cachedPublicData.trendingItems);
        }
        if (cachedPublicData.todaySchedule) {
          setTodaySchedule(cachedPublicData.todaySchedule);
        }
      }

      const publicData = await loadPublicHomeData();
      if (publicData.trendingItems) {
        setTrendingItems(publicData.trendingItems);
      }
      if (typeof publicData.todaySchedule !== "undefined") {
        setTodaySchedule(publicData.todaySchedule);
      }
      if (publicData.trendingItems || typeof publicData.todaySchedule !== "undefined") {
        publicHomeLoadedAtRef.current = Date.now();
      }
    })().finally(() => {
      if (publicHomeRequestRef.current === request) {
        publicHomeRequestRef.current = null;
      }
      setIsPublicDataLoading(false);
    });
    publicHomeRequestRef.current = request;
    return request;
  }, []);

  const refreshCalendar = useCallback(async (force = false): Promise<void> => {
    if (!force && calendarRequestRef.current) {
      return calendarRequestRef.current;
    }
    if (
      !force &&
      calendarLoadedAtRef.current > 0 &&
      Date.now() - calendarLoadedAtRef.current < PUBLIC_DATA_TTL_MS
    ) {
      return;
    }

    const request = window.melonbang.bangumi
      .getCalendar()
      .catch(() => [])
      .then((nextCalendarDays) => {
        setCalendarDays(nextCalendarDays);
        calendarLoadedAtRef.current = Date.now();
      })
      .finally(() => {
        if (calendarRequestRef.current === request) {
          calendarRequestRef.current = null;
        }
      });
    calendarRequestRef.current = request;
    return request;
  }, []);

  const refreshCollection = useCallback(
    async (force?: boolean): Promise<void> => {
      const nextSyncState = await window.melonbang.bangumi.refreshCollection(force);
      setSyncState(nextSyncState);
      await loadCollectionSnapshot();
    },
    [loadCollectionSnapshot]
  );

  const refreshSyncAndCollectionSnapshot = useCallback(async (): Promise<void> => {
    const nextSyncState = await window.melonbang.bangumi.getSyncState();
    setSyncState(nextSyncState);
    await loadCollectionSnapshot();
  }, [loadCollectionSnapshot]);

  const schedulePostMutationSyncCheck = useCallback((): void => {
    for (const delay of [750, 2500]) {
      const timer = window.setTimeout(() => {
        postMutationSyncTimersRef.current = postMutationSyncTimersRef.current.filter(
          (entry) => entry !== timer
        );
        void refreshSyncAndCollectionSnapshot().catch(() => undefined);
      }, delay);
      postMutationSyncTimersRef.current.push(timer);
    }
  }, [refreshSyncAndCollectionSnapshot]);

  const refreshSession = useCallback(async (): Promise<void> => {
    setIsBootstrapping(true);
    try {
      const [nextSession, nextSyncState] = await Promise.all([
        window.melonbang.bangumi.getSession(),
        window.melonbang.bangumi.getSyncState()
      ]);
      setSession(nextSession);
      setSyncState(nextSyncState);
      setIsBootstrapping(false);
      if (nextSession) {
        void loadCollectionSnapshot().catch(() => undefined);
        void refreshCollection(false).catch(() => undefined);
      } else {
        clearCollectionSnapshot();
      }
      void refreshPublicHomeData();
    } catch (error) {
      setSession(null);
      setSyncState({
        stale: true,
        pendingMutationCount: 0,
        lastSyncError: errorMessage(error)
      });
      clearCollectionSnapshot();
      setTrendingItems([]);
      setTodaySchedule(null);
      setCalendarDays([]);
      setIsBootstrapping(false);
    } finally {
      setIsBootstrapping(false);
    }
  }, [clearCollectionSnapshot, loadCollectionSnapshot, refreshCollection, refreshPublicHomeData]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void refreshSession();
    }, 0);
    return () => window.clearTimeout(timer);
  }, [refreshSession]);

  useEffect(
    () => () => {
      for (const timer of postMutationSyncTimersRef.current) {
        window.clearTimeout(timer);
      }
      postMutationSyncTimersRef.current = [];
    },
    []
  );

  const signIn = useCallback(async (): Promise<void> => {
    try {
      const nextSession = await window.melonbang.bangumi.signIn();
      setSession(nextSession);
      setSyncState(await window.melonbang.bangumi.getSyncState());
      await loadCollectionSnapshot();
      void refreshPublicHomeData();
    } catch (error) {
      setSession(null);
      setSyncState({
        stale: true,
        pendingMutationCount: 0,
        lastSyncError: errorMessage(error)
      });
      clearCollectionSnapshot();
      setTrendingItems([]);
      setTodaySchedule(null);
      setCalendarDays([]);
      throw error;
    }
  }, [clearCollectionSnapshot, loadCollectionSnapshot, refreshPublicHomeData]);

  const cancelSignIn = useCallback(async (): Promise<void> => {
    await window.melonbang.bangumi.cancelSignIn();
  }, []);

  const signOut = useCallback(async (): Promise<void> => {
    await window.melonbang.bangumi.signOut();
    setSession(null);
    setSyncState(null);
    clearCollectionSnapshot();
  }, [clearCollectionSnapshot]);

  const updateTracking = useCallback(
    async (input: TrackingMutation): Promise<void> => {
      const result = await window.melonbang.bangumi.updateTracking(input);
      setSyncState(result.syncState);
      await loadCollectionSnapshot();
      schedulePostMutationSyncCheck();
    },
    [loadCollectionSnapshot, schedulePostMutationSyncCheck]
  );

  const listCollection = useCallback(
    async (filter?: CollectionFilter): Promise<CollectionListItem[]> =>
      window.melonbang.bangumi.listCollection(filter),
    []
  );

  const getCachedSubject = useCallback(
    (subjectId: number) => window.melonbang.bangumi.getCachedSubject(subjectId),
    []
  );
  const getSubject = useCallback(
    (subjectId: number) => window.melonbang.bangumi.getSubject(subjectId),
    []
  );
  const searchSubjects = useCallback(
    (keyword: string) => window.melonbang.bangumi.searchSubjects(keyword),
    []
  );

  const value: AppStateValue = useMemo(
    () => ({
      session,
      syncState,
      isBootstrapping,
      collectionItems,
      collectionLoaded,
      homeItems,
      trendingItems,
      todaySchedule,
      calendarDays,
      isPublicDataLoading,
      refreshSession,
      signIn,
      cancelSignIn,
      signOut,
      listCollection,
      getCachedSubject,
      getSubject,
      searchSubjects,
      refreshCalendar,
      updateTracking,
      refreshCollection
    }),
    [
      session,
      syncState,
      isBootstrapping,
      collectionItems,
      collectionLoaded,
      homeItems,
      trendingItems,
      todaySchedule,
      calendarDays,
      isPublicDataLoading,
      refreshSession,
      signIn,
      cancelSignIn,
      signOut,
      listCollection,
      getCachedSubject,
      getSubject,
      searchSubjects,
      refreshCalendar,
      updateTracking,
      refreshCollection
    ]
  );

  return <AppStateContext.Provider value={value}>{children}</AppStateContext.Provider>;
}

export function useAppState(): AppStateValue {
  const value = useContext(AppStateContext);
  if (!value) {
    throw new Error("AppStateProvider is missing.");
  }
  return value;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "未知错误";
}

async function loadPublicHomeData(): Promise<{
  trendingItems?: BroadcastItem[];
  todaySchedule?: BroadcastDay | null;
}> {
  const [trendingResult, todayScheduleResult] = await Promise.allSettled([
    window.melonbang.bangumi.getTrendingCurrent(),
    window.melonbang.bangumi.getTodaySchedule()
  ]);

  return {
    trendingItems: trendingResult.status === "fulfilled" ? trendingResult.value : undefined,
    todaySchedule:
      todayScheduleResult.status === "fulfilled" ? todayScheduleResult.value : undefined
  };
}

async function loadCachedPublicHomeData(): Promise<{
  trendingItems: BroadcastItem[];
  todaySchedule: BroadcastDay | null;
}> {
  const [trendingItems, todaySchedule] = await Promise.all([
    window.melonbang.bangumi.getCachedTrendingCurrent().catch(() => []),
    window.melonbang.bangumi.getCachedTodaySchedule().catch(() => null)
  ]);

  return { trendingItems, todaySchedule };
}
