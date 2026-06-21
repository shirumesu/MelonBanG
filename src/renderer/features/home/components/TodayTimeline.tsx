import { Bell, Play } from "lucide-react";
import { Link } from "react-router-dom";
import type { CollectionListItem } from "@shared/contracts/bangumi";
import { ArtworkCard } from "@/components/melon/artwork";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

const scheduleTimes = ["02:00", "12:30", "19:00", "22:00", "23:30", "24:00"];

export function TodayTimeline({ items }: { items: CollectionListItem[] }): JSX.Element {
  return (
    <div className="flex flex-col">
      {items.slice(0, 6).map((item, index) => {
        const isAired = index < 3;
        const isNext = index === 3;
        return (
          <div key={item.subjectId} className="flex items-stretch gap-4">
            <div
              className={`flex w-[52px] items-center justify-end text-[13px] font-black ${isAired ? "text-muted-foreground" : "text-[var(--mint-600)]"}`}
            >
              {scheduleTimes[index] ?? "22:00"}
            </div>
            <div className="relative flex w-4 items-center justify-center">
              <div className="absolute inset-y-0 left-1/2 w-0.5 -translate-x-1/2 bg-[var(--line-strong)]" />
              <div
                className={`relative z-10 size-3 rounded-full border-[2.5px] ${isNext ? "bg-card border-[var(--cherry-500)] shadow-[0_0_0_7px_rgba(255,107,129,.18)]" : isAired ? "border-[var(--mint-400)] bg-[var(--mint-400)]" : "bg-card border-[var(--mint-400)]"} shadow-[0_0_0_4px_var(--background)]`}
              />
            </div>
            <Link
              to={`/subject/${item.subjectId}`}
              className={`bg-card my-1 flex flex-1 items-center gap-3 rounded-[14px] border px-4 py-3 shadow-[var(--shadow-sm)] transition hover:translate-x-1 hover:border-[var(--mint-200)] ${isNext ? "border-[var(--cherry-300)] shadow-[0_6px_16px_rgba(255,107,129,.16)]" : "border-border"}`}
            >
              <div className="w-[42px] flex-none">
                <ArtworkCard
                  id={item.subjectId}
                  title={item.nameCn ?? item.name}
                  className="aspect-[3/4] rounded-[9px]"
                  overlay={false}
                />
              </div>
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-black">{item.nameCn ?? item.name}</div>
                <div className="text-muted-foreground mt-1 text-xs font-semibold">
                  {isAired
                    ? `已放送 · 更新至 EP${item.nextEpisode?.sort ?? 1}`
                    : `即将放送 · 全 ${item.episodeTotal ?? "?"} 话`}
                </div>
              </div>
              <div className="flex items-center gap-3">
                {isAired ? (
                  <Badge variant="mint">已更新 EP{item.nextEpisode?.sort ?? 1}</Badge>
                ) : isNext ? (
                  <Badge variant="cherry">即将放送</Badge>
                ) : (
                  <Badge variant="outline">待播</Badge>
                )}
                {isAired ? (
                  <Button variant="secondary" size="sm">
                    <Play className="size-4 fill-current" />
                    播放
                  </Button>
                ) : (
                  <Button variant="ghost" size="sm">
                    <Bell className="size-4" />
                    提醒我
                  </Button>
                )}
              </div>
            </Link>
          </div>
        );
      })}
    </div>
  );
}
