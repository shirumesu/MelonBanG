import { useState } from "react";
import { Bell, ChevronRight, PlayCircle, Sparkles } from "lucide-react";
import { Link } from "react-router-dom";
import { TODAY_ITEMS, TODAY_SUBTITLE } from "@/data/home";
import { useAppState } from "@/app/AppStateProvider";
import { HeroCarousel } from "./components/HeroCarousel";
import { ContinueRail } from "./components/ContinueRail";
import { Timeline } from "@/components/melon/Timeline";
import {
  IconButton,
  PageContent,
  SearchBox,
  Section,
  SectionHead,
  SyncPill,
  Topbar
} from "@/components/melon/layout";

export function HomeRoute() {
  const [search, setSearch] = useState("");
  const { syncState } = useAppState();
  const syncLabel = syncState?.lastSuccessfulSyncAt
    ? `已同步 · ${formatRelativeTime(syncState.lastSuccessfulSyncAt)}`
    : syncState?.stale
      ? "缓存离线"
      : "等待同步";

  return (
    <>
      <Topbar title="探索" subtitle="Bangumi 收藏与放送动态">
        <SearchBox
          className="min-w-[280px]"
          placeholder="搜索番剧、角色、制作公司…"
          value={search}
          onChange={setSearch}
        />
        <SyncPill stale={syncState?.stale} label={syncLabel} />
        <IconButton badge={5}>
          <Bell />
        </IconButton>
      </Topbar>

      <PageContent>
        <HeroCarousel />

        <Section>
          <SectionHead
            title={
              <>
                <PlayCircle className="text-mint-500 size-[19px]" />
                继续播放
              </>
            }
            sub="接着上次看"
          />
          <ContinueRail />
        </Section>

        <Section>
          <SectionHead
            title={
              <>
                <Sparkles className="text-cherry-500 size-[19px]" />
                今日更新
              </>
            }
            sub={TODAY_SUBTITLE}
            action={
              <Link
                to="/schedule"
                className="text-ink-faint hover:text-mint-500 inline-flex items-center gap-1 text-[12.5px] font-bold"
              >
                新番时间表 <ChevronRight className="size-4" />
              </Link>
            }
          />
          <Timeline items={TODAY_ITEMS} />
        </Section>
      </PageContent>
    </>
  );
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
