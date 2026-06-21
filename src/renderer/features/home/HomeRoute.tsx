import { useState } from "react";
import { Bell, ChevronRight, PlayCircle, Sparkles } from "lucide-react";
import { Link } from "react-router-dom";
import type { TimelineItem } from "@/data/home";
import type { BroadcastDay } from "@shared/contracts/bangumi";
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
  const { calendarDays, syncState } = useAppState();
  const today = findToday(calendarDays);
  const todayItems = today ? toTimelineItems(today) : [];
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
            sub={today ? `${today.weekday.cn} · ${today.items.length} 部放送` : "正在读取放送表"}
            action={
              <Link
                to="/schedule"
                className="text-ink-faint hover:text-mint-500 inline-flex items-center gap-1 text-[12.5px] font-bold"
              >
                新番时间表 <ChevronRight className="size-4" />
              </Link>
            }
          />
          {todayItems.length > 0 ? (
            <Timeline items={todayItems} />
          ) : (
            <div className="border-line bg-surface text-ink-faint rounded-[20px] border p-8 text-center text-sm font-bold shadow-[var(--shadow-sm)]">
              今日暂无 Bangumi 放送数据。
            </div>
          )}
        </Section>
      </PageContent>
    </>
  );
}

function findToday(days: BroadcastDay[]): BroadcastDay | undefined {
  const todayId = bangumiWeekdayId(new Date());
  return days.find((day) => day.weekday.id === todayId);
}

function toTimelineItems(day: BroadcastDay): TimelineItem[] {
  return day.items.slice(0, 8).map((item) => ({
    time: "放送",
    index: item.subjectId,
    subjectId: item.subjectId,
    title: item.nameCn ?? item.name,
    total: item.episodeTotal,
    done: false,
    coverUrl: item.coverUrl,
    subtitle:
      typeof item.episodeTotal === "number" ? `今日放送 · 全 ${item.episodeTotal} 话` : "今日放送",
    badgeLabel: "今日放送",
    actionLabel: "详情"
  }));
}

function bangumiWeekdayId(date: Date): number {
  const day = date.getDay();
  return day === 0 ? 7 : day;
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
