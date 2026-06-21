import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center gap-1 rounded-full px-2.5 py-[3px] text-[11.5px] font-bold whitespace-nowrap",
  {
    variants: {
      variant: {
        default: "bg-surface-3 text-ink-soft",
        outline: "border border-line-strong bg-transparent text-ink-soft",
        mint: "bg-mint-100 text-mint-600 dark:bg-mint-400/20",
        cherry: "bg-[#ffe6ea] text-cherry-600 dark:bg-cherry-500/20",
        sky: "bg-[#e3efff] text-[#3f74c4] dark:bg-sky-500/20 dark:text-sky-300",
        grape: "bg-[#efeaff] text-[#6f57c4] dark:bg-grape-500/20 dark:text-grape-400",
        gold: "bg-[#fff2d6] text-[#b5742a] dark:bg-gold-500/20 dark:text-gold-400"
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
