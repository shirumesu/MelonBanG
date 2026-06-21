import { useState } from "react";
import { ArrowUpDown, Bookmark, CheckCircle2, Eye, PauseCircle, XCircle } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import {
  TRACKING_CARDS,
  TRACKING_COUNT_LABEL,
  TRACKING_FILTERS,
  TRACKING_TABS,
  type TrackingStatus
} from "@/data/tracking";
import { TrackingCard } from "./components/TrackingCard";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { PageContent, SearchBox, SyncPill, Topbar } from "@/components/melon/layout";
import { cn } from "@/lib/utils";

const TAB_ICONS: Record<TrackingStatus, LucideIcon> = {
  watching: Eye,
  wish: Bookmark,
  hold: PauseCircle,
  done: CheckCircle2,
  drop: XCircle
};

export function TrackingRoute() {
  const [status, setStatus] = useState<TrackingStatus>("watching");
  const [search, setSearch] = useState("");

  return (
    <>
      <Topbar title="追番" subtitle="我的 Bangumi 收藏 · 共 351 部">
        <SearchBox placeholder="在追番列表中搜索…" value={search} onChange={setSearch} />
        <Button variant="outline" size="sm">
          <ArrowUpDown className="size-4" />
          更新时间
        </Button>
        <SyncPill label="已同步 · 刚刚" />
      </Topbar>

      <PageContent>
        <div className="border-line bg-surface inline-flex gap-1 rounded-full border p-1.5 shadow-[var(--shadow-sm)]">
          {TRACKING_TABS.map((tab) => {
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
                    ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_5px_12px_rgba(34,179,136,.28)]"
                    : "text-ink-soft hover:text-ink"
                )}
              >
                <Icon className="size-4" />
                {tab.label}
                <span
                  className={cn(
                    "rounded-full px-[7px] text-[11px] font-extrabold",
                    active ? "text-on-accent bg-white/50" : "bg-surface-3 text-ink-faint"
                  )}
                >
                  {tab.count}
                </span>
              </button>
            );
          })}
        </div>

        <div className="mt-4 mb-2 flex flex-wrap items-center gap-2">
          <span className="text-ink-faint mr-0.5 text-xs font-bold">筛选</span>
          {TRACKING_FILTERS.map((filter, i) => (
            <Badge key={filter} variant={i === 0 ? "mint" : "outline"}>
              {filter}
            </Badge>
          ))}
          <div className="flex-1" />
          <span className="text-ink-faint text-xs">{TRACKING_COUNT_LABEL[status]}</span>
        </div>

        <div className="mt-3.5 grid gap-4 [grid-template-columns:repeat(auto-fill,minmax(168px,1fr))]">
          {TRACKING_CARDS[status].map((card, i) => (
            <TrackingCard key={`${status}-${i}`} status={status} card={card} />
          ))}
        </div>
      </PageContent>
    </>
  );
}
