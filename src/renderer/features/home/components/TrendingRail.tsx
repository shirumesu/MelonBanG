import { useEffect, useRef, useState } from "react";
import { ChevronLeft, ChevronRight, Play } from "lucide-react";
import { Link } from "react-router-dom";
import type { BroadcastItem } from "@shared/contracts/bangumi";
import { SeasonChip } from "@/components/melon/SeasonChip";
import type { Season } from "@/data/home";

const trendingBackgrounds = [
  ["#7bd0c1", "#3b82c4"],
  ["#f7a8b8", "#9b6ad8"],
  ["#ffd56b", "#ff7a5b"],
  ["#9be7c4", "#3aa17e"],
  ["#a9c7ff", "#6a6ae0"],
  ["#ffb3c7", "#ff6b9d"],
  ["#c0a8ff", "#7d5fe0"],
  ["#8fe3d6", "#3aa1a8"]
];

const kanjiPool = ["夏", "恋", "刃", "空", "星", "光", "緋", "創", "旅", "幻", "蒼", "奏"];

export function TrendingRail({
  items,
  loading = false
}: {
  items: BroadcastItem[];
  loading?: boolean;
}) {
  const railRef = useRef<HTMLDivElement>(null);
  const [canScrollLeft, setCanScrollLeft] = useState(false);
  const [canScrollRight, setCanScrollRight] = useState(false);

  const slides = items
    .filter(
      (item): item is BroadcastItem & { subjectId: number } => typeof item.subjectId === "number"
    )
    .slice(0, 8)
    .map((item, index) => toSlide(item, index));

  const updateScrollButtons = () => {
    const rail = railRef.current;
    if (!rail) return;

    const maxScroll = rail.scrollWidth - rail.clientWidth;
    setCanScrollLeft(rail.scrollLeft > 1);
    setCanScrollRight(rail.scrollLeft < maxScroll - 1);
  };

  useEffect(() => {
    updateScrollButtons();
    const rail = railRef.current;
    if (!rail) return;

    rail.addEventListener("scroll", updateScrollButtons, { passive: true });
    window.addEventListener("resize", updateScrollButtons);

    return () => {
      rail.removeEventListener("scroll", updateScrollButtons);
      window.removeEventListener("resize", updateScrollButtons);
    };
  }, [slides.length]);

  const scroll = (direction: number) => {
    const rail = railRef.current;
    if (!rail) return;

    const step = Math.max(220, rail.clientWidth * 0.8);
    rail.scrollBy({ left: direction * step, behavior: "smooth" });
  };

  if (slides.length === 0) {
    return (
      <div className="border-line bg-surface text-ink-faint mt-1.5 grid min-h-[200px] place-items-center rounded-[20px] border text-sm font-bold shadow-[var(--shadow-sm)]">
        {loading ? "正在读取本季度热播数据…" : "本季度热播数据暂不可用。"}
      </div>
    );
  }

  return (
    <div className="group relative mt-1.5">
      {/* 左箭头 */}
      {canScrollLeft && (
        <button
          type="button"
          onClick={() => scroll(-1)}
          aria-label="向左滚动"
          className="border-line bg-surface text-ink-faint hover:text-mint-600 hover:border-mint-200 absolute top-[46%] left-[-8px] z-[5] grid size-[38px] -translate-y-1/2 place-items-center rounded-full border opacity-0 shadow-[var(--shadow-md)] transition-all group-hover:opacity-100"
        >
          <ChevronLeft className="size-4" />
        </button>
      )}

      {/* 右箭头 */}
      {canScrollRight && (
        <button
          type="button"
          onClick={() => scroll(1)}
          aria-label="向右滚动"
          className="border-line bg-surface text-ink-faint hover:text-mint-600 hover:border-mint-200 absolute top-[46%] right-[-8px] z-[5] grid size-[38px] -translate-y-1/2 place-items-center rounded-full border opacity-0 shadow-[var(--shadow-md)] transition-all group-hover:opacity-100"
        >
          <ChevronRight className="size-4" />
        </button>
      )}

      {/* 滚动容器 */}
      <div
        ref={railRef}
        className="no-scrollbar flex gap-4 overflow-x-auto scroll-smooth px-0.5 pt-1 pb-3.5"
        style={{ scrollbarWidth: "none", msOverflowStyle: "none" }}
      >
        {slides.map((slide) => (
          <TrendingPoster key={slide.subjectId} slide={slide} />
        ))}
      </div>
    </div>
  );
}

interface Slide {
  subjectId: number;
  rank: number;
  kanji: string;
  gradient: [string, string];
  season: Season;
  seasonLabel: string;
  title: string;
  score: number | null;
  coverUrl: string | undefined;
  episodeTotal: number | undefined;
  type: string;
  studio: string | undefined;
}

