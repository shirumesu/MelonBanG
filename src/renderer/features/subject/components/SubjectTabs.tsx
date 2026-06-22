import { useState } from "react";
import type { SubjectComment as ApiSubjectComment, SubjectTopic } from "@shared/contracts/bangumi";
import { InteractiveRating } from "@/components/melon/RatingStars";
import { GradientAvatar } from "@/components/melon/GradientAvatar";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

type Tab = "comments" | "discussions";

export function SubjectTabs({
  comments,
  topics
}: {
  comments: ApiSubjectComment[];
  topics: SubjectTopic[];
}) {
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

          {comments.length > 0 ? (
            <div className="border-line bg-surface-2 mt-3.5 rounded-[14px] border p-4">
              <div className="space-y-3.5">
                {comments.map((comment, index) => (
                  <div
                    key={comment.id ?? `${comment.user.nickname}-${index}`}
                    className="flex gap-3"
                  >
                    <GradientAvatar
                      initial={comment.user.nickname.slice(0, 1)}
                      className="mt-0.5"
                      size="sm"
                    />
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        {comment.url ? (
                          <a
                            href={comment.url}
                            target="_blank"
                            rel="noreferrer"
                            className="hover:text-mint-600 text-[13px] font-extrabold"
                          >
                            {comment.user.nickname}
                          </a>
                        ) : (
                          <b className="text-[13px]">{comment.user.nickname}</b>
                        )}
                        {comment.status ? (
                          <span className="text-ink-faint text-[11px] font-bold">
                            {comment.status}
                          </span>
                        ) : null}
                        {typeof comment.score === "number" ? (
                          <span className="text-cherry-500 text-[11px] font-extrabold">
                            {comment.score} 分
                          </span>
                        ) : null}
                      </div>
                      <p className="text-ink-soft mt-1 text-[13px] leading-relaxed">
                        {comment.text}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <div className="border-line bg-surface-2 text-ink-faint mt-3.5 rounded-[14px] border p-5 text-center text-sm font-semibold">
              没有获取到吐槽箱数据。
            </div>
          )}
        </div>
      ) : (
        <>
          {topics.length > 0 ? (
            <div className="border-line bg-surface-2 rounded-[14px] border p-[18px]">
              <div className="space-y-3.5">
                {topics.map((topic, index) => (
                  <div
                    key={topic.topicId ?? `${topic.title}-${index}`}
                    className="border-line border-b pb-3.5 last:border-b-0 last:pb-0"
                  >
                    {topic.url ? (
                      <a
                        href={topic.url}
                        target="_blank"
                        rel="noreferrer"
                        className="text-ink hover:text-mint-600 text-[15px] leading-snug font-bold"
                      >
                        {topic.title}
                      </a>
                    ) : (
                      <div className="text-ink text-[15px] leading-snug font-bold">
                        {topic.title}
                      </div>
                    )}
                    <div className="text-ink-faint mt-1.5 text-[12.5px] leading-relaxed font-medium">
                      {[
                        topic.author,
                        typeof topic.replies === "number" ? `${topic.replies} 回复` : null,
                        typeof topic.replies !== "number" ? topic.updatedAt : null
                      ]
                        .filter(Boolean)
                        .join(" · ")}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <div className="border-line bg-surface-2 text-ink-faint rounded-[14px] border p-5 text-center text-sm font-semibold">
              暂未加载讨论内容。
            </div>
          )}
        </>
      )}
    </>
  );
}
