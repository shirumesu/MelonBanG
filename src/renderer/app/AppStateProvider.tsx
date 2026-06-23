import { createContext, useCallback, useContext, useEffect, useState } from "react";
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
  refreshCalendar: () => Promise<void>;
  updateTracking: (input: TrackingMutation) => Promise<void>;
  refreshCollection: (force?: boolean) => Promise<void>;
};

const AppStateContext = createContext<AppStateValue | null>(null);

export function AppStateProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<BangumiSession | null>(null);
  const [syncState, setSyncState] = useState<SyncState | null>(null);
  const [homeItems, setHomeItems] = useState<CollectionListItem[]>([]);
  const [trendingItems, setTrendingItems] = useState<BroadcastItem[]>([]);
  const [todaySchedule, setTodaySchedule] = useState<BroadcastDay | null>(null);
  const [calendarDays, setCalendarDays] = useState<BroadcastDay[]>([]);
  const [isBootstrapping, setIsBootstrapping] = useState(true);
  const [isPublicDataLoading, setIsPublicDataLoading] = useState(false);

  const refreshPublicHomeData = useCallback(async (): Promise<void> => {
    setIsPublicDataLoading(true);
    try {
      const publicData = await loadPublicHomeData();
      setTrendingItems(publicData.trendingItems);
      setTodaySchedule(publicData.todaySchedule);
      setCalendarDays(publicData.calendarDays);
    } finally {
      setIsPublicDataLoading(false);
    }
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

  async function signIn(): Promise<void> {
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
  }

  async function cancelSignIn(): Promise<void> {
    await window.melonbang.bangumi.cancelSignIn();
  }

  async function signOut(): Promise<void> {
    await window.melonbang.bangumi.signOut();
    setSession(null);
    setSyncState(null);
    setHomeItems([]);
  }

  async function refreshCollection(force?: boolean): Promise<void> {
    const nextSyncState = await window.melonbang.bangumi.refreshCollection(force);
    setSyncState(nextSyncState);
    setHomeItems(await window.melonbang.bangumi.listCollection({ status: "watching" }));
  }

  const refreshCalendar = useCallback(async (): Promise<void> => {
    await refreshPublicHomeData();
  }, [refreshPublicHomeData]);

  async function updateTracking(input: TrackingMutation): Promise<void> {
    const result = await window.melonbang.bangumi.updateTracking(input);
    setSyncState(result.syncState);
    setHomeItems(await window.melonbang.bangumi.listCollection({ status: "watching" }));
  }

  async function listCollection(filter?: CollectionFilter): Promise<CollectionListItem[]> {
    return window.melonbang.bangumi.listCollection(filter);
  }

  const value: AppStateValue = {
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
    getCachedSubject: (subjectId) => window.melonbang.bangumi.getCachedSubject(subjectId),
    getSubject: (subjectId) => window.melonbang.bangumi.getSubject(subjectId),
    searchSubjects: (keyword) => window.melonbang.bangumi.searchSubjects(keyword),
    refreshCalendar,
    updateTracking,
    refreshCollection
  };

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
  calendarDays: BroadcastDay[];
}> {
  const [trendingItems, todaySchedule, calendarDays] = await Promise.all([
    window.melonbang.bangumi.getTrendingCurrent().catch(() => []),
    window.melonbang.bangumi.getTodaySchedule().catch(() => null),
    window.melonbang.bangumi.getCalendar().catch(() => [])
  ]);

  return { trendingItems, todaySchedule, calendarDays };
}
