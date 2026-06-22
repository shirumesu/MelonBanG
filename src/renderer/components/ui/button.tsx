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
          "from-mint-400 to-mint-500 bg-linear-to-br text-white shadow-[0_8px_18px_rgba(34,179,136,.32)] hover:-translate-y-0.5 hover:brightness-105",
        cherry:
          "from-cherry-400 to-cherry-500 bg-linear-to-br text-white shadow-[0_8px_18px_rgba(255,107,129,.3)] hover:-translate-y-0.5 hover:brightness-105",
        soft: "bg-mint-50 text-mint-600 border-mint-200 hover:bg-mint-100 hover:-translate-y-0.5 border",
        secondary: "bg-secondary text-secondary-foreground hover:bg-surface-3 hover:-translate-y-0.5",
        outline:
          "bg-card text-foreground border-line-strong hover:border-mint-300 hover:text-mint-600 hover:-translate-y-0.5 border",
        ghost: "text-muted-foreground hover:bg-secondary hover:text-foreground bg-transparent"
      },
      size: {
        default: "h-10 px-[18px] py-2.5",
        sm: "h-8 gap-1.5 px-[13px] text-xs",
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