function TrendingPoster({ slide }: { slide: Slide }) {
  const isTopRanked = slide.rank <= 3;

  return (
    <Link
      to={`/subject/${slide.subjectId}`}
      className="group/poster flex w-[180px] flex-none flex-col transition-transform duration-180 hover:-translate-y-0.5"
    >
      {/* 封面区域 */}
      <div
        className="relative aspect-[3/4] overflow-hidden rounded-[14px] shadow-[var(--shadow-md)] transition-shadow group-hover/poster:shadow-[var(--shadow-lg)]"
        style={{
          background: slide.coverUrl
            ? undefined
            : `linear-gradient(135deg, ${slide.gradient[0]}, ${slide.gradient[1]})`
        }}
      >
        {slide.coverUrl ? (
          <img
            src={slide.coverUrl}
            alt={slide.title}
            className="absolute inset-0 size-full object-cover object-center"
          />
        ) : (
          <span className="absolute inset-0 grid place-items-center text-[64px] leading-none font-extrabold text-white/[0.22] [text-shadow:0_2px_10px_rgba(0,0,0,.15)]">
            {slide.kanji}
          </span>
        )}

        {/* 渐变遮罩 */}
        <div className="absolute inset-0 bg-gradient-to-t from-black/75 via-black/5 to-transparent" />

        {/* 排名徽章 */}
        <span
          className={
            "absolute top-2 left-2 z-[2] rounded-full px-2.5 py-0.5 text-[11.5px] font-extrabold text-white shadow-[var(--shadow-sm)] backdrop-blur-[6px] " +
            (isTopRanked
              ? "bg-gradient-to-br from-[var(--gold-400)] to-[var(--cherry-500)]"
              : "bg-black/[0.36]")
          }
        >
          #{slide.rank}
        </span>

        {/* 播放图标 */}
        <div className="absolute inset-0 z-[1] grid place-items-center opacity-0 transition-opacity duration-180 group-hover/poster:opacity-100">
          <span className="text-mint-600 grid size-[46px] place-items-center rounded-full bg-white/[0.92] shadow-[var(--shadow-md)]">
            <Play className="size-5 fill-current" />
          </span>
        </div>

        {/* 标题覆盖在底部 */}
        <div className="absolute inset-x-2.5 bottom-2.5 z-[2] line-clamp-2 text-[13px] leading-tight font-extrabold text-white [text-shadow:0_1px_3px_rgba(0,0,0,.5),0_2px_8px_rgba(0,0,0,.4)]">
          {slide.title}
        </div>
      </div>

      {/* 内容区域 */}
      <div className="px-0.5 pt-2.5">
        {/* 标签组 */}
        <div className="mb-1.5 flex flex-wrap gap-1.5">
          <SeasonChip season={slide.season} label={slide.seasonLabel} size="sm" />
          <span className="bg-surface-3 text-ink-faint rounded-full px-2 py-0.5 text-[10px] font-bold">
            {slide.type}
          </span>
          {slide.episodeTotal && (
            <span className="bg-surface-3 text-ink-faint rounded-full px-2 py-0.5 text-[10px] font-bold">
              全{slide.episodeTotal}话
            </span>
          )}
        </div>

        {/* 元信息 */}
        <div className="text-ink-faint flex items-center gap-1.5 text-[11.5px] font-semibold">
          {slide.score !== null && (
            <span className="text-gold-500 font-extrabold">★ {slide.score.toFixed(1)}</span>
          )}
          {slide.score !== null && slide.studio && <span>·</span>}
          {slide.studio && <span className="truncate">{slide.studio}</span>}
        </div>
      </div>
    </Link>
  );
}

function toSlide(item: BroadcastItem & { subjectId: number }, index: number): Slide {
  // Extract studio from metaTags or use platform as fallback
  const studio =
    item.metaTags?.find(
      (tag) => tag.includes("制作") || tag.includes("Studio") || tag.includes("动画")
    ) ?? item.platform;

  return {
    subjectId: item.subjectId,
    rank: index + 1,
    kanji:
      Array.from(item.displayName ?? item.nameCn ?? item.name)[0] ??
      kanjiPool[index % kanjiPool.length],
    gradient: trendingBackgrounds[index % trendingBackgrounds.length],
    season: toSeason(item.season?.name),
    seasonLabel: item.season?.label ?? "CURRENT SEASON",
    title: item.displayName ?? item.nameCn ?? item.name,
    score: typeof item.score === "number" ? item.score : null,
    coverUrl: item.coverUrl,
    episodeTotal: item.episodeTotal,
    type: item.platform ?? "TV",
    studio
  };
}

function toSeason(seasonName: string | undefined): Season {
  switch (seasonName) {
    case "WINTER":
      return "winter";
    case "SPRING":
      return "spring";
    case "FALL":
      return "fall";
    case "SUMMER":
    default:
      return "summer";
  }
}
