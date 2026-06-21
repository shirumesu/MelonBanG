import { createContext, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import type {
  BangumiSession,
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
  refreshSession: () => Promise<void>;
  signIn: () => Promise<void>;
  signOut: () => Promise<void>;
  listCollection: (filter?: CollectionFilter) => Promise<CollectionListItem[]>;
  getSubject: (subjectId: number) => Promise<SubjectDetail>;
  searchSubjects: (keyword: string) => Promise<SubjectSearchResult[]>;
  updateTracking: (input: TrackingMutation) => Promise<void>;
  refreshCollection: (force?: boolean) => Promise<void>;
};

const AppStateContext = createContext<AppStateValue | null>(null);

export function AppStateProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<BangumiSession | null>(null);
  const [syncState, setSyncState] = useState<SyncState | null>(null);
  const [homeItems, setHomeItems] = useState<CollectionListItem[]>([]);
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
        setHomeItems(await window.melonbang.bangumi.listCollection({ status: "watching" }));
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
    } finally {
      setIsBootstrapping(false);
    }
  }

  async function signIn(): Promise<void> {
    try {
      const nextSession = await window.melonbang.bangumi.signIn();
      setSession(nextSession);
      setSyncState(await window.melonbang.bangumi.getSyncState());
      setHomeItems(await window.melonbang.bangumi.listCollection({ status: "watching" }));
    } catch (error) {
      setSession(null);
      setSyncState({
        stale: true,
        pendingMutationCount: 0,
        lastSyncError: errorMessage(error)
      });
      setHomeItems([]);
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
      refreshSession,
      signIn,
      signOut,
      listCollection,
      getSubject: (subjectId) => window.melonbang.bangumi.getSubject(subjectId),
      searchSubjects: (keyword) => window.melonbang.bangumi.searchSubjects(keyword),
      updateTracking,
      refreshCollection
    }),
    [homeItems, isBootstrapping, session, syncState]
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
