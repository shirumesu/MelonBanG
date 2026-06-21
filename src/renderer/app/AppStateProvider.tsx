import { createContext, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import type {
  BangumiSession,
  BroadcastDay,
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
  const [calendarDays, setCalendarDays] = useState<BroadcastDay[]>([]);
  const [isBootstrapping, setIsBootstrapping] = useState(true);

  useEffect(() => {
    void refreshSession();
  }, []);

  async function refreshSession(): Promise<void> {
    setIsBootstrapping(true);
    try {
      const [nextSession, nextSyncState] = await Promise.all([
        window.melonbang.bangumi.getSession(),
        window.melonbang.bangumi.getSyncState()
      ]);
      setSession(nextSession);
      setSyncState(nextSyncState);
      if (nextSession) {
        const [nextHomeItems, nextCalendarDays] = await Promise.all([
          window.melonbang.bangumi.listCollection({ status: "watching" }),
          window.melonbang.bangumi.getCalendar().catch(() => [])
        ]);
        setHomeItems(nextHomeItems);
        setCalendarDays(nextCalendarDays);
      } else {
        setHomeItems([]);
        setCalendarDays([]);
      }
    } catch (error) {
      setSession(null);
      setSyncState({
        stale: true,
        pendingMutationCount: 0,
        lastSyncError: errorMessage(error)
      });
      setHomeItems([]);
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
      const [nextHomeItems, nextCalendarDays] = await Promise.all([
        window.melonbang.bangumi.listCollection({ status: "watching" }),
        window.melonbang.bangumi.getCalendar().catch(() => [])
      ]);
      setHomeItems(nextHomeItems);
      setCalendarDays(nextCalendarDays);
    } catch (error) {
      setSession(null);
      setSyncState({
        stale: true,
        pendingMutationCount: 0,
        lastSyncError: errorMessage(error)
      });
      setHomeItems([]);
      setCalendarDays([]);
      throw error;
    }
  }

  async function signOut(): Promise<void> {
    await window.melonbang.bangumi.signOut();
    setSession(null);
    setSyncState(null);
    setHomeItems([]);
    setCalendarDays([]);
  }

  async function refreshCollection(force?: boolean): Promise<void> {
    const nextSyncState = await window.melonbang.bangumi.refreshCollection(force);
    setSyncState(nextSyncState);
    setHomeItems(await window.melonbang.bangumi.listCollection({ status: "watching" }));
  }

  async function refreshCalendar(): Promise<void> {
    setCalendarDays(await window.melonbang.bangumi.getCalendar());
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
    [calendarDays, homeItems, isBootstrapping, session, syncState]
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
