import { Link } from "react-router-dom";
import { Eye, Play } from "lucide-react";
import type { TimelineItem } from "@/data/home";
import { artGradient, artKanji } from "@/data/artwork";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

function RowMeta({ item, isNext }: { item: TimelineItem; isNext: boolean }) {
  const badgeLabel =
    item.badgeLabel ??
    (item.done
      ? `已更新${typeof item.ep === "number" ? ` EP${item.ep}` : ""}`
      : `${isNext ? "即将" : "待播"}${typeof item.ep === "number" ? ` · EP${item.ep}` : ""}`);

  if (item.done) {
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
  isFirst,
  isLast
}: {
  item: TimelineItem;
  isNext: boolean;
  isFirst: boolean;
  isLast: boolean;
}) {
  return (
    <div className="flex items-stretch gap-3.5">
      <div
        className={
          "flex w-[52px] flex-none items-center justify-end text-[13.5px] font-extrabold tabular-nums " +
          (item.done ? "text-ink-faint" : "text-mint-600")
        }
      >
        {item.time}
      </div>

      <div className="relative flex w-4 flex-none items-center justify-center">
        <span
          className="bg-line-strong absolute left-1/2 w-0.5 -translate-x-1/2"
          style={{ top: isFirst ? "50%" : 0, bottom: isLast ? "50%" : 0 }}
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
                  background: item.done ? "var(--mint-400)" : "var(--surface)"
                }
          }
        />
      </div>

      <Link
        to={`/subject/${item.subjectId ?? item.index}`}
        className={
          "group border-line bg-surface my-1.5 flex flex-1 items-center gap-3.5 rounded-[14px] border px-3.5 py-2.5 shadow-[var(--shadow-sm)] transition hover:translate-x-[3px] hover:shadow-[var(--shadow-md)] " +
          (isNext
            ? "border-cherry-300 shadow-[0_6px_16px_rgba(255,107,129,.16)]"
            : "hover:border-mint-200")
        }
      >
        <span
          className="relative h-14 w-[42px] flex-none overflow-hidden rounded-[9px] shadow-[var(--shadow-sm)]"
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
            <span className="absolute inset-0 grid place-items-center text-2xl font-extrabold text-white/35">
              {artKanji(item.index)}
            </span>
          )}
          <span className="absolute inset-0 grid place-items-center bg-black/35 text-white opacity-0 transition group-hover:opacity-100">
            <Play className="size-4 fill-current" />
          </span>
        </span>
        <div className="min-w-0 flex-1">
          <b className="block truncate text-sm font-bold">{item.title}</b>
          <div className="text-ink-faint mt-[3px] text-xs font-semibold">
            {item.subtitle ??
              (item.done
                ? `已放送${typeof item.ep === "number" ? ` · 更新至 EP${item.ep}` : ""}`
                : `即将放送${typeof item.total === "number" ? ` · 全${item.total}话` : ""}`)}
          </div>
        </div>
        <div className="flex flex-none items-center gap-2.5">
          <RowMeta item={item} isNext={isNext} />
        </div>
      </Link>
    </div>
  );
}

export function Timeline({ items }: { items: TimelineItem[] }) {
  const nextIndex = items.findIndex((item) => !item.done);
  return (
    <div className="flex flex-col">
      {items.map((item, i) => (
        <TimelineRow
          key={`${item.time}-${item.index}-${i}`}
          item={item}
          isNext={i === nextIndex}
          isFirst={i === 0}
          isLast={i === items.length - 1}
        />
      ))}
    </div>
  );
}
