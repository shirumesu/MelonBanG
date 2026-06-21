import { useState } from "react";
import { InteractiveRating } from "@/components/melon/RatingStars";
import { GradientAvatar } from "@/components/melon/GradientAvatar";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

type Tab = "comments" | "discussions";

export function SubjectTabs() {
  const [tab, setTab] = useState<Tab>("comments");

  return (
    <>
      <div className="border-line bg-surface mb-3.5 inline-flex gap-1 rounded-full border p-1.5 shadow-[var(--shadow-sm)]">
        {(
          [
            { key: "comments", label: "吐槽箱" },
            { key: "discussions", label: "讨论版" }
          ] as const
        ).map((entry) => {
          const active = entry.key === tab;
          return (
            <button
              key={entry.key}
              type="button"
              onClick={() => setTab(entry.key)}
              className={cn(
                "inline-flex items-center gap-1.5 rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                active
                  ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_5px_12px_rgba(34,179,136,.28)]"
                  : "text-ink-soft hover:text-ink"
              )}
            >
              {entry.label}
            </button>
          );
        })}
      </div>

      {tab === "comments" ? (
        <div>
          <div className="border-line-strong bg-surface-2 flex gap-3 rounded-[20px] border border-dashed p-4">
            <GradientAvatar initial="栞" />
            <div className="flex-1">
              <textarea
                placeholder="写下你的吐槽…"
                className="text-ink placeholder:text-ink-faint min-h-[84px] w-full resize-none bg-transparent text-sm outline-none"
              />
              <div className="mt-3 flex items-center gap-3">
                <div className="flex items-center gap-2">
                  <span className="text-ink-faint text-[13px] font-bold">评分</span>
                  <InteractiveRating />
                </div>
                <div className="flex-1" />
                <Button>发送吐槽</Button>
              </div>
            </div>
          </div>

          <div className="border-line bg-surface-2 text-ink-faint mt-3.5 rounded-[14px] border p-5 text-center text-sm font-semibold">
            暂未加载吐槽箱内容。
          </div>
        </div>
      ) : (
        <div className="border-line bg-surface-2 text-ink-faint rounded-[14px] border p-5 text-center text-sm font-semibold">
          暂未加载讨论内容。
        </div>
      )}
    </>
  );
}
