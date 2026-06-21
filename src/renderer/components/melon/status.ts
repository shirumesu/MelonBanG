import type { CollectionStatus, EpisodeStatus } from "@shared/contracts/bangumi";

export const collectionStatusMeta: Record<
  CollectionStatus,
  { label: string; badgeVariant: "mint" | "gold" | "grape" | "sky" | "cherry" }
> = {
  watching: { label: "在看", badgeVariant: "mint" },
  wish: { label: "想看", badgeVariant: "gold" },
  on_hold: { label: "搁置", badgeVariant: "grape" },
  completed: { label: "看过", badgeVariant: "sky" },
  dropped: { label: "抛弃", badgeVariant: "cherry" }
};

export const episodeStatusMeta: Record<EpisodeStatus, { label: string }> = {
  unwatched: { label: "未看" },
  queue: { label: "待看" },
  watched: { label: "已看" },
  dropped: { label: "跳过" }
};
