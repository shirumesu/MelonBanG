import { ChevronLeft, ChevronRight } from "lucide-react";
import { useRef } from "react";
import type { CollectionListItem } from "@shared/contracts/bangumi";
import { PosterCard } from "@/features/tracking/components/PosterCard";
import { Button } from "@/components/ui/button";

export function ContinueRail({ items }: { items: CollectionListItem[] }): JSX.Element {
  const railRef = useRef<HTMLDivElement | null>(null);

  function scrollBy(direction: -1 | 1): void {
    railRef.current?.scrollBy({
      left: railRef.current.clientWidth * 0.8 * direction,
      behavior: "smooth"
    });
  }

  return (
    <div className="relative">
      <Button
        type="button"
        variant="outline"
        size="sm"
        className="absolute top-[42%] left-[-8px] z-10 size-9 rounded-full p-0"
        onClick={() => scrollBy(-1)}
      >
        <ChevronLeft className="size-4" />
      </Button>
      <div ref={railRef} className="flex gap-4 overflow-x-auto px-1 pb-3">
        {items.map((item) => (
          <PosterCard
            key={item.subjectId}
            item={item}
            compact
            extra={
              item.nextEpisode ? (
                <div className="bg-secondary h-1 rounded-full">
                  <div
                    className="h-full rounded-full bg-linear-to-r from-[var(--mint-400)] to-[var(--mint-300)]"
                    style={{
                      width: `${Math.max(8, Math.min(100, ((item.nextEpisode.sort - 1) / (item.episodeTotal ?? 1)) * 100))}%`
                    }}
                  />
                </div>
              ) : null
            }
          />
        ))}
      </div>
      <Button
        type="button"
        variant="outline"
        size="sm"
        className="absolute top-[42%] right-[-8px] z-10 size-9 rounded-full p-0"
        onClick={() => scrollBy(1)}
      >
        <ChevronRight className="size-4" />
      </Button>
    </div>
  );
}
