import { cn } from "@/lib/utils";

const seasonGradients: Record<string, string> = {
  default: "linear-gradient(135deg,var(--mint-400),var(--sky-400))",
  summer: "linear-gradient(135deg,#ffd76b,#ff8a5b)",
  winter: "linear-gradient(135deg,#9fd9ff,#6aa6f0)",
  spring: "linear-gradient(135deg,#ffb6c8,#a7e9cf)",
  fall: "linear-gradient(135deg,#ffb36b,#d98a4a)"
};

export function SeasonChip({
  label,
  season = "default",
  size = "default",
  className
}: {
  label: string;
  season?: keyof typeof seasonGradients;
  size?: "default" | "sm";
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full font-extrabold tracking-[0.04em] text-white",
        size === "sm" ? "px-2 py-0.5 text-[10px]" : "px-[11px] py-1 text-xs",
        className
      )}
      style={{ background: seasonGradients[season] ?? seasonGradients.default }}
    >
      {label}
    </span>
  );
}
