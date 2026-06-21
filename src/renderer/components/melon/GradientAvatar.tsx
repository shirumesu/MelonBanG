import { cn } from "@/lib/utils";

const sizeClasses = {
  sm: "size-[30px] text-xs",
  md: "size-10 text-[15px]",
  lg: "size-14 text-xl"
} as const;

export function GradientAvatar({
  initial,
  gradient,
  size = "md",
  className
}: {
  initial: string;
  gradient?: string;
  size?: keyof typeof sizeClasses;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "grid shrink-0 place-items-center overflow-hidden rounded-full font-extrabold text-white",
        sizeClasses[size],
        className
      )}
      style={{ background: gradient ?? "linear-gradient(135deg,var(--grape-400),var(--sky-500))" }}
    >
      {initial}
    </span>
  );
}
