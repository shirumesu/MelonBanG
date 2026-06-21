import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center rounded-full px-2.5 py-1 text-[11px] font-extrabold tracking-[0.01em] whitespace-nowrap",
  {
    variants: {
      variant: {
        default: "bg-secondary text-secondary-foreground",
        outline: "text-muted-foreground border border-[var(--line-strong)] bg-transparent",
        mint: "bg-[var(--mint-100)] text-[var(--mint-600)]",
        cherry: "bg-[#ffe6ea] text-[var(--cherry-600)]",
        sky: "bg-[#e3efff] text-[#3f74c4]",
        grape: "bg-[#efeaff] text-[#6f57c4]",
        gold: "bg-[#fff2d6] text-[#b5742a]"
      }
    },
    defaultVariants: {
      variant: "default"
    }
  }
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLDivElement>, VariantProps<typeof badgeVariants> {}

function Badge({ className, variant, ...props }: BadgeProps): JSX.Element {
  return <div className={cn(badgeVariants({ variant }), className)} {...props} />;
}

export { Badge };
