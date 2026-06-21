import type { ReactElement } from "react";
import { cn } from "@/lib/utils";

const gradients = [
  ["#7bd0c1", "#3b82c4"],
  ["#f7a8b8", "#9b6ad8"],
  ["#ffd56b", "#ff7a5b"],
  ["#9be7c4", "#3aa17e"],
  ["#a9c7ff", "#6a6ae0"],
  ["#ffb3c7", "#ff6b9d"],
  ["#c0a8ff", "#7d5fe0"],
  ["#8fe3d6", "#3aa1a8"],
  ["#ffd0a8", "#ff9a5b"],
  ["#b8e986", "#5aa84a"],
  ["#ff9eb5", "#c25b8e"],
  ["#86c5ff", "#3f74c4"]
] as const;

export function ArtworkCard({
  id,
  title,
  className,
  imageUrl,
  overlay = true
}: {
  id: number;
  title: string;
  className?: string;
  imageUrl?: string;
  overlay?: boolean;
}): ReactElement {
  const gradient = gradients[id % gradients.length];
  const mark = extractMark(title);

  return (
    <div
      className={cn(
        "bg-card relative overflow-hidden rounded-[14px] shadow-[var(--shadow-md)]",
        className
      )}
      style={{ background: `linear-gradient(135deg, ${gradient[0]}, ${gradient[1]})` }}
    >
      {imageUrl ? (
        <img
          src={imageUrl}
          alt={title}
          className="absolute inset-0 size-full object-cover"
          loading="lazy"
          referrerPolicy="no-referrer"
        />
      ) : null}
      {!imageUrl ? (
        <span className="absolute inset-0 grid place-items-center text-6xl font-black text-white/20">
          {mark}
        </span>
      ) : null}
      {overlay ? (
        <div className="absolute inset-0 bg-linear-to-b from-transparent via-transparent to-black/50" />
      ) : null}
    </div>
  );
}

function extractMark(title: string): string {
  const first = Array.from(title).find((char) =>
    /[\p{Script=Han}\p{Script=Katakana}\p{Script=Hiragana}A-Za-z0-9]/u.test(char)
  );
  return first?.toUpperCase() ?? "M";
}
