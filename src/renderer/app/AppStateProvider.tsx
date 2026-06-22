import { createContext, useContext, useEffect, useMemo, useState } from "react";
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
  refreshSession: () => Promise<void>;
  signIn: () => Promise<void>;
  signOut: () => Promise<void>;
  listCollection: (filter?: CollectionFilter) => Promise<CollectionListItem[]>;
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

  useEffect(() => {
    void refreshSession();
  }, []);

  async function refreshSession(): Promise<void> {
    setIsBootstrapping(true);
    try {
      const [nextSession, nextSyncState, publicData] = await Promise.all([
        window.melonbang.bangumi.getSession(),
        window.melonbang.bangumi.getSyncState(),
        loadPublicHomeData()
      ]);
      setSession(nextSession);
      setSyncState(nextSyncState);
      setTrendingItems(publicData.trendingItems);
      setTodaySchedule(publicData.todaySchedule);
      setCalendarDays(publicData.calendarDays);
      if (nextSession) {
        const nextHomeItems = await window.melonbang.bangumi.listCollection({
          status: "watching"
        });
        setHomeItems(nextHomeItems);
      } else {
        setHomeItems([]);
      }
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
  }

  async function signIn(): Promise<void> {
    try {
      const nextSession = await window.melonbang.bangumi.signIn();
      setSession(nextSession);
      setSyncState(await window.melonbang.bangumi.getSyncState());
      const [nextHomeItems, publicData] = await Promise.all([
        window.melonbang.bangumi.listCollection({ status: "watching" }),
        loadPublicHomeData()
      ]);
      setHomeItems(nextHomeItems);
      setTrendingItems(publicData.trendingItems);
      setTodaySchedule(publicData.todaySchedule);
      setCalendarDays(publicData.calendarDays);
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

  async function refreshCalendar(): Promise<void> {
    const publicData = await loadPublicHomeData();
    setTrendingItems(publicData.trendingItems);
    setTodaySchedule(publicData.todaySchedule);
    setCalendarDays(publicData.calendarDays);
  }

  async function updateTracking(input: TrackingMutation): Promise<void> {
    const result = await window.melonbang.bangumi.updateTracking(input);
    setSyncState(result.syncState);
    setHomeItems(await window.melonbang.bangumi.listCollection({ status: "watching" }));
  }

  async function listCollection(filter?: CollectionFilter): Promise<CollectionListItem[]> {
    return window.melonbang.bangumi.listCollection(filter);
  }

  const value = useMemo<AppStateValue>(
    () => ({
      session,
      syncState,
      isBootstrapping,
      homeItems,
      trendingItems,
      todaySchedule,
      calendarDays,
      refreshSession,
      signIn,
      signOut,
      listCollection,
      getSubject: (subjectId) => window.melonbang.bangumi.getSubject(subjectId),
      searchSubjects: (keyword) => window.melonbang.bangumi.searchSubjects(keyword),
      refreshCalendar,
      updateTracking,
      refreshCollection
    }),
    [calendarDays, homeItems, isBootstrapping, session, syncState, todaySchedule, trendingItems]
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
  calendarDays: BroadcastDay[];
}> {
  const [trendingItems, todaySchedule, calendarDays] = await Promise.all([
    window.melonbang.bangumi.getTrendingCurrent().catch(() => []),
    window.melonbang.bangumi.getTodaySchedule().catch(() => null),
    window.melonbang.bangumi.getCalendar().catch(() => [])
  ]);

  return { trendingItems, todaySchedule, calendarDays };
}
