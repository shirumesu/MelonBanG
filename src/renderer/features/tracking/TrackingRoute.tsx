import { useDeferredValue, useEffect, useMemo, useState } from "react";
import {
  ArrowDownWideNarrow,
  Bookmark,
  CheckCircle2,
  Eye,
  PauseCircle,
  RefreshCw,
  XCircle
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import type { CollectionListItem, CollectionStatus } from "@shared/contracts/bangumi";
import { useAppState } from "@/app/AppStateProvider";
import { PosterCard } from "./components/PosterCard";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { PageContent, SearchBox, SyncPill, Topbar } from "@/components/melon/layout";
import { cn } from "@/lib/utils";

type QuickFilter = "all" | "progress" | "rated" | "pending";
type SortKey = "updated" | "score";

const STATUS_TABS: Array<{ key: CollectionStatus; label: string }> = [
  { key: "watching", label: "在看" },
  { key: "wish", label: "想看" },
  { key: "on_hold", label: "搁置" },
  { key: "completed", label: "看过" },
  { key: "dropped", label: "抛弃" }
];

const QUICK_FILTERS: Array<{ key: QuickFilter; label: string }> = [
  { key: "all", label: "全部" },
  { key: "progress", label: "有进度" },
  { key: "rated", label: "已评分" },
  { key: "pending", label: "待同步" }
];

const TAB_ICONS: Record<CollectionStatus, LucideIcon> = {
  watching: Eye,
  wish: Bookmark,
  on_hold: PauseCircle,
  completed: CheckCircle2,
  dropped: XCircle
};

export function TrackingRoute() {
  const { listCollection, refreshCollection, syncState } = useAppState();
  const [status, setStatus] = useState<CollectionStatus>("watching");
  const [quickFilter, setQuickFilter] = useState<QuickFilter>("all");
  const [sortKey, setSortKey] = useState<SortKey>("updated");
  const [search, setSearch] = useState("");
  const deferredSearch = useDeferredValue(search);
  const [items, setItems] = useState<CollectionListItem[] | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => {
    let ignore = false;

    void listCollection().then((nextItems) => {
      if (!ignore) {
        setItems(nextItems);
      }
    });

    return () => {
      ignore = true;
    };
  }, [listCollection]);

  async function refresh(): Promise<void> {
    setRefreshing(true);
    try {
      await refreshCollection(true);
      setItems(await listCollection());
    } finally {
      setRefreshing(false);
    }
  }

  const collectionItems = useMemo(() => items ?? [], [items]);
  const loading = items === null;

  const counts = useMemo(() => {
    const next: Record<CollectionStatus, number> = {
      watching: 0,
      wish: 0,
      on_hold: 0,
      completed: 0,
      dropped: 0
    };

    for (const item of collectionItems) {
      next[item.collection.status] += 1;
    }

    return next;
  }, [collectionItems]);

  const visibleItems = useMemo(() => {
    const loweredSearch = deferredSearch.trim().toLowerCase();
    return collectionItems
      .filter((item) => item.collection.status === status)
      .filter((item) => matchesSearch(item, loweredSearch))
      .filter((item) => matchesQuickFilter(item, quickFilter))
      .sort((left, right) => compareItems(left, right, sortKey));
  }, [collectionItems, deferredSearch, quickFilter, sortKey, status]);

  const syncLabel = syncState?.lastSuccessfulSyncAt
    ? `已同步 · ${formatRelativeTime(syncState.lastSuccessfulSyncAt)}`
    : syncState?.stale
      ? "缓存离线"
      : "等待同步";

  return (
    <>
      <Topbar title="追番" subtitle={`我的 Bangumi 动画收藏 · 已缓存 ${collectionItems.length} 部`}>
        <SearchBox placeholder="在追番列表中搜索…" value={search} onChange={setSearch} />
        <Button
          variant="outline"
          size="sm"
          onClick={() => setSortKey((value) => (value === "updated" ? "score" : "updated"))}
        >
          <ArrowDownWideNarrow className="size-4" />
          {sortKey === "updated" ? "更新时间" : "评分"}
        </Button>
        <Button variant="outline" size="sm" onClick={() => void refresh()} disabled={refreshing}>
          <RefreshCw className={cn("size-4", refreshing && "animate-spin")} />
          刷新
        </Button>
        <SyncPill stale={syncState?.stale} label={syncLabel} />
      </Topbar>

      <PageContent>
        <div className="border-line bg-surface inline-flex gap-1 rounded-full border p-1.5 shadow-[var(--shadow-sm)]">
          {STATUS_TABS.map((tab) => {
            const Icon = TAB_ICONS[tab.key];
            const active = tab.key === status;
            return (
              <button
                key={tab.key}
                type="button"
                onClick={() => setStatus(tab.key)}
                className={cn(
                  "inline-flex items-center gap-1.5 rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                  active
                    ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_4px_10px_rgba(34,179,136,.22)]"
                    : "text-ink-soft hover:text-ink"
                )}
              >
                <Icon className="size-[17px] opacity-90" />
                {tab.label}
                <span
                  className={cn(
                    "ml-0.5 rounded-full px-[7px] py-px text-[10.5px] font-extrabold",
                    active ? "text-on-accent bg-white/40" : "bg-surface-3 text-ink-faint"
                  )}
                >
                  {counts[tab.key]}
                </span>
              </button>
            );
          })}
        </div>

        <div className="mt-4 mb-2 flex flex-wrap items-center gap-2">
          <span className="text-ink-faint mr-0.5 text-xs font-bold">筛选</span>
          {QUICK_FILTERS.map((filter) => (
            <button key={filter.key} type="button" onClick={() => setQuickFilter(filter.key)}>
              <Badge variant={quickFilter === filter.key ? "mint" : "outline"}>
                {filter.label}
              </Badge>
            </button>
          ))}
          <div className="flex-1" />
          <span className="text-ink-faint text-xs">
            {loading ? "加载中…" : `${visibleItems.length} 部`}
          </span>
        </div>

        {loading ? (
          <div className="text-ink-faint mt-16 text-center text-sm font-bold">正在读取收藏…</div>
        ) : visibleItems.length > 0 ? (
          <div className="mt-3.5 grid [grid-template-columns:repeat(auto-fill,minmax(168px,1fr))] gap-4">
            {visibleItems.map((item) => (
              <PosterCard key={item.subjectId} item={item} />
            ))}
          </div>
        ) : (
          <div className="border-line bg-surface text-ink-faint mt-10 rounded-[20px] border p-10 text-center text-sm font-bold shadow-[var(--shadow-sm)]">
            当前筛选下没有收藏条目。
          </div>
        )}
      </PageContent>
    </>
  );
}

