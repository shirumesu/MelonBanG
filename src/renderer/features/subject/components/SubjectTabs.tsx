import { useState } from "react";
import { ChevronRight, Plus, ThumbsUp } from "lucide-react";
import { SUBJECT_DEMO } from "@/data/subject";
import { InteractiveRating, StarRow } from "@/components/melon/RatingStars";
import { GradientAvatar } from "@/components/melon/GradientAvatar";
import { Badge } from "@/components/ui/badge";
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
            { key: "comments", label: "吐槽箱", count: "328" },
            { key: "discussions", label: "讨论版", count: "" }
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
              {entry.count ? (
                <span
                  className={cn(
                    "rounded-full px-[7px] text-[11px] font-extrabold",
                    active ? "text-on-accent bg-white/50" : "bg-surface-3 text-ink-faint"
                  )}
                >
                  {entry.count}
                </span>
              ) : null}
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

          <div>
            {SUBJECT_DEMO.comments.map((comment, i) => (
              <div
                key={comment.name}
                className={cn("flex gap-3 py-3.5", i > 0 && "border-line border-t")}
              >
                <GradientAvatar initial={comment.initial} gradient={comment.gradient} />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-bold">{comment.name}</span>
                    <StarRow value={comment.stars} size={12} />
                    <Badge
                      variant={comment.statusTag === "看过" ? "sky" : "mint"}
                      className="text-[10px]"
                    >
                      {comment.statusTag}
                    </Badge>
                    <span className="text-ink-faint ml-auto text-xs">{comment.time}</span>
                  </div>
                  <div className="text-ink mt-1.5 leading-[1.65]">{comment.text}</div>
                  <div className="text-ink-faint mt-2 flex items-center gap-4 text-xs font-semibold">
                    <span className="hover:text-mint-500 inline-flex cursor-pointer items-center gap-1.5">
                      <ThumbsUp className="size-3.5" /> {comment.likes}
                    </span>
                  </div>
                </div>
              </div>
            ))}
          </div>

          <div className="mt-3 text-center">
            <Button variant="outline" size="sm">
              查看更多吐槽
            </Button>
          </div>
        </div>
      ) : (
        <div>
          <div className="mb-2 flex items-center">
            <div className="flex-1" />
            <Button size="sm">
              <Plus className="size-4" />
              新讨论
            </Button>
          </div>
          <div>
            {SUBJECT_DEMO.discussions.map((discussion, i) => (
              <div
                key={discussion.title}
                className={cn(
                  "flex cursor-pointer items-center gap-2.5 py-[11px]",
                  i > 0 && "border-line border-t"
                )}
              >
                <span className="text-ink hover:text-mint-600 min-w-0 flex-1 truncate text-[13.5px] font-bold">
                  {discussion.title}
                </span>
                <span className="text-ink-faint text-xs whitespace-nowrap">
                  {discussion.author} · {discussion.replies} · {discussion.date}
                </span>
              </div>
            ))}
          </div>
          <div className="mt-3 text-center">
            <span className="text-ink-faint inline-flex cursor-pointer items-center justify-center gap-1 text-[12.5px] font-bold">
              更多讨论 <ChevronRight className="size-4" />
            </span>
          </div>
        </div>
      )}
    </>
  );
}
