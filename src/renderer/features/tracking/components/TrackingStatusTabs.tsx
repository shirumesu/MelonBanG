import type { CollectionStatus } from "@shared/contracts/bangumi";
import { Bookmark, CheckCircle2, Eye, PauseCircle, XCircle } from "lucide-react";
import type { ComponentType, ReactElement } from "react";
import { TabsList, TabsTrigger } from "@/components/ui/tabs";

const statusConfig: Array<{
  status: CollectionStatus;
  label: string;
  icon: ComponentType<{ className?: string }>;
}> = [
  { status: "watching", label: "在看", icon: Eye },
  { status: "wish", label: "想看", icon: Bookmark },
  { status: "on_hold", label: "搁置", icon: PauseCircle },
  { status: "completed", label: "看过", icon: CheckCircle2 },
  { status: "dropped", label: "抛弃", icon: XCircle }
];

export function TrackingStatusTabs({
  counts,
  value
}: {
  counts: Record<CollectionStatus, number>;
  value: CollectionStatus;
}): ReactElement {
  return (
    <TabsList className="flex flex-wrap gap-1 rounded-full">
      {statusConfig.map(({ status, label, icon: Icon }) => (
        <TabsTrigger key={status} value={status} className="min-w-[110px] justify-center">
          <Icon className="size-4" />
          <span>{label}</span>
          <span
            className={
              value === status
                ? "rounded-full bg-white/50 px-2 py-0.5 text-[11px]"
                : "bg-secondary text-muted-foreground rounded-full px-2 py-0.5 text-[11px]"
            }
          >
            {counts[status]}
          </span>
        </TabsTrigger>
      ))}
    </TabsList>
  );
}
