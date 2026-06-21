import { useState } from "react";
import { ExternalLink, Film, ListChecks, Play } from "lucide-react";
import { Link } from "react-router-dom";
import { SUBJECT_DEMO, type SubjectStatus } from "@/data/subject";
import { StarRow } from "@/components/melon/RatingStars";
import { SeasonChip } from "@/components/melon/SeasonChip";
import { IconButton } from "@/components/melon/layout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { artGradient } from "@/data/artwork";
import { cn } from "@/lib/utils";

const STATUS_OPTIONS: { key: SubjectStatus; label: string }[] = [
  { key: "wish", label: "想看" },
  { key: "watching", label: "在看" },
  { key: "hold", label: "搁置" },
  { key: "done", label: "看过" },
  { key: "drop", label: "抛弃" }
];

const STAT_COLORS: Record<string, string> = {
  wish: "var(--sky-400)",
  watching: "var(--mint-400)",
  hold: "var(--gold-400)",
  done: "var(--grape-400)",
  drop: "var(--cherry-400)"
};

export function SubjectHero({
  onOpenEpisodes,
  onOpenPv
}: {
  onOpenEpisodes: () => void;
  onOpenPv: () => void;
}) {
  const subject = SUBJECT_DEMO;
  const [status, setStatus] = useState<SubjectStatus | null>(subject.defaultStatus);

  return (
    <div className="border-line bg-surface relative grid grid-cols-[230px_1fr] gap-16 overflow-hidden rounded-[20px] border p-7 shadow-[var(--shadow-sm)] max-[1080px]:grid-cols-[160px_1fr] max-[1080px]:gap-7">
      <div className="absolute inset-0 opacity-[0.07] [background:radial-gradient(ellipse_650px_460px_at_22%_32%,#ffb84d,transparent),radial-gradient(ellipse_500px_360px_at_72%_52%,var(--mint-300),transparent),radial-gradient(ellipse_380px_300px_at_55%_92%,#ff8a5b,transparent)]" />

      <a
        href="https://bgm.tv"
        target="_blank"
        rel="noreferrer"
        className="text-mint-600 border-mint-200 bg-mint-50 hover:bg-mint-100 absolute top-3.5 right-[18px] z-[2] inline-flex items-center gap-1.5 rounded-full border px-[11px] py-[5px] text-xs font-bold"
      >
        <ExternalLink className="size-4" />在 Bangumi 打开
      </a>

      <div
        className="relative aspect-3/4 self-stretch overflow-hidden rounded-[14px] shadow-[0_24px_60px_rgba(28,70,55,.25),0_0_0_1px_rgba(0,0,0,.05)]"
        style={{ background: artGradient(0) }}
      >
        <span className="absolute inset-0 grid place-items-center text-[72px] font-extrabold text-white/10">
          {subject.kanji}
        </span>
      </div>

      <div className="relative flex min-w-0 flex-col gap-2">
        <h1 className="pr-[120px] text-2xl font-extrabold tracking-[-0.01em]">{subject.title}</h1>
        <div className="text-ink-faint mb-0.5 text-[12.5px] font-semibold">{subject.alt}</div>

        <div className="flex flex-wrap gap-1.5">
          <SeasonChip season="summer" label={subject.seasonLabel} />
          <Badge variant="mint">{subject.tags[0]}</Badge>
          <Badge variant="outline">{subject.tags[1]}</Badge>
          <Badge variant="grape">{subject.tags[2]}</Badge>
          <Badge variant="grape">{subject.tags[3]}</Badge>
          <Badge variant="grape">{subject.tags[4]}</Badge>
          <Badge variant="outline">{subject.tags[5]}</Badge>
        </div>

        <div className="text-ink-soft text-[13.5px] leading-normal font-medium">
          连载至 <span className="text-mint-500 text-[15px] font-extrabold">{subject.current}</span>{" "}
          / 预定全 {subject.total} 话 · {subject.schedule}
        </div>

        <div className="flex flex-col items-start gap-1">
          <div className="flex items-center gap-3.5">
            <span className="inline-flex items-baseline text-[48px] leading-none font-extrabold tracking-[-0.03em]">
              {subject.score}
              <small className="text-ink-faint ml-[3px] text-xl font-bold">/10</small>
            </span>
            <div className="inline-flex items-center gap-1.5 rounded-[14px] border border-[rgba(255,107,129,.2)] bg-[linear-gradient(135deg,rgba(255,107,129,.08),rgba(255,107,129,.14))] px-3.5 py-2">
              <span className="text-cherry-500 text-[18px] font-extrabold">#{subject.rank}</span>
              <span className="text-cherry-600 text-[11px] leading-tight font-semibold opacity-80">
                Bangumi
                <br />
                Rank
              </span>
            </div>
            <div className="flex flex-col items-start gap-0.5">
              <StarRow value={Math.round(subject.score / 2)} size={16} />
              <div className="text-ink-faint text-xs font-medium">{subject.ratingCount} 人评分</div>
            </div>
          </div>
        </div>

        <div className="flex flex-col gap-2 py-0.5">
          <div className="bg-surface-3 flex h-2 overflow-hidden rounded-full">
            {subject.stats.map((stat) => (
              <div
                key={stat.key}
                style={{ width: `${stat.pct}%`, background: STAT_COLORS[stat.key] }}
              />
            ))}
          </div>
          <div className="text-ink-faint flex flex-wrap gap-x-5 text-xs leading-[2.1] font-medium">
            {subject.stats.map((stat) => (
              <span key={stat.key}>
                <span
                  className="mr-1.5 inline-block size-[9px] rounded-[3px] align-middle"
                  style={{ background: STAT_COLORS[stat.key] }}
                />
                <b className="text-ink-soft mr-0.5 font-extrabold">{stat.count}</b> {stat.label}
              </span>
            ))}
          </div>
        </div>

        <div className="bg-line my-1.5 h-px" />

        <div className="flex flex-wrap items-center gap-2">
          <Button asChild>
            <Link to="/player">
              <Play className="size-[18px] fill-current" />
              继续播放 EP{String(subject.currentEp).padStart(2, "0")}
            </Link>
          </Button>
          <IconButton title="选集" onClick={onOpenEpisodes}>
            <ListChecks />
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
                  onClick={() => setStatus(option.key)}
                  className={cn(
                    "rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                    status === option.key
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
              onClick={() => setStatus(null)}
              className="text-cherry-500 hover:bg-cherry-500/10 rounded-full px-3.5 py-2 text-[13px] font-bold transition"
            >
              取消追番
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
