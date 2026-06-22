import { Play } from "lucide-react";
import type { ReactElement, ReactNode } from "react";
import { Link } from "react-router-dom";
import type { CollectionListItem } from "@shared/contracts/bangumi";
import { ArtworkCard } from "@/components/melon/artwork";
import { collectionStatusMeta } from "@/components/melon/status";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

export function PosterCard({
  item,
  compact = false,
  extra
}: {
  item: CollectionListItem;
  compact?: boolean;
  extra?: ReactNode;
}): ReactElement {
  const meta = collectionStatusMeta[item.collection.status];
  const progressText = item.nextEpisode
    ? `看到 EP${Math.max(1, item.nextEpisode.sort - (item.nextEpisode.status === "watched" ? 0 : 1))}`
    : typeof item.watchedEpisodeCount === "number"
      ? `看到 EP${item.watchedEpisodeCount}`
      : `全 ${item.episodeTotal ?? "?"} 话`;

  return (
    <Link
      to={`/subject/${item.subjectId}`}
      className={cn(
        "flex flex-col transition hover:-translate-y-1",
        compact ? "w-[188px] flex-none" : "min-w-0"
      )}
    >
      <div className="group/cover relative">
        <ArtworkCard
          id={item.subjectId}
          title={item.nameCn ?? item.name}
          imageUrl={item.coverUrl}
          className={cn(
            compact ? "aspect-[3/4]" : "aspect-[3/4] w-full",
            item.collection.status === "dropped" && "opacity-90 grayscale-[0.3]"
          )}
        />
        <div className="absolute top-3 left-3">
          <Badge variant={meta.badgeVariant}>{meta.label}</Badge>
        </div>
        {item.episodeTotal ? (
          <div className="absolute top-3 right-3 rounded-full bg-black/30 px-2 py-1 text-[11px] font-extrabold text-white backdrop-blur-sm">
            全 {item.episodeTotal} 话
          </div>
        ) : null}
        <div className="absolute inset-0 grid place-items-center opacity-0 transition group-hover/cover:opacity-100">
          <div className="grid size-11 place-items-center rounded-full bg-white/95 text-[var(--mint-600)] shadow-[var(--shadow-md)]">
            <Play className="size-4.5 fill-current" />
          </div>
        </div>
        <div className="absolute inset-x-0 bottom-0 rounded-b-[14px] bg-linear-to-t from-black/70 to-transparent px-3 pt-8 pb-3">
          <div className="line-clamp-2 text-sm font-black text-white">
            {item.nameCn ?? item.name}
          </div>
        </div>
      </div>
      <div className="px-0.5 pt-2">
        <div className="text-muted-foreground flex items-center justify-between gap-2 text-[11px] font-bold">
          <span className="truncate">★ {formatScore(item.score)}</span>
          <span className="truncate">{progressText}</span>
        </div>
        {extra ? <div className="mt-2">{extra}</div> : null}
      </div>
    </Link>
  );
}

function formatScore(score: number | undefined): string {
  return typeof score === "number" && Number.isFinite(score) && score > 0 ? String(score) : "—";
}
