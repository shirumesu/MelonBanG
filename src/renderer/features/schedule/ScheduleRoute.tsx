import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ChevronLeft, Inbox, SlidersHorizontal } from "lucide-react";
import type { TimelineItem } from "@/data/home";
import type { BroadcastDay } from "@shared/contracts/bangumi";
import { useAppState } from "@/app/AppStateProvider";
import { Timeline } from "@/components/melon/Timeline";
import { IconButton, SearchBox, Topbar } from "@/components/melon/layout";
import { Button } from "@/components/ui/button";
import { parseAiringTimestamp } from "@/lib/airing";
import { cn } from "@/lib/utils";

export function ScheduleRoute() {
  const navigate = useNavigate();
  const { calendarDays } = useAppState();
  const week = useMemo(() => calendarDaysToWeek(calendarDays), [calendarDays]);
  const todayIndex = useMemo(() => findTodayIndex(week), [week]);
  const [selected, setSelected] = useState(todayIndex);
  const day = week[selected] ?? week[todayIndex] ?? emptyToday();

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <Topbar
        title="新番时间表"
        subtitle={`${currentSeasonLabel()} · 每周放送`}
        leading={
          <IconButton onClick={() => void navigate("/home")}>
            <ChevronLeft />
          </IconButton>
        }
      >
        <SearchBox placeholder="搜索新番…" />
        <Button variant="outline" size="sm">
          <SlidersHorizontal className="size-4" />
          筛选
        </Button>
      </Topbar>

      <div className="border-line bg-surface-2 flex gap-[7px] overflow-x-auto border-b px-[26px] py-4">
        {week.map((entry, i) => {
          const active = i === selected;
          return (
            <button
              key={entry.en}
              type="button"
              onClick={() => setSelected(i)}
              className={cn(
                "w-[88px] flex-none cursor-pointer rounded-[14px] border-[1.5px] px-2 py-3 text-center text-[13.5px] font-bold transition",
                active
                  ? "border-transparent bg-[linear-gradient(135deg,var(--cherry-400),var(--cherry-500))] text-white shadow-[0_8px_16px_rgba(255,107,129,.28)]"
                  : "border-line bg-surface text-ink hover:border-mint-200"
              )}
            >
              {entry.day}
              <span className="mt-0.5 block text-[11px] font-semibold uppercase opacity-75">
                {entry.en}
              </span>
              <span className="mt-1 block text-[10px] font-extrabold opacity-65">
                {entry.items.length} 部
              </span>
            </button>
          );
        })}
      </div>

      <div className="flex-1 overflow-auto">
        <div className="flex items-center gap-3.5 px-[26px] pt-[22px] pb-3">
          <h2 className="text-xl font-extrabold">
            {day.day}
            {selected === todayIndex ? " · 今天" : ""}
          </h2>
          <span className="text-ink-faint text-[13px] font-semibold">
            {day.items.length === 0 ? "本日无放送" : `${day.items.length} 部放送`}
          </span>
        </div>

        <div className="px-[26px] pb-10">
          {day.items.length === 0 ? (
            <div className="text-ink-faint flex flex-col items-center justify-center py-20 text-center">
              <Inbox className="size-14" />
              <b className="text-ink-soft mt-3 text-base">本日暂无新番放送</b>
              <p className="mt-1.5 text-[13px]">选择其他日期查看新番时间表</p>
            </div>
          ) : (
            <Timeline items={day.items} variant="schedule" />
          )}
        </div>
      </div>
    </div>
  );
}

type WeekDay = {
  day: string;
  en: string;
  weekdayId: number;
  items: TimelineItem[];
};

const FALLBACK_WEEKDAYS: WeekDay[] = [
  { day: "周一", en: "MON", weekdayId: 1, items: [] },
  { day: "周二", en: "TUE", weekdayId: 2, items: [] },
  { day: "周三", en: "WED", weekdayId: 3, items: [] },
  { day: "周四", en: "THU", weekdayId: 4, items: [] },
  { day: "周五", en: "FRI", weekdayId: 5, items: [] },
  { day: "周六", en: "SAT", weekdayId: 6, items: [] },
  { day: "周日", en: "SUN", weekdayId: 7, items: [] }
];

function calendarDaysToWeek(days: BroadcastDay[]): WeekDay[] {
  if (days.length === 0) {
    return FALLBACK_WEEKDAYS;
  }

  const byId = new Map(days.map((day) => [day.weekday.id, day]));
  return FALLBACK_WEEKDAYS.map((fallback) => {
    const day = byId.get(fallback.weekdayId);
    if (!day) {
      return fallback;
    }

    return {
      day: day.weekday.cn.replace("星期", "周"),
      en: day.weekday.en.toUpperCase(),
      weekdayId: day.weekday.id,
      items: toTimelineItems(day)
    };
  });
}

function toTimelineItems(day: BroadcastDay): TimelineItem[] {
  const now = Date.now();
  const todayKey = shanghaiDateKey(new Date());

  return day.items.map((item, index) => {
    const airingTimestamp = parseAiringTimestamp(item.airingAtShanghai ?? item.airingAt);
    const done = Number.isFinite(airingTimestamp) && airingTimestamp <= now;
    const isToday = item.airingAtShanghai?.slice(0, 10) === todayKey;
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
        typeof item.episodeTotal === "number"
          ? `${day.weekday.cn}放送 · 全 ${item.episodeTotal} 话`
          : `${day.weekday.cn}放送`,
      badgeLabel: isToday ? (done ? "已放送" : "今日放送") : done ? "本周已放送" : "待放送",
      actionLabel: "详情"
    };
  });
}

function formatAiringTime(value: string | undefined): string {
  return value?.slice(11, 16) || "放送";
}

function findTodayIndex(week: WeekDay[]): number {
  const todayId = bangumiWeekdayId(new Date());
  const index = week.findIndex((day) => day.weekdayId === todayId);
  return index >= 0 ? index : 0;
}

function emptyToday(): WeekDay {
  return FALLBACK_WEEKDAYS[findTodayIndex(FALLBACK_WEEKDAYS)];
}

function bangumiWeekdayId(date: Date): number {
  const day = date.getDay();
  return day === 0 ? 7 : day;
}

function shanghaiDateKey(date: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).format(date);
}

function currentSeasonLabel(date = new Date()): string {
  const year = date.getFullYear();
  const month = date.getMonth() + 1;
  if (month >= 10) {
    return `${year} 秋季`;
  }
  if (month >= 7) {
    return `${year} 夏季`;
  }
  if (month >= 4) {
    return `${year} 春季`;
  }
  return `${year} 冬季`;
}
