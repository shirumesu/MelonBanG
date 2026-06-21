import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { ChevronLeft, ChevronRight, Heart, Play } from "lucide-react";
import { HERO_SLIDES } from "@/data/home";
import { SeasonChip } from "@/components/melon/SeasonChip";

export function HeroCarousel() {
  const [idx, setIdx] = useState(0);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  const count = HERO_SLIDES.length;

  const go = (next: number): void => setIdx((next + count) % count);

  useEffect(() => {
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
    pause();
    timer.current = setInterval(() => setIdx((i) => (i + 1) % count), 5500);
  };

  return (
    <div
      className="group relative mt-1.5 overflow-hidden rounded-[28px] shadow-[var(--shadow-lg)]"
      onMouseEnter={pause}
      onMouseLeave={resume}
    >
      <div
        className="flex transition-transform duration-[550ms] ease-[cubic-bezier(.4,0,.2,1)]"
        style={{ transform: `translateX(-${idx * 100}%)` }}
      >
        {HERO_SLIDES.map((slide) => (
          <div
            key={slide.title}
            className="relative flex min-h-[262px] flex-[0_0_100%] flex-col justify-end px-[34px] py-[30px] text-white"
          >
            <div className="absolute inset-0" style={{ background: slide.background }} />
            <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(0,0,0,.46),rgba(0,0,0,.14)_58%,transparent)]" />
            <span className="pointer-events-none absolute -right-1.5 -bottom-[46px] text-[230px] leading-none font-extrabold text-white/[0.13]">
              {slide.kanji}
            </span>
            <div className="relative z-[2] max-w-[560px]">
              <div className="mb-3 flex flex-wrap items-center gap-2.5">
                <span className="rounded-full bg-white/20 px-2.5 py-1 text-[11.5px] font-bold">
                  {slide.badge}
                </span>
                <SeasonChip season={slide.season} label={slide.seasonLabel} />
                <span className="rounded-full bg-white/[0.18] px-2.5 py-1 text-[11.5px] font-bold">
                  {slide.kind}
                </span>
              </div>
              <h2 className="my-2 text-[30px] font-extrabold [text-shadow:0_2px_14px_rgba(0,0,0,.3)]">
                {slide.title}
              </h2>
              <p className="mb-[18px] text-sm leading-relaxed text-white/90">{slide.desc}</p>
              <div className="flex flex-wrap gap-2.5">
                <Link
                  to="/player"
                  className="text-mint-600 inline-flex h-12 items-center gap-2 rounded-full bg-white px-6 text-[15px] font-extrabold"
                >
                  <Play className="size-[18px] fill-current" />
                  继续播放 {slide.ep}
                </Link>
                <button
                  type="button"
                  className="inline-flex h-12 items-center gap-2 rounded-full border border-white/40 bg-white/[0.18] px-6 text-[15px] font-extrabold text-white"
                >
                  <Heart className="size-[18px]" />
                  追番
                </button>
                <Link
                  to="/subject/0"
                  className="inline-flex h-12 items-center gap-2 rounded-full border border-white/30 bg-white/[0.12] px-6 text-[15px] font-extrabold text-white"
                >
                  查看详情
                </Link>
              </div>
            </div>
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
        className="absolute top-1/2 left-4 grid size-10 -translate-y-1/2 place-items-center rounded-full border border-white/40 bg-white/[0.18] text-white opacity-0 backdrop-blur-[6px] transition group-hover:opacity-100 hover:bg-white/30"
      >
        <ChevronLeft className="size-[18px]" />
      </button>
      <button
        type="button"
        aria-label="下一个"
        onClick={() => {
          go(idx + 1);
          resume();
        }}
        className="absolute top-1/2 right-4 grid size-10 -translate-y-1/2 place-items-center rounded-full border border-white/40 bg-white/[0.18] text-white opacity-0 backdrop-blur-[6px] transition group-hover:opacity-100 hover:bg-white/30"
      >
        <ChevronRight className="size-[18px]" />
      </button>

      <div className="absolute right-6 bottom-[22px] z-[6] flex gap-[7px]">
        {HERO_SLIDES.map((slide, i) => (
          <button
            key={slide.title}
            type="button"
            aria-label={`第 ${i + 1} 张`}
            onClick={() => {
              go(i);
              resume();
            }}
            className={
              "h-2 rounded-full transition-all " +
              (i === idx ? "w-[22px] bg-white" : "w-2 bg-white/45")
            }
          />
        ))}
      </div>
    </div>
  );
}
