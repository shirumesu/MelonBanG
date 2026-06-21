import type { ReactElement, ReactNode } from "react";
import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

export function PageHeader({
  title,
  subtitle,
  actions,
  searchValue,
  onSearchChange,
  searchPlaceholder = "搜索…"
}: {
  title: string;
  subtitle?: string;
  actions?: ReactNode;
  searchValue?: string;
  onSearchChange?: (value: string) => void;
  searchPlaceholder?: string;
}): ReactElement {
  return (
    <div className="from-background via-background sticky top-0 z-20 flex items-center gap-4 bg-linear-to-b to-transparent py-6">
      <div>
        <div className="text-[26px] font-black tracking-[0.01em]">{title}</div>
        {subtitle ? (
          <div className="text-muted-foreground mt-1 text-sm font-semibold">{subtitle}</div>
        ) : null}
      </div>
      <div className="ml-auto flex items-center gap-3">
        {typeof searchValue === "string" && onSearchChange ? (
          <div className="relative min-w-[280px]">
            <Search className="text-muted-foreground pointer-events-none absolute top-1/2 left-4 size-4 -translate-y-1/2" />
            <Input
              value={searchValue}
              onChange={(event) => onSearchChange(event.target.value)}
              placeholder={searchPlaceholder}
              className="pr-4 pl-11"
            />
          </div>
        ) : null}
        {actions}
      </div>
    </div>
  );
}

export function SectionTitle({
  title,
  subtitle,
  action
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
}): ReactElement {
  return (
    <div className="mb-4 flex items-end gap-3">
      <div className="text-[17px] font-black">{title}</div>
      {subtitle ? (
        <div className="text-muted-foreground text-xs font-semibold">{subtitle}</div>
      ) : null}
      <div className="ml-auto">{action}</div>
    </div>
  );
}

export function PageSection({
  className,
  children
}: {
  className?: string;
  children: ReactNode;
}): ReactElement {
  return <section className={cn("mt-7", className)}>{children}</section>;
}
