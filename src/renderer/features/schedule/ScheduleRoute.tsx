import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { ChevronLeft, Inbox, SlidersHorizontal } from "lucide-react";
import { TODAY_INDEX, WEEK } from "@/data/schedule";
import { Timeline } from "@/components/melon/Timeline";
import { IconButton, SearchBox, Topbar } from "@/components/melon/layout";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export function ScheduleRoute() {
  const navigate = useNavigate();
  const [selected, setSelected] = useState(TODAY_INDEX);
  const day = WEEK[selected];

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
        {WEEK.map((entry, i) => {
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
            {selected === TODAY_INDEX ? " · 今天" : ""}
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
            <Timeline items={day.items} />
          )}
        </div>
      </div>
    </div>
  );
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
