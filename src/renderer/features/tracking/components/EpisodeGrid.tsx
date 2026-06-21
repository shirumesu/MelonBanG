import type { EpisodeCollectionState, EpisodeStatus } from "@shared/contracts/bangumi";
import { cn } from "@/lib/utils";

export function EpisodeGrid({
  episodes,
  onSelect
}: {
  episodes: EpisodeCollectionState[];
  onSelect?: (episode: EpisodeCollectionState) => void;
}): JSX.Element {
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(58px,1fr))] gap-2.5">
      {episodes.map((episode) => (
        <button
          key={episode.episodeId}
          type="button"
          onClick={() => onSelect?.(episode)}
          className={cn(
            "relative aspect-square rounded-[11px] border text-sm font-black transition",
            episodeTone(episode.status),
            episode.status !== "unwatched" && "hover:-translate-y-0.5"
          )}
        >
          {episode.sort}
          {episode.status === "watched" ? (
            <span className="absolute top-1 right-1.5 text-[10px] text-[var(--mint-500)]">✓</span>
          ) : null}
        </button>
      ))}
    </div>
  );
}

function episodeTone(status: EpisodeStatus): string {
  if (status === "watched") {
    return "border-[var(--mint-200)] bg-[var(--mint-50)] text-[var(--mint-600)]";
  }
  if (status === "queue") {
    return "border-transparent bg-linear-to-br from-[var(--mint-400)] to-[var(--mint-300)] text-primary-foreground shadow-[0_6px_14px_rgba(34,179,136,.30)]";
  }
  if (status === "dropped") {
    return "border-[var(--cherry-300)] bg-[#fff0f3] text-[var(--cherry-600)]";
  }
  return "border-border bg-card text-muted-foreground hover:border-[var(--mint-300)] hover:text-[var(--mint-600)]";
}
