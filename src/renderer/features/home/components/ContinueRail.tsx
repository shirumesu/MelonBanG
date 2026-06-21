import { useEffect, useRef, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { CONTINUE_ITEMS } from "@/data/home";
import { Poster } from "@/components/melon/Poster";

export function ContinueRail() {
  const rowRef = useRef<HTMLDivElement>(null);
  const [atStart, setAtStart] = useState(true);
  const [atEnd, setAtEnd] = useState(false);

  const update = (): void => {
    const row = rowRef.current;
    if (!row) {
      return;
    }
    const max = row.scrollWidth - row.clientWidth;
    setAtStart(row.scrollLeft <= 1);
    setAtEnd(row.scrollLeft >= max - 1);
  };

  useEffect(() => {
    update();
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);

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

      <div
        ref={rowRef}
        onScroll={update}
        className="flex gap-4 overflow-x-auto px-0.5 pt-1 pb-3.5"
      >
        {CONTINUE_ITEMS.map((item) => (
          <Poster
            key={item.index}
            index={item.index}
            href="/subject/0"
            width={172}
            overlayTitle={item.title}
            body={
              <>
                <div className="text-ink-faint flex items-center gap-1.5 text-[11.5px] font-semibold">
                  <span className="text-gold-500 font-extrabold">★ {item.score}</span>·
                  <span>看到 EP{item.currentEp}</span>
                </div>
                <div className="bg-surface-3 mt-2 h-1 overflow-hidden rounded-full">
                  <div
                    className="h-full rounded-full bg-[linear-gradient(90deg,var(--mint-400),var(--mint-300))]"
                    style={{ width: `${item.progress}%` }}
                  />
                </div>
              </>
            }
          />
        ))}
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
