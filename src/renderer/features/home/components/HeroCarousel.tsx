import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { ChevronLeft, ChevronRight, Heart, Play } from "lucide-react";
import type { BroadcastItem, SeasonInfo } from "@shared/contracts/bangumi";
import type { Season } from "@/data/home";
import { SeasonChip } from "@/components/melon/SeasonChip";

const heroBackgrounds = [
  "#1a9374",
  "#b84176",
  "#d97642"
];

export function HeroCarousel({ items }: { items: BroadcastItem[] }) {
  const [idx, setIdx] = useState(0);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  const slides = items
    .filter(
      (item): item is BroadcastItem & { subjectId: number } => typeof item.subjectId === "number"
    )
    .slice(0, 5)
    .map((item, index) => toSlide(item, index));
  const count = slides.length;

  const go = (next: number): void => {
    if (count > 0) {
      setIdx((next + count) % count);
    }
  };

  useEffect(() => {
    if (count <= 1) {
      return;
    }
    timer.current = setInterval(() => setIdx((i) => (i + 1) % count), 5500);
    return () => {
      if (timer.current) {
        clearInterval(timer.current);
      }
    };
  }, [count]);

  const pause = (): void => {
    if (timer.current) {
      clearInterval(timer.current);
      timer.current = null;
    }
  };
  const resume = (): void => {
    if (count <= 1) {
      return;
    }
    pause();
    timer.current = setInterval(() => setIdx((i) => (i + 1) % count), 5500);
  };

  if (slides.length === 0) {
    return (
      <div className="border-line bg-surface text-ink-faint mt-1.5 grid min-h-[196px] place-items-center rounded-[24px] border text-sm font-bold shadow-[var(--shadow-md)]">
        本季度热播数据暂不可用。
      </div>
    );
  }

  return (
    <div
      className="group relative mt-1.5 overflow-hidden rounded-[24px] shadow-[var(--shadow-md)]"
      onMouseEnter={pause}
      onMouseLeave={resume}
    >
      <div
        className="flex transition-transform duration-[550ms] ease-[cubic-bezier(.4,0,.2,1)]"
        style={{ transform: `translateX(-${idx * 100}%)` }}
      >
        {slides.map((slide) => (
          <div
            key={slide.subjectId}
            className="relative flex min-h-[196px] flex-[0_0_100%] items-stretch overflow-hidden text-white"
          >
            <div className="absolute inset-0" style={{ background: slide.background }} />

            {/* 左侧内容区 */}
            <div className="relative z-[2] flex flex-1 flex-col justify-end px-7 py-5">
              <span className="pointer-events-none absolute -left-3 -bottom-8 text-[140px] font-extrabold leading-none text-white/[0.08]">
                {slide.kanji}
              </span>

              <div className="relative max-w-[480px]">
                <div className="mb-2.5 flex flex-wrap items-center gap-2">
                  <span className="rounded-full bg-white/90 px-3 py-1 text-xs font-extrabold text-gray-800 shadow-sm">
                    {slide.badge}
                  </span>
                  <SeasonChip season={slide.season} label={slide.seasonLabel} />
                  <span className="rounded-full bg-white/[0.22] px-2.5 py-1 text-[11px] font-bold backdrop-blur-sm">
                    {slide.kind}
                  </span>
                </div>
                <h2 className="mb-2 text-[27px] font-extrabold leading-tight [text-shadow:0_2px_16px_rgba(0,0,0,.35)]">
                  {slide.title}
                </h2>
                <p className="mb-4 line-clamp-2 text-[13px] leading-relaxed text-white/[0.92] [text-shadow:0_1px_8px_rgba(0,0,0,.25)]">
                  {slide.desc}
                </p>
                <div className="flex flex-wrap gap-2">
                  <Link
                    to={`/subject/${slide.subjectId}`}
                    className="text-mint-600 inline-flex h-10 items-center gap-1.5 rounded-full bg-white px-5 text-sm font-extrabold shadow-[0_3px_12px_rgba(0,0,0,.25)]"
                  >
                    <Play className="size-4 fill-current" />
                    查看详情
                  </Link>
                  <button
                    type="button"
                    className="inline-flex h-10 items-center gap-1.5 rounded-full border border-white/40 bg-white/[0.20] px-5 text-sm font-extrabold text-white backdrop-blur-sm transition hover:bg-white/30"
                  >
                    <Heart className="size-4" />
                    追番
                  </button>
                </div>
              </div>
            </div>

            {/* 右侧封面区 */}
            {slide.coverUrl ? (
              <div className="relative w-[280px] flex-none">
                <div className="absolute inset-0 bg-gradient-to-r from-black/40 via-black/15 to-transparent" />
                <img
                  src={slide.coverUrl}
                  alt=""
                  className="absolute inset-0 size-full object-cover object-center"
                  loading="lazy"
                />
                <div className="absolute inset-0 bg-gradient-to-l from-transparent via-transparent to-black/20" />
              </div>
            ) : null}
          </div>
        ))}
      </div>

      <button
        type="button"
        aria-label="上一个"
        onClick={() => {
          go(idx - 1);
          resume();
        }}
        className="absolute top-1/2 left-3 grid size-9 -translate-y-1/2 place-items-center rounded-full border border-white/30 bg-white/[0.14] text-white opacity-0 backdrop-blur-[4px] transition group-hover:opacity-100 hover:bg-white/25"
      >
        <ChevronLeft className="size-4" />
      </button>
      <button
        type="button"
        aria-label="下一个"
        onClick={() => {
          go(idx + 1);
          resume();
        }}
        className="absolute top-1/2 right-3 grid size-9 -translate-y-1/2 place-items-center rounded-full border border-white/30 bg-white/[0.14] text-white opacity-0 backdrop-blur-[4px] transition group-hover:opacity-100 hover:bg-white/25"
      >
        <ChevronRight className="size-4" />
      </button>

      <div className="absolute right-5 bottom-4 z-[6] flex gap-1.5">
        {slides.map((slide, i) => (
          <button
            key={slide.subjectId}
            type="button"
            aria-label={`第 ${i + 1} 张`}
            onClick={() => {
              go(i);
              resume();
            }}
            className={
              "h-1.5 rounded-full transition-all " +
              (i === idx ? "w-5 bg-white" : "w-1.5 bg-white/40")
            }
          />
        ))}
      </div>
    </div>
  );
}

function toSlide(item: BroadcastItem & { subjectId: number }, index: number) {
  return {
    subjectId: item.subjectId,
    kanji: Array.from(item.displayName ?? item.nameCn ?? item.name)[0] ?? "新",
    badge: `本季热度 #${index + 1}`,
    season: toSeason(item.season),
    seasonLabel: item.season?.label ?? "CURRENT SEASON",
    kind: [item.platform, typeof item.score === "number" ? `${item.score.toFixed(1)} 分` : null]
      .filter(Boolean)
      .join(" · "),
    title: item.displayName ?? item.nameCn ?? item.name,
    ep: typeof item.episodeTotal === "number" ? `全 ${item.episodeTotal} 话` : "",
    desc: item.summary ?? "暂无简介。",
    background: heroBackgrounds[index % heroBackgrounds.length],
    coverUrl: item.coverUrl
  };
}

function toSeason(season: SeasonInfo | undefined): Season {
  switch (season?.name) {
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
