import type { ReactNode } from "react";
import { TitleBar } from "./TitleBar";

export function WindowFrame({ crumb, children }: { crumb?: string; children: ReactNode }) {
  return (
    <div className="grid h-full grid-rows-[40px_1fr] overflow-hidden">
      <TitleBar crumb={crumb} />
      <div className="min-h-0">{children}</div>
    </div>
  );
}
