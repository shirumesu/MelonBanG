import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 rounded-full text-sm font-extrabold whitespace-nowrap transition disabled:pointer-events-none disabled:opacity-60 [&_svg]:pointer-events-none [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default:
          "bg-linear-to-br from-[var(--mint-400)] to-[var(--mint-500)] text-white shadow-[0_8px_18px_rgba(34,179,136,.32)] hover:brightness-105",
        secondary: "bg-secondary text-secondary-foreground hover:bg-[var(--surface-3)]",
        outline:
          "bg-card text-foreground border border-[var(--line-strong)] hover:border-[var(--mint-300)]",
        ghost: "text-muted-foreground hover:bg-secondary hover:text-foreground bg-transparent",
        cherry:
          "bg-linear-to-br from-[var(--cherry-400)] to-[var(--cherry-500)] text-white shadow-[0_8px_18px_rgba(255,107,129,.32)] hover:brightness-105"
      },
      size: {
        default: "h-10 px-5 py-2.5",
        sm: "h-8 px-3.5 text-xs",
        lg: "h-12 px-6 text-[15px]"
      }
    },
    defaultVariants: {
      variant: "default",
      size: "default"
    }
  }
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>, VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return (
      <Comp className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props} />
    );
  }
);
Button.displayName = "Button";

export { Button };
