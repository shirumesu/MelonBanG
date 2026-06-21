import { useCallback, useEffect, useRef, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useAppState } from "@/app/AppStateProvider";
import { PosterCard } from "@/features/tracking/components/PosterCard";

export function ContinueRail() {
  const { homeItems } = useAppState();
  const rowRef = useRef<HTMLDivElement>(null);
  const [atStart, setAtStart] = useState(true);
  const [atEnd, setAtEnd] = useState(false);

  const update = useCallback((): void => {
    const row = rowRef.current;
    if (!row) {
      return;
    }
    const max = row.scrollWidth - row.clientWidth;
    setAtStart(row.scrollLeft <= 1);
    setAtEnd(row.scrollLeft >= max - 1);
  }, []);

  useEffect(() => {
    update();
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, [homeItems, update]);

  const scrollBy = (dir: number): void => {
    const row = rowRef.current;
    if (!row) {
      return;
    }
    row.scrollBy({ left: dir * Math.max(220, row.clientWidth * 0.8), behavior: "smooth" });
  };

  return (
    <div className="group relative">
      <button
        type="button"
        aria-label="向左"
        onClick={() => scrollBy(-1)}
        className={
          "border-line bg-surface text-ink-soft hover:border-mint-200 hover:text-mint-600 absolute top-[46%] -left-2 z-[5] grid size-[38px] -translate-y-1/2 place-items-center rounded-full border opacity-0 shadow-[var(--shadow-md)] transition group-hover:opacity-100 " +
          (atStart ? "hidden" : "")
        }
      >
        <ChevronLeft className="size-[18px]" />
      </button>

      <div ref={rowRef} onScroll={update} className="flex gap-4 overflow-x-auto px-0.5 pt-1 pb-3.5">
        {homeItems.length > 0 ? (
          homeItems
            .slice(0, 12)
            .map((item) => (
              <PosterCard
                key={item.subjectId}
                item={item}
                compact
                extra={
                  item.pendingMutationKeys.length > 0 ? (
                    <span className="text-gold-500 text-[11px] font-extrabold">等待同步</span>
                  ) : null
                }
              />
            ))
        ) : (
          <div className="border-line bg-surface text-ink-faint w-full rounded-[20px] border p-8 text-center text-sm font-bold shadow-[var(--shadow-sm)]">
            暂无在看收藏。
          </div>
        )}
      </div>

      <button
        type="button"
        aria-label="向右"
        onClick={() => scrollBy(1)}
        className={
          "border-line bg-surface text-ink-soft hover:border-mint-200 hover:text-mint-600 absolute top-[46%] -right-2 z-[5] grid size-[38px] -translate-y-1/2 place-items-center rounded-full border opacity-0 shadow-[var(--shadow-md)] transition group-hover:opacity-100 " +
          (atEnd ? "hidden" : "")
        }
      >
        <ChevronRight className="size-[18px]" />
      </button>
    </div>
  );
}
