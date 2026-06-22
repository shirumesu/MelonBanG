import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { Eye, Play } from "lucide-react";
import type { TimelineItem } from "@/data/home";
import { artGradient, artKanji } from "@/data/artwork";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { parseAiringTimestamp } from "@/lib/airing";
import { cn } from "@/lib/utils";

type TimelineVariant = "home" | "schedule";

const timelineVariants: Record<
  TimelineVariant,
  {
    card: string;
    poster: string;
    title: string;
    subtitle: string;
    time: string;
    nowTime: string;
  }
> = {
  home: {
    card: "my-2 gap-4 px-4 py-3.5",
    poster: "h-[128px] w-[96px] rounded-[14px]",
    title: "text-base",
    subtitle: "mt-1 text-[13px]",
    time: "w-[56px] text-sm",
    nowTime: "w-[56px] text-[12.5px]"
  },
  schedule: {
    card: "my-2.5 gap-5 px-[18px] py-4",
    poster: "h-[150px] w-[112px] rounded-[16px]",
    title: "text-[17px]",
    subtitle: "mt-1.5 text-[13px]",
    time: "w-[60px] text-[14px]",
    nowTime: "w-[60px] text-[12.5px]"
  }
};

function RowMeta({ item, isNext, done }: { item: TimelineItem; isNext: boolean; done: boolean }) {
  const badgeLabel =
    item.badgeLabel && !(done && /今日放送|待放送/.test(item.badgeLabel))
      ? item.badgeLabel
      : done
        ? `已放送${typeof item.ep === "number" ? ` EP${item.ep}` : ""}`
        : `${isNext ? "即将" : "待播"}${typeof item.ep === "number" ? ` · EP${item.ep}` : ""}`;

  if (done) {
    return (
      <>
        <Badge variant="mint">{badgeLabel}</Badge>
        <Button variant="soft" size="sm">
          <Play className="size-4 fill-current" />
          {item.actionLabel ?? "播放"}
        </Button>
      </>
    );
  }
  return (
    <>
      <Badge variant={isNext ? "cherry" : "outline"}>{badgeLabel}</Badge>
      <Button variant="outline" size="sm">
        <Eye className="size-4" />
        {item.actionLabel ?? "提醒我"}
      </Button>
    </>
  );
}

function TimelineRow({
  item,
  isNext,
  done,
  connectBefore,
  connectAfter,
  variant
}: {
  item: TimelineItem;
  isNext: boolean;
  done: boolean;
  connectBefore: boolean;
  connectAfter: boolean;
  variant: TimelineVariant;
}) {
  const size = timelineVariants[variant];
  const cardClass = cn(
    "group border-line bg-surface flex flex-1 items-center rounded-[14px] border shadow-[var(--shadow-sm)] transition hover:translate-x-[3px] hover:shadow-[var(--shadow-md)]",
    size.card,
    isNext
      ? "border-cherry-300 shadow-[0_6px_16px_rgba(255,107,129,.16)]"
      : "hover:border-mint-200"
  );
  const content = (
    <>
      <span
        className={cn("relative flex-none overflow-hidden shadow-[var(--shadow-sm)]", size.poster)}
        style={{ background: artGradient(item.index) }}
      >
        {item.coverUrl ? (
          <img
            src={item.coverUrl}
            alt=""
            className="absolute inset-0 size-full object-cover"
            loading="lazy"
          />
        ) : (
          <span className="absolute inset-0 grid place-items-center text-3xl font-extrabold text-white/35">
            {artKanji(item.index)}
          </span>
        )}
        <span className="absolute inset-0 grid place-items-center bg-black/35 text-white opacity-0 transition group-hover:opacity-100">
          <Play className="size-4 fill-current" />
        </span>
      </span>
      <div className="min-w-0 flex-1">
        <b className={cn("line-clamp-2 block font-bold leading-snug", size.title)}>
          {item.title}
        </b>
        <div className={cn("text-ink-faint line-clamp-2 font-semibold leading-relaxed", size.subtitle)}>
          {item.subtitle ??
            (done
              ? `已放送${typeof item.ep === "number" ? ` · 更新至 EP${item.ep}` : ""}`
              : `即将放送${typeof item.total === "number" ? ` · 全${item.total}话` : ""}`)}
        </div>
      </div>
      <div className="flex flex-none items-center gap-2.5">
        <RowMeta item={item} isNext={isNext} done={done} />
      </div>
    </>
  );

  return (
    <div className="flex items-stretch gap-3.5">
      <div
        className={
          cn(
            "flex flex-none items-center justify-end font-extrabold tabular-nums",
            size.time,
            done ? "text-ink-faint" : "text-mint-600"
          )
        }
      >
        {item.time}
      </div>

      <div className="relative flex w-4 flex-none items-center justify-center">
        <span
          className="bg-line-strong absolute left-1/2 w-0.5 -translate-x-1/2"
          style={{ top: connectBefore ? 0 : "50%", bottom: connectAfter ? 0 : "50%" }}
        />
        <span
          className="bg-surface relative z-[1] size-[13px] rounded-full border-[2.5px] shadow-[0_0_0_4px_var(--bg)]"
          style={
            isNext
              ? {
                  borderColor: "var(--cherry-500)",
                  boxShadow: "0 0 0 4px var(--bg),0 0 0 7px rgba(255,107,129,.18)"
                }
              : {
                  borderColor: "var(--mint-400)",
                  background: done ? "var(--mint-400)" : "var(--surface)"
                }
          }
        />
      </div>

      {typeof item.subjectId === "number" ? (
        <Link to={`/subject/${item.subjectId}`} className={cardClass}>
          {content}
        </Link>
      ) : (
        <div className={cardClass}>{content}</div>
      )}
    </div>
  );
}