function matchesSearch(item: CollectionListItem, loweredSearch: string): boolean {
  if (!loweredSearch) {
    return true;
  }

  return [item.name, item.nameCn, item.summary, item.nextEpisode?.name, item.nextEpisode?.nameCn]
    .filter(Boolean)
    .some((value) => value?.toLowerCase().includes(loweredSearch));
}

function matchesQuickFilter(item: CollectionListItem, quickFilter: QuickFilter): boolean {
  if (quickFilter === "progress") {
    return Boolean(item.nextEpisode || item.watchedEpisodeCount);
  }
  if (quickFilter === "rated") {
    return Boolean(item.collection.score);
  }
  if (quickFilter === "pending") {
    return item.pendingMutationKeys.length > 0;
  }
  return true;
}

function compareItems(
  left: CollectionListItem,
  right: CollectionListItem,
  sortKey: SortKey
): number {
  if (sortKey === "score") {
    return (right.collection.score ?? 0) - (left.collection.score ?? 0);
  }

  return Date.parse(right.collection.updatedAt) - Date.parse(left.collection.updatedAt);
}

function formatRelativeTime(value: string): string {
  const timestamp = Date.parse(value);
  if (Number.isNaN(timestamp)) {
    return "刚刚";
  }

  const diffSeconds = Math.round((timestamp - Date.now()) / 1000);
  const units: Array<[Intl.RelativeTimeFormatUnit, number]> = [
    ["year", 60 * 60 * 24 * 365],
    ["month", 60 * 60 * 24 * 30],
    ["day", 60 * 60 * 24],
    ["hour", 60 * 60],
    ["minute", 60],
    ["second", 1]
  ];
  const formatter = new Intl.RelativeTimeFormat("zh-CN", { numeric: "auto" });

  for (const [unit, seconds] of units) {
    if (Math.abs(diffSeconds) >= seconds || unit === "second") {
      return formatter.format(Math.round(diffSeconds / seconds), unit);
    }
  }

  return "刚刚";
}
