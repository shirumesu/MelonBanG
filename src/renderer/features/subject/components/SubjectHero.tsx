import { Download, ExternalLink, Film, ListChecks, Play } from "lucide-react";
import type { CollectionStatus, SubjectDetail } from "@shared/contracts/bangumi";
import { StarRow } from "@/components/melon/RatingStars";
import { SeasonChip } from "@/components/melon/SeasonChip";
import { IconButton } from "@/components/melon/layout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { artGradient } from "@/data/artwork";
import { cn } from "@/lib/utils";

const STATUS_OPTIONS: { key: CollectionStatus; label: string }[] = [
  { key: "wish", label: "想看" },
  { key: "watching", label: "在看" },
  { key: "on_hold", label: "搁置" },
  { key: "completed", label: "看过" },
  { key: "dropped", label: "抛弃" }
];

const STAT_COLORS: Record<CollectionStatus, string> = {
  wish: "var(--sky-400)",
  watching: "var(--mint-400)",
  on_hold: "var(--gold-400)",
  completed: "var(--grape-400)",
  dropped: "var(--cherry-400)"
};

const STAT_LABELS: Record<CollectionStatus, string> = {
  wish: "想看",
  watching: "在看",
  on_hold: "搁置",
  completed: "看过",
  dropped: "抛弃"
};

