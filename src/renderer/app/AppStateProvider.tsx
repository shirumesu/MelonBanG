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
      const publicData = await loadPublicHomeData();
      setTrendingItems(publicData.trendingItems);
      setTodaySchedule(publicData.todaySchedule);
      publicHomeLoadedAtRef.current = Date.now();
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

  const refreshSession = useCallback(async (): Promise<void> => {
    setIsBootstrapping(true);
    try {
      const [nextSession, nextSyncState] = await Promise.all([
        window.melonbang.bangumi.getSession(),
        window.melonbang.bangumi.getSyncState()
      ]);
      setSession(nextSession);
      setSyncState(nextSyncState);
      if (nextSession) {
        const nextHomeItems = await window.melonbang.bangumi.listCollection({
          status: "watching"
        });
        setHomeItems(nextHomeItems);
      } else {
        setHomeItems([]);
      }
      void refreshPublicHomeData();
    } catch (error) {
      setSession(null);
      setSyncState({
        stale: true,
        pendingMutationCount: 0,
        lastSyncError: errorMessage(error)
      });
      setHomeItems([]);
      setTrendingItems([]);
      setTodaySchedule(null);
      setCalendarDays([]);
    } finally {
      setIsBootstrapping(false);
    }
  }, [refreshPublicHomeData]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void refreshSession();
    }, 0);
    return () => window.clearTimeout(timer);
  }, [refreshSession]);

  const signIn = useCallback(async (): Promise<void> => {
    try {
      const nextSession = await window.melonbang.bangumi.signIn();
      setSession(nextSession);
      setSyncState(await window.melonbang.bangumi.getSyncState());
      const nextHomeItems = await window.melonbang.bangumi.listCollection({ status: "watching" });
      setHomeItems(nextHomeItems);
      void refreshPublicHomeData();
    } catch (error) {
      setSession(null);
      setSyncState({
        stale: true,
        pendingMutationCount: 0,
        lastSyncError: errorMessage(error)
      });
      setHomeItems([]);
      setTrendingItems([]);
      setTodaySchedule(null);
      setCalendarDays([]);
      throw error;
    }
  }, [refreshPublicHomeData]);

  const cancelSignIn = useCallback(async (): Promise<void> => {
    await window.melonbang.bangumi.cancelSignIn();
  }, []);

  const signOut = useCallback(async (): Promise<void> => {
    await window.melonbang.bangumi.signOut();
    setSession(null);
    setSyncState(null);
    setHomeItems([]);
  }, []);

  const refreshWatchingItems = useCallback(async (): Promise<void> => {
    setHomeItems(await window.melonbang.bangumi.listCollection({ status: "watching" }));
  }, []);

  const refreshCollection = useCallback(
    async (force?: boolean): Promise<void> => {
      const nextSyncState = await window.melonbang.bangumi.refreshCollection(force);
      setSyncState(nextSyncState);
      await refreshWatchingItems();
    },
    [refreshWatchingItems]
  );

  const updateTracking = useCallback(
    async (input: TrackingMutation): Promise<void> => {
      const result = await window.melonbang.bangumi.updateTracking(input);
      setSyncState(result.syncState);
      await refreshWatchingItems();
    },
    [refreshWatchingItems]
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
  trendingItems: BroadcastItem[];
  todaySchedule: BroadcastDay | null;
}> {
  const [trendingItems, todaySchedule] = await Promise.all([
    window.melonbang.bangumi.getTrendingCurrent().catch(() => []),
    window.melonbang.bangumi.getTodaySchedule().catch(() => null)
  ]);

  return { trendingItems, todaySchedule };
}
