import { useEffect, useMemo, useState } from "react";
import type { ReactElement } from "react";
import { ChevronLeft, ChevronRight, Heart, Play } from "lucide-react";
import { Link } from "react-router-dom";
import type { CollectionListItem } from "@shared/contracts/bangumi";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useTheme } from "@/app/ThemeProvider";

const heroBackgrounds = [
  "radial-gradient(130% 130% at 86% 6%,rgba(255,255,255,.20),transparent 44%),linear-gradient(115deg,#0f7d5e,#1aa183 42%,#3f7fd8)",
  "radial-gradient(130% 130% at 86% 6%,rgba(255,255,255,.16),transparent 44%),linear-gradient(115deg,#a8336e,#d65189 44%,#8a5fd8)",
  "radial-gradient(130% 130% at 86% 6%,rgba(255,255,255,.16),transparent 44%),linear-gradient(115deg,#c0641d,#ef7f43 44%,#ff5f7a)"
] as const;

const heroBackgroundsDark = [
  "radial-gradient(130% 130% at 86% 6%,rgba(255,255,255,.08),transparent 44%),linear-gradient(115deg,#0a5d48,#138569 42%,#2d5fb8)",
  "radial-gradient(130% 130% at 86% 6%,rgba(255,255,255,.06),transparent 44%),linear-gradient(115deg,#7a2652,#b23e6d 44%,#6a47b8)",
  "radial-gradient(130% 130% at 86% 6%,rgba(255,255,255,.06),transparent 44%),linear-gradient(115deg,#9a4e15,#c86333 44%,#d94858)"
] as const;

export function HomeHero({ items }: { items: CollectionListItem[] }): ReactElement {
  const { resolvedTheme } = useTheme();
  const slides = useMemo(
    () =>
      items.slice(0, 3).map((item, index) => ({
        ...item,
        background: (resolvedTheme === "dark" ? heroBackgroundsDark : heroBackgrounds)[
          index % heroBackgrounds.length
        ],
        kanji: Array.from(item.nameCn ?? item.name)[0] ?? "夏",
        tag: index === 0 ? "本季热度 #1" : index === 1 ? "本周新上架" : "高分推荐"
      })),
    [items, resolvedTheme]
  );

  const [index, setIndex] = useState(0);

  useEffect(() => {
    if (slides.length <= 1) {
      return;
    }
    const timer = window.setInterval(() => {
      setIndex((value) => (value + 1) % slides.length);
    }, 5500);
    return () => window.clearInterval(timer);
  }, [slides.length]);

  if (slides.length === 0) {
    return (
      <div className="border-border bg-card h-[262px] rounded-[28px] border shadow-[var(--shadow-lg)]" />
    );
  }

  const active = slides[index];

  return (
    <div className="relative overflow-hidden rounded-[28px] shadow-[var(--shadow-lg)]">
      <div
        className="relative min-h-[262px] px-9 pt-8 pb-8 text-white"
        style={{ background: active.background }}
      >
        <div className="absolute inset-0 bg-linear-to-r from-black/45 via-black/10 to-transparent" />
        <div className="absolute right-[-8px] bottom-[-48px] text-[170px] leading-none font-black text-white/[0.07]">
          {active.kanji}
        </div>
        <div className="relative z-10 max-w-[560px]">
          <div className="mb-3 flex flex-wrap items-center gap-2">
            <Badge className="bg-white/20 text-white backdrop-blur-sm" variant="outline">
              {active.tag}
            </Badge>
            <Badge className="bg-white/18 text-white" variant="outline">
              2026 SUMMER
            </Badge>
            <Badge className="bg-white/18 text-white" variant="outline">
              TV Animation
            </Badge>
          </div>
          <h2 className="text-[30px] font-black">{active.nameCn ?? active.name}</h2>
          <p className="mt-3 text-sm leading-7 text-white/90">{active.summary}</p>
          <div className="mt-5 flex flex-wrap gap-3">
            <Button
              size="lg"
              className="bg-white text-[var(--mint-600)] shadow-none hover:bg-white/95"
            >
              <Play className="size-4 fill-current" />
              继续播放 {active.nextEpisode ? `EP${active.nextEpisode.sort}` : ""}
            </Button>
            <Button
              size="lg"
              variant="outline"
              className="border-white/35 bg-white/15 text-white backdrop-blur-sm hover:bg-white/20"
            >
              <Heart className="size-4" />
              追番
            </Button>
            <Button
              asChild
              size="lg"
              variant="outline"
              className="border-white/30 bg-white/10 text-white hover:bg-white/15"
            >
              <Link to={`/subject/${active.subjectId}`}>查看详情</Link>
            </Button>
          </div>
        </div>
      </div>

      {slides.length > 1 ? (
        <>
          <button
            type="button"
            onClick={() => setIndex((value) => (value - 1 + slides.length) % slides.length)}
            className="absolute top-1/2 left-4 grid size-10 -translate-y-1/2 place-items-center rounded-full border border-white/35 bg-white/20 text-white backdrop-blur-sm"
          >
            <ChevronLeft className="size-4" />
          </button>
          <button
            type="button"
            onClick={() => setIndex((value) => (value + 1) % slides.length)}
            className="absolute top-1/2 right-4 grid size-10 -translate-y-1/2 place-items-center rounded-full border border-white/35 bg-white/20 text-white backdrop-blur-sm"
          >
            <ChevronRight className="size-4" />
          </button>
          <div className="absolute right-6 bottom-5 flex gap-2">
            {slides.map((slide, slideIndex) => (
              <button
                key={slide.subjectId}
                type="button"
                onClick={() => setIndex(slideIndex)}
                className={
                  slideIndex === index
                    ? "h-2 w-6 rounded-full bg-white"
                    : "size-2 rounded-full bg-white/45"
                }
              />
            ))}
          </div>
        </>
      ) : null}
    </div>
  );
}
