import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { Play } from "lucide-react";
import { artGradient, artKanji } from "@/data/artwork";
import { cn } from "@/lib/utils";

type PosterProps = {
  index: number;
  href?: string;
  kanji?: string;
  /** top-left floating pill (e.g. episode count) */
  badge?: ReactNode;
  /** top-right corner (e.g. status tag) */
  corner?: ReactNode;
  /** title rendered as an overlay on the bottom of the cover */
  overlayTitle?: ReactNode;
  imageUrl?: string;
  /** bottom-of-cover bar (e.g. "12 集 · 4.2 GB") */
  footer?: ReactNode;
  /** content rendered below the cover */
  body?: ReactNode;
  showPlay?: boolean;
  dim?: boolean;
  /** fixed width for horizontal rails; defaults to fluid grid width */
  width?: number;
  className?: string;
};

export function Poster({
  index,
  href,
  kanji,
  imageUrl,
  badge,
  corner,
  overlayTitle,
  footer,
  body,
  showPlay = true,
  dim = false,
  width,
  className
}: PosterProps) {
  const inner = (
    <>
      <div
        className="relative aspect-3/4 overflow-hidden rounded-[14px] shadow-[var(--shadow-md)] transition group-hover:shadow-[var(--shadow-lg)]"
        style={{ background: artGradient(index), filter: dim ? "grayscale(.35)" : undefined }}
      >
        {imageUrl ? (
          <img
            src={imageUrl}
            alt={typeof overlayTitle === "string" ? overlayTitle : ""}
            className="absolute inset-0 size-full object-cover"
            loading="lazy"
            referrerPolicy="no-referrer"
          />
        ) : (
          <span className="absolute inset-0 grid place-items-center text-6xl font-extrabold text-white/20 [text-shadow:0_2px_10px_rgba(0,0,0,.15)]">
            {kanji ?? artKanji(index)}
          </span>
        )}
        <div className="absolute inset-0 bg-[linear-gradient(180deg,transparent_38%,rgba(0,0,0,.62))]" />
        {badge ? <div className="absolute top-2 left-2 z-[2]">{badge}</div> : null}
        {corner ? <div className="absolute top-2 right-2 z-[2]">{corner}</div> : null}
        {showPlay ? (
          <span className="absolute inset-0 grid place-items-center opacity-0 transition group-hover:opacity-100">
            <span className="text-mint-600 grid size-[46px] place-items-center rounded-full bg-white/90 shadow-[var(--shadow-md)]">
              <Play className="size-5 fill-current" />
            </span>
          </span>
        ) : null}
        {overlayTitle ? (
          <div className="absolute right-3 bottom-3 left-3 z-[2] line-clamp-2 text-[13px] font-extrabold text-white [text-shadow:0_1px_5px_rgba(0,0,0,.55)]">
            {overlayTitle}
          </div>
        ) : null}
        {footer ? (
          <div className="absolute right-2 bottom-2 left-2 z-[2] flex items-center justify-between text-[11.5px] font-bold text-white">
            {footer}
          </div>
        ) : null}
      </div>
      {body ? <div className="px-0.5 pt-2">{body}</div> : null}
    </>
  );

  const classes = cn(
    "group flex flex-col transition-transform duration-200 hover:-translate-y-0.5",
    width ? "shrink-0" : "w-auto",
    href ? "cursor-pointer" : "",
    className
  );
  const style = width ? { width } : undefined;

  if (href) {
    return (
      <Link to={href} className={classes} style={style}>
        {inner}
      </Link>
    );
  }
  return (
    <div className={classes} style={style}>
      {inner}
    </div>
  );
}