function NowMarker({
  now,
  connectBefore,
  connectAfter,
  variant
}: {
  now: Date;
  connectBefore: boolean;
  connectAfter: boolean;
  variant: TimelineVariant;
}) {
  const size = timelineVariants[variant];
  return (
    <div className="flex items-stretch gap-3.5 py-1">
      <div
        className={cn(
          "text-cherry-500 flex flex-none items-center justify-end font-extrabold tabular-nums",
          size.nowTime
        )}
      >
        {formatShanghaiTime(now)}
      </div>
      <div className="relative flex w-4 flex-none items-center justify-center">
        <span
          className="bg-line-strong absolute left-1/2 w-0.5 -translate-x-1/2"
          style={{ top: connectBefore ? 0 : "50%", bottom: connectAfter ? 0 : "50%" }}
        />
        <span className="bg-cherry-400 relative z-[1] size-[11px] rounded-full shadow-[0_0_0_4px_var(--bg),0_0_0_8px_rgba(255,107,129,.18)]" />
      </div>
      <div className="flex flex-1 items-center">
        <span className="border-cherry-200 bg-cherry-50 text-cherry-500 rounded-full border px-3 py-1 text-[11px] font-extrabold shadow-[var(--shadow-sm)]">
          现在
        </span>
      </div>
    </div>
  );
}

export function Timeline({
  items,
  variant = "home"
}: {
  items: TimelineItem[];
  variant?: TimelineVariant;
}) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 60 * 1000);
    return () => window.clearInterval(timer);
  }, []);

  const nextIndex = items.findIndex((item) => !isTimelineItemDone(item, now));
  const nowIndex = useMemo(() => nowMarkerIndex(items, now), [items, now]);
  return (
    <div className="flex flex-col">
      {nowIndex === 0 ? (
        <NowMarker now={now} connectBefore={false} connectAfter variant={variant} />
      ) : null}
      {items.map((item, i) => (
        <div key={`${item.time}-${item.index}-${i}`}>
          <TimelineRow
            item={item}
            isNext={i === nextIndex}
            done={isTimelineItemDone(item, now)}
            connectBefore={i > 0 || nowIndex === 0}
            connectAfter={i < items.length - 1 || nowIndex === items.length}
            variant={variant}
          />
          {nowIndex === i + 1 ? (
            <NowMarker
              now={now}
              connectBefore
              connectAfter={nowIndex < items.length}
              variant={variant}
            />
          ) : null}
        </div>
      ))}
    </div>
  );
}

function isTimelineItemDone(item: TimelineItem, now: Date): boolean {
  const timestamp = parseAiringTimestamp(item.airingAtShanghai ?? item.airingAt);
  return item.done || (Number.isFinite(timestamp) && timestamp <= now.getTime());
}

function nowMarkerIndex(items: TimelineItem[], now: Date): number | null {
  const today = shanghaiDateKey(now);
  const times = items.map((item, index) => ({
    index,
    timestamp: parseAiringTimestamp(item.airingAtShanghai ?? item.airingAt),
    dateKey: shanghaiDateKeyFromAiring(item.airingAtShanghai ?? item.airingAt)
  }));
  const todayTimes = times.filter(
    (entry): entry is { index: number; timestamp: number; dateKey: string } =>
      entry.dateKey === today && Number.isFinite(entry.timestamp)
  );

  if (todayTimes.length === 0) {
    return null;
  }

  const nowTimestamp = now.getTime();
  const next = todayTimes.find((entry) => entry.timestamp > nowTimestamp);
  if (next) {
    return next.index;
  }

  return todayTimes[todayTimes.length - 1].index + 1;
}

function shanghaiDateKeyFromAiring(value: string | undefined): string | null {
  if (!value) {
    return null;
  }

  const shanghaiMatch = /^(\d{4}-\d{2}-\d{2}) /.exec(value);
  if (shanghaiMatch) {
    return shanghaiMatch[1];
  }

  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? shanghaiDateKey(new Date(timestamp)) : null;
}

function shanghaiDateKey(date: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).format(date);
}

function formatShanghaiTime(date: Date): string {
  return new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23"
  }).format(date);
}
