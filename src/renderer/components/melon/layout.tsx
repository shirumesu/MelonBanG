import type { ReactNode } from "react";
import { Search } from "lucide-react";
import { cn } from "@/lib/utils";

export function Topbar({
  title,
  subtitle,
  titleSize = 22,
  leading,
  children
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  titleSize?: number;
  leading?: ReactNode;
  children?: ReactNode;
}) {
  return (
    <div className="sticky top-0 z-20 flex min-w-0 items-center gap-3.5 bg-[linear-gradient(180deg,var(--bg)_60%,transparent)] px-[26px] py-4">
      {leading}
      <div className="min-w-0">
        <div className="font-extrabold tracking-[0.01em]" style={{ fontSize: titleSize }}>
          {title}
        </div>
        {subtitle ? (
          <div className="text-ink-faint mt-px text-[12.5px] font-semibold">{subtitle}</div>
        ) : null}
      </div>
      {children ? (
        <div className="ml-auto flex min-w-0 items-center gap-3.5">{children}</div>
      ) : null}
    </div>
  );
}

export function SearchBox({
  placeholder = "搜索…",
  value,
  onChange,
  className
}: {
  placeholder?: string;
  value?: string;
  onChange?: (value: string) => void;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "border-line bg-surface text-ink-faint flex min-w-[260px] items-center gap-2.5 rounded-full border px-3.5 py-2.5 shadow-[var(--shadow-sm)]",
        className
      )}
    >
      <Search className="size-[17px]" />
      <input
        value={value}
        onChange={(event) => onChange?.(event.target.value)}
        placeholder={placeholder}
        className="text-ink placeholder:text-ink-faint min-w-0 flex-1 bg-transparent text-[13.5px] outline-none"
      />
      <kbd className="bg-surface-3 text-ink-faint rounded-md px-1.5 py-0.5 text-[10.5px]">
        Ctrl K
      </kbd>
    </div>
  );
}

export function SyncPill({ stale = false, label }: { stale?: boolean; label?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-[7px] rounded-full border px-3 py-[7px] text-xs font-bold",
        stale
          ? "border-[#ffdfa8] bg-[#fff5e6] text-[#b5742a]"
          : "border-mint-200 bg-mint-50 text-mint-600"
      )}
    >
      <span
        className={cn(
          "size-[7px] rounded-full",
          stale ? "bg-gold-500" : "bg-mint-400 animate-melon-pulse"
        )}
      />
      {label ?? (stale ? "缓存离线" : "已同步")}
    </span>
  );
}

export function IconButton({
  children,
  badge,
  className,
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & { badge?: ReactNode }) {
  return (
    <button
      type="button"
      className={cn(
        "border-line bg-surface text-ink-soft hover:border-mint-200 hover:text-ink relative grid size-10 place-items-center rounded-[13px] border shadow-[var(--shadow-sm)] transition [&_svg]:size-5",
        className
      )}
      {...props}
    >
      {children}
      {badge != null ? (
        <span className="bg-cherry-500 absolute -top-1 -right-1 grid h-[17px] min-w-[17px] place-items-center rounded-full px-1 text-[10px] font-extrabold text-white shadow-[0_0_0_2px_var(--bg)]">
          {badge}
        </span>
      ) : null}
    </button>
  );
}

export function SectionHead({
  title,
  sub,
  action,
  className
}: {
  title: ReactNode;
  sub?: ReactNode;
  action?: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("mb-3.5 flex items-end gap-3", className)}>
      <div className="flex items-center gap-2 text-[17px] font-extrabold">{title}</div>
      {sub ? <div className="text-ink-faint text-[12.5px] font-semibold">{sub}</div> : null}
      {action ? <div className="ml-auto">{action}</div> : null}
    </div>
  );
}

export function PageContent({
  narrow = false,
  className,
  children
}: {
  narrow?: boolean;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div
      className={cn(
        "min-w-0 flex-1 overflow-auto px-[26px] pt-1.5 pb-10",
        narrow && "mx-auto w-full max-w-[1180px]",
        className
      )}
    >
      {children}
    </div>
  );
}

export function Section({ className, children }: { className?: string; children: ReactNode }) {
  return <section className={cn("mt-[26px]", className)}>{children}</section>;
}
