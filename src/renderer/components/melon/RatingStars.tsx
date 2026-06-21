import { useRef, useState } from "react";
import { Star } from "lucide-react";
import { RATE_LABELS } from "@/data/subject";
import { cn } from "@/lib/utils";

function StarCell({ fill, size }: { fill: number; size: number }) {
  const clamped = Math.max(0, Math.min(1, fill));
  return (
    <span className="relative inline-flex" style={{ width: size, height: size }}>
      <Star
        className="absolute inset-0"
        style={{
          width: size,
          height: size,
          fill: "rgba(255,184,61,0.14)",
          stroke: "var(--gold-500)",
          strokeWidth: 1.6
        }}
      />
      <span
        className="absolute inset-0 overflow-hidden"
        style={{ clipPath: `inset(0 ${(1 - clamped) * 100}% 0 0)` }}
      >
        <Star
          className="text-gold-500 fill-current"
          style={{ width: size, height: size }}
        />
      </span>
    </span>
  );
}

export function StarRow({
  value,
  size = 16,
  className
}: {
  value: number;
  size?: number;
  className?: string;
}) {
  return (
    <div className={cn("inline-flex gap-0.5", className)}>
      {Array.from({ length: 5 }, (_, i) => (
        <StarCell key={i} fill={value - i} size={size} />
      ))}
    </div>
  );
}

export function InteractiveRating() {
  const [committed, setCommitted] = useState(0);
  const [hover, setHover] = useState(0);
  const rowRef = useRef<HTMLDivElement>(null);

  const display = hover || committed;
  const score10 = Math.round(display * 2);
  const label = score10 ? (RATE_LABELS[score10] ?? "") : "点击评分";

  const ratingFromEvent = (event: React.MouseEvent): number => {
    const rect = rowRef.current?.getBoundingClientRect();
    if (!rect) {
      return 0;
    }
    const x = event.clientX - rect.left;
    const raw = Math.round((x / (rect.width / 5)) * 2) / 2;
    return Math.max(0.5, Math.min(5, raw));
  };

  return (
    <span className="inline-flex items-center">
      <div
        ref={rowRef}
        className="inline-flex cursor-pointer items-center gap-1.5 select-none"
        onMouseMove={(event) => setHover(ratingFromEvent(event))}
        onMouseLeave={() => setHover(0)}
        onClick={(event) => setCommitted(ratingFromEvent(event))}
      >
        {Array.from({ length: 5 }, (_, i) => (
          <StarCell key={i} fill={display - i} size={24} />
        ))}
      </div>
      <span className="border-line ml-2 inline-flex items-center gap-1.5 border-l pl-2.5">
        <span className="text-gold-500 text-base font-extrabold">{score10 || ""}</span>
        <span className="text-ink-soft text-[13px] font-semibold">{label}</span>
      </span>
    </span>
  );
}
