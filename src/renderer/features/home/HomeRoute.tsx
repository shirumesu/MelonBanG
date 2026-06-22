import { useState } from "react";
import { Bell, ChevronRight, Flame, PlayCircle, Sparkles } from "lucide-react";
import { Link } from "react-router-dom";
import type { TimelineItem } from "@/data/home";
import type { BroadcastDay } from "@shared/contracts/bangumi";
import { useAppState } from "@/app/AppStateProvider";
import { TrendingRail } from "./components/TrendingRail";
import { ContinueRail } from "./components/ContinueRail";
import { Timeline } from "@/components/melon/Timeline";
import { parseAiringTimestamp } from "@/lib/airing";
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
  const { calendarDays, syncState, todaySchedule, trendingItems } = useAppState();
  const today = todaySchedule ?? findToday(calendarDays);
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
        <Section>
          <SectionHead
            title={
              <>
                <Flame className="text-cherry-500 size-[19px]" />
                本季热度
              </>
            }
            sub="当季最受欢迎的番剧"
          />
          <TrendingRail items={trendingItems} />
        </Section>

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
            <Timeline items={todayItems} variant="home" />
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
  const now = Date.now();
  return day.items.map((item, index) => {
    const airingTimestamp = parseAiringTimestamp(item.airingAtShanghai ?? item.airingAt);
    const done = Number.isFinite(airingTimestamp) && airingTimestamp <= now;
    return {
      time: formatAiringTime(item.airingAtShanghai),
      airingAt: item.airingAt,
      airingAtShanghai: item.airingAtShanghai,
      index: item.subjectId ?? index + 1,
      subjectId: item.subjectId,
      title: item.displayName ?? item.nameCn ?? item.name,
      total: item.episodeTotal,
      done,
      coverUrl: item.coverUrl,
      subtitle:
        typeof item.episodeTotal === "number" ? `今日放送 · 全 ${item.episodeTotal} 话` : "今日放送",
      badgeLabel: done ? "已放送" : "今日放送",
      actionLabel: "详情"
    };
  });
}

function formatAiringTime(value: string | undefined): string {
  return value?.slice(11, 16) || "放送";
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
