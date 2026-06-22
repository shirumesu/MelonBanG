import { useState } from "react";
import type { SubjectComment as ApiSubjectComment, SubjectTopic } from "@shared/contracts/bangumi";
import { InteractiveRating } from "@/components/melon/RatingStars";
import { ReadOnlyRating } from "@/components/melon/ReadOnlyRating";
import { GradientAvatar } from "@/components/melon/GradientAvatar";
import { Button } from "@/components/ui/button";
import { Clock, MessageCircle, User } from "lucide-react";
import { cn } from "@/lib/utils";

type Tab = "comments" | "discussions";

export function SubjectTabs({
  comments,
  topics,
  loading = false
}: {
  comments: ApiSubjectComment[];
  topics: SubjectTopic[];
  loading?: boolean;
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
            <div className="mt-3.5 space-y-3">
              {comments.map((comment, index) => (
                <div
                  key={comment.id ?? `${comment.user.nickname}-${index}`}
                  className="border-line bg-surface flex gap-3.5 rounded-[16px] border p-4 shadow-[var(--shadow-xs)] transition-shadow hover:shadow-[var(--shadow-sm)]"
                >
                  {comment.user.avatarUrl ? (
                    <img
                      src={comment.user.avatarUrl}
                      alt={comment.user.nickname}
                      className="bg-surface-2 h-10 w-10 shrink-0 rounded-full object-cover"
                      onError={(e) => {
                        // Fallback to GradientAvatar on error
                        const target = e.currentTarget;
                        target.style.display = "none";
                        const fallback = target.nextElementSibling;
                        if (fallback) {
                          (fallback as HTMLElement).style.display = "flex";
                        }
                      }}
                    />
                  ) : null}
                  <GradientAvatar
                    initial={comment.user.nickname.slice(0, 1)}
                    size="md"
                    className={cn("shrink-0", comment.user.avatarUrl && "hidden")}
                  />

                  <div className="min-w-0 flex-1">
                    {/* Header: nickname + status tag */}
                    <div className="mb-2 flex flex-wrap items-center gap-2">
                      {comment.url ? (
                        <a
                          href={comment.url}
                          target="_blank"
                          rel="noreferrer"
                          className="text-ink hover:text-mint-600 text-[14px] font-extrabold transition-colors"
                        >
                          {comment.user.nickname}
                        </a>
                      ) : (
                        <span className="text-ink text-[14px] font-extrabold">
                          {comment.user.nickname}
                        </span>
                      )}
                      {comment.status ? (
                        <span className="bg-surface-2 text-ink-faint rounded-full px-2 py-0.5 text-[11px] font-bold">
                          {comment.status}
                        </span>
                      ) : null}
                    </div>

                    {/* Comment text */}
                    <p className="text-ink mb-3 text-[13.5px] leading-relaxed">{comment.text}</p>

                    {/* Footer: score + time */}
                    <div className="flex flex-wrap items-center gap-3">
                      {typeof comment.score === "number" && comment.score > 0 ? (
                        <ReadOnlyRating score={comment.score} />
                      ) : null}
                      {comment.createdAt ? (
                        <div className="text-ink-faint flex items-center gap-1 text-[12px] font-medium">
                          <Clock className="h-3 w-3" strokeWidth={2} />
                          <span>{comment.createdAt}</span>
                        </div>
                      ) : null}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="border-line bg-surface-2 text-ink-faint mt-3.5 rounded-[14px] border p-5 text-center text-sm font-semibold">
              {loading ? "正在获取吐槽箱数据…" : "没有获取到吐槽箱数据。"}
            </div>
          )}
        </div>
      ) : (
        <>
          {topics.length > 0 ? (
            <div className="space-y-2.5">
              {topics.map((topic, index) => (
                <div
                  key={topic.topicId ?? `${topic.title}-${index}`}
                  className="border-line bg-surface group rounded-[14px] border p-4 shadow-[var(--shadow-xs)] transition-shadow hover:shadow-[var(--shadow-sm)]"
                >
                  {/* Topic title */}
                  {topic.url ? (
                    <a
                      href={topic.url}
                      target="_blank"
                      rel="noreferrer"
                      className="text-ink group-hover:text-mint-600 mb-2.5 block text-[15px] leading-snug font-bold transition-colors"
                    >
                      {topic.title}
                    </a>
                  ) : (
                    <div className="text-ink mb-2.5 text-[15px] leading-snug font-bold">
                      {topic.title}
                    </div>
                  )}

                  {/* Meta info: author + replies + time */}
                  <div className="text-ink-faint flex flex-wrap items-center gap-x-3 gap-y-1.5 text-[12.5px] font-medium">
                    {topic.author ? (
                      <div className="flex items-center gap-1">
                        <User className="h-3 w-3" strokeWidth={2} />
                        <span>{topic.author}</span>
                      </div>
                    ) : null}
                    {typeof topic.replies === "number" ? (
                      <div className="text-mint-600 flex items-center gap-1 font-semibold">
                        <MessageCircle className="h-3 w-3" strokeWidth={2} />
                        <span>{topic.replies} 回复</span>
                      </div>
                    ) : null}
                    {topic.updatedAt ? (
                      <div className="flex items-center gap-1">
                        <Clock className="h-3 w-3" strokeWidth={2} />
                        <span>{topic.updatedAt}</span>
                      </div>
                    ) : null}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="border-line bg-surface-2 text-ink-faint rounded-[14px] border p-5 text-center text-sm font-semibold">
              {loading ? "正在获取讨论内容…" : "暂未加载讨论内容。"}
            </div>
          )}
        </>
      )}
    </>
  );
}