export function SubjectHero({
  subject,
  onOpenEpisodes,
  onOpenCache,
  onOpenPv,
  onContinuePlayback,
  onChangeStatus
}: {
  subject: SubjectDetail;
  onOpenEpisodes: () => void;
  onOpenCache: () => void;
  onOpenPv: () => void;
  onContinuePlayback: () => void;
  onChangeStatus: (status: CollectionStatus) => void;
}) {
  const title = subject.nameCn ?? subject.name;
  const nextEpisode = subject.episodes.find(
    (episode) => episode.status === "queue" || episode.status === "unwatched"
  );
  const watchedCount = subject.episodes.filter((episode) => episode.status === "watched").length;
  const season = seasonFromDate(subject.airDate);
  const seasonLabel = subject.airDate
    ? `${subject.airDate.slice(0, 4)} ${season.label}`
    : "未知档期";
  const chips = buildChips(subject);
  const stats = buildStats(subject);

  return (
    <div className="border-line bg-surface relative grid grid-cols-[230px_1fr] gap-16 overflow-hidden rounded-[20px] border p-7 shadow-[var(--shadow-sm)] max-[1080px]:grid-cols-[160px_1fr] max-[1080px]:gap-7 max-[1080px]:p-5">
      <div className="absolute inset-0 opacity-[0.07] [background:radial-gradient(ellipse_650px_460px_at_22%_32%,var(--gold-400),transparent),radial-gradient(ellipse_500px_360px_at_72%_52%,var(--mint-300),transparent),radial-gradient(ellipse_380px_300px_at_55%_92%,var(--cherry-400),transparent)] dark:opacity-[0.05]" />

      <a
        href={`https://bgm.tv/subject/${subject.subjectId}`}
        target="_blank"
        rel="noreferrer"
        className="text-mint-600 border-mint-200 bg-mint-50 hover:bg-mint-100 absolute top-3.5 right-[18px] z-[2] inline-flex items-center gap-1.5 rounded-full border px-[11px] py-[5px] text-xs font-bold max-[1080px]:relative max-[1080px]:top-0 max-[1080px]:right-0 max-[1080px]:mb-2 max-[1080px]:self-start"
      >
        <ExternalLink className="size-4" />在 Bangumi 打开
      </a>

      <div
        className="relative aspect-3/4 self-stretch overflow-hidden rounded-[14px] shadow-[0_24px_60px_rgba(28,70,55,.25),0_0_0_1px_rgba(0,0,0,.05)]"
        style={{ background: artGradient(subject.subjectId) }}
      >
        {subject.coverUrl ? (
          <img
            src={subject.coverUrl}
            alt=""
            className="absolute inset-0 size-full object-cover"
            decoding="async"
            referrerPolicy="no-referrer"
          />
        ) : (
          <span className="absolute inset-0 grid place-items-center text-[72px] font-extrabold text-white/10">
            {title.slice(0, 1)}
          </span>
        )}
      </div>

      <div className="relative flex min-w-0 flex-col gap-2">
        <h1 className="text-2xl font-extrabold tracking-[-0.01em] max-[1080px]:pr-0">{title}</h1>
        <div className="text-ink-faint mb-0.5 text-[12.5px] font-semibold">{subject.name}</div>

        <div className="flex flex-wrap gap-1.5">
          <SeasonChip season={season.key} label={seasonLabel} />
          {chips.map((chip, index) => (
            <Badge key={`${chip}-${index}`} variant={index === 0 ? "mint" : "outline"}>
              {chip}
            </Badge>
          ))}
        </div>

        <div className="text-ink-soft text-[13.5px] leading-normal font-medium">
          已看{" "}
          <span className="text-mint-500 text-[15px] font-extrabold">
            {watchedCount > 0 ? `EP${String(watchedCount).padStart(2, "0")}` : "未开始"}
          </span>{" "}
          / 预定全 {subject.episodeTotal ?? "?"} 话 · {subject.airDate ?? "未知开播日期"}
          {subject.platform ? ` · ${subject.platform}` : ""}
        </div>

        <div className="flex flex-col items-start gap-1">
          <div className="flex items-baseline gap-3.5">
            <span className="inline-flex items-baseline text-[48px] leading-none font-extrabold tracking-[-0.03em]">
              {subject.score?.toFixed(1) ?? "—"}
              <small className="text-ink-faint ml-[3px] text-xl font-bold">/10</small>
            </span>
            <div className="inline-flex items-center gap-1.5 self-end rounded-[14px] border border-[rgba(255,107,129,.2)] bg-[linear-gradient(135deg,rgba(255,107,129,.08),rgba(255,107,129,.14))] px-3.5 py-2">
              <span className="text-cherry-500 text-[18px] font-extrabold">
                #{subject.rank ?? "—"}
              </span>
              <span className="text-cherry-600 text-[11px] leading-tight font-semibold opacity-80">
                Bangumi
                <br />
                Rank
              </span>
            </div>
            <div className="flex flex-col items-start gap-0.5 self-end">
              <StarRow value={(subject.score ?? 0) / 2} size={16} />
              <div className="text-ink-faint text-xs font-medium">
                {subject.ratingCount ? `${subject.ratingCount} 人评分` : "评分人数未知"}
              </div>
            </div>
          </div>
        </div>

        <div className="flex flex-col gap-2 py-0.5">
          <div className="bg-surface-3 flex h-2 overflow-hidden rounded-full">
            {stats.map((stat) => (
              <div key={stat.key} style={{ width: `${stat.pct}%`, background: stat.color }} />
            ))}
          </div>
          <div className="text-ink-faint flex flex-wrap gap-x-5 text-xs leading-[2.1] font-medium">
            {stats.map((stat) => (
              <span key={stat.key}>
                <span
                  className="mr-1.5 inline-block size-[9px] rounded-[3px] align-middle"
                  style={{ background: stat.color }}
                />
                <b className="text-ink-soft mr-0.5 font-extrabold">{stat.count}</b> {stat.label}
              </span>
            ))}
          </div>
        </div>

        <div className="bg-line my-1.5 h-px" />

        <div className="flex flex-wrap items-center gap-2">
          <Button onClick={onContinuePlayback}>
            <Play className="size-[18px] fill-current" />
            继续播放 {nextEpisode ? `EP${String(nextEpisode.sort).padStart(2, "0")}` : ""}
          </Button>
          <IconButton title="选集" onClick={onOpenEpisodes}>
            <ListChecks />
          </IconButton>
          <IconButton title="搜索并缓存资源" onClick={onOpenCache}>
            <Download />
          </IconButton>
          <IconButton title="查看 PV" onClick={onOpenPv}>
            <Film />
          </IconButton>

          <div className="border-line bg-surface-2 inline-flex items-center rounded-full border p-1.5">
            <div className="inline-flex gap-1">
              {STATUS_OPTIONS.map((option) => (
                <button
                  key={option.key}
                  type="button"
                  onClick={() => onChangeStatus(option.key)}
                  className={cn(
                    "rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                    subject.collection?.status === option.key
                      ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_5px_12px_rgba(34,179,136,.28)]"
                      : "text-ink-soft hover:text-ink"
                  )}
                >
                  {option.label}
                </button>
              ))}
            </div>
            <span className="bg-line-strong mx-1.5 h-[22px] w-px" />
            <button
              type="button"
              disabled
              title="Bangumi v0 当前接口未提供删除条目收藏的稳定入口"
              className="text-cherry-500 rounded-full px-3.5 py-2 text-[13px] font-bold opacity-45"
            >
              取消追番
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function buildChips(subject: SubjectDetail): string[] {
  const chips = [
    subject.platform,
    ...(subject.metaTags ?? []),
    ...(subject.tags ?? []).map((tag) => tag.name)
  ];

  return [
    ...new Set(chips.filter((chip): chip is string => typeof chip === "string" && chip.length > 0))
  ].slice(0, 6);
}

function buildStats(subject: SubjectDetail): Array<{
  key: CollectionStatus;
  label: string;
  count: number;
  pct: number;
  color: string;
}> {
  const stats = subject.collectionStats ?? {
    wish: 0,
    watching: 0,
    on_hold: 0,
    completed: 0,
    dropped: 0
  };
  const total = Object.values(stats).reduce((sum, count) => sum + count, 0);

  return (["wish", "watching", "on_hold", "completed", "dropped"] as const).map((key) => ({
    key,
    label: STAT_LABELS[key],
    count: stats[key],
    pct: total > 0 ? (stats[key] / total) * 100 : 0,
    color: STAT_COLORS[key]
  }));
}

function seasonFromDate(date: string | undefined): {
  key: "spring" | "summer" | "fall" | "winter" | "default";
  label: string;
} {
  if (!date) {
    return { key: "default", label: "SEASON" };
  }

  const month = Number(date.slice(5, 7));
  if (month >= 10) {
    return { key: "fall", label: "FALL" };
  }
  if (month >= 7) {
    return { key: "summer", label: "SUMMER" };
  }
  if (month >= 4) {
    return { key: "spring", label: "SPRING" };
  }
  return { key: "winter", label: "WINTER" };
}
