import type { ReactNode } from "react";
import { Poster } from "@/components/melon/Poster";
import { Badge } from "@/components/ui/badge";
import type { TrackingCard as TrackingCardData, TrackingStatus } from "@/data/tracking";

function ProgressBar({ pct, gold = false }: { pct: number; gold?: boolean }) {
  return (
    <div className="bg-surface-3 mt-[7px] h-1 overflow-hidden rounded-full">
      <div
        className="h-full rounded-full"
        style={{
          width: `${pct}%`,
          background: gold
            ? "linear-gradient(90deg,#ffd56b,#ffb83d)"
            : "linear-gradient(90deg,var(--mint-400),var(--mint-300))"
        }}
      />
    </div>
  );
}

function Sub({ children }: { children: ReactNode }) {
  return (
    <div className="text-ink-faint mt-2 flex items-center justify-between text-xs font-semibold">
      {children}
    </div>
  );
}

const CORNER: Record<TrackingStatus, ReactNode> = {
  watching: (
    <Badge variant="mint" className="text-[10px]">
      在看
    </Badge>
  ),
  wish: (
    <Badge variant="gold" className="text-[10px]">
      想看
    </Badge>
  ),
  hold: (
    <Badge variant="gold" className="text-[10px]">
      搁置
    </Badge>
  ),
  done: (
    <Badge variant="sky" className="text-[10px]">
      看过
    </Badge>
  ),
  drop: (
    <Badge variant="cherry" className="text-[10px]">
      抛弃
    </Badge>
  )
};

function body(status: TrackingStatus, card: TrackingCardData): ReactNode {
  const pct = Math.round((card.current / card.total) * 100);
  switch (status) {
    case "watching":
      return (
        <>
          <div className="text-ink-soft text-xs font-bold">
            看到 <b className="text-mint-600">{card.current}</b> / 全{card.total}话
          </div>
          <ProgressBar pct={pct} />
          <Sub>
            <span>★ {card.score}</span>
            <span>更新于 {card.updated}</span>
          </Sub>
        </>
      );
    case "wish":
      return (
        <>
          <div className="text-ink-faint text-xs font-bold">
            预定全{card.total}话 · {card.air}
          </div>
          <Sub>
            <span>★ {card.score}</span>
            <span>{card.season}</span>
          </Sub>
        </>
      );
    case "hold":
      return (
        <>
          <div className="text-ink-soft text-xs font-bold">
            停在 <b className="text-mint-600">{card.current}</b> / 全{card.total}话
          </div>
          <ProgressBar pct={pct} gold />
          <Sub>
            <span className="text-ink-faint">已搁置 {card.updated}</span>
          </Sub>
        </>
      );
    case "done":
      return (
        <>
          <div className="text-ink-faint text-xs font-bold">全{card.total}话 已看完</div>
          <Sub>
            <span className="text-gold-500 font-extrabold">我的评分 {card.myScore}</span>
            <span>{card.season}</span>
          </Sub>
        </>
      );
    case "drop":
      return (
        <>
          <div className="text-ink-faint text-xs font-bold">
            看到 {card.current} / 全{card.total}话 后弃
          </div>
          <Sub>
            <span className="text-ink-faint">★ {card.score}</span>
            <span>{card.season}</span>
          </Sub>
        </>
      );
  }
}

export function TrackingCard({ status, card }: { status: TrackingStatus; card: TrackingCardData }) {
  return (
    <Poster
      index={card.index}
      href={`/subject/${card.index}`}
      overlayTitle={card.title}
      corner={CORNER[status]}
      dim={status === "drop"}
      body={body(status, card)}
    />
  );
}
