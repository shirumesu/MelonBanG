import * as React from "react";
import { cn } from "@/lib/utils";

const Input = React.forwardRef<HTMLInputElement, React.ComponentProps<"input">>(
  ({ className, ...props }, ref) => (
    <input
      ref={ref}
      className={cn(
        "border-input bg-card text-foreground placeholder:text-muted-foreground flex h-11 w-full rounded-full border px-4 py-2 text-sm font-semibold shadow-[var(--shadow-sm)] transition outline-none focus-visible:border-[var(--mint-300)]",
        className
      )}
      {...props}
    />
  )
);
Input.displayName = "Input";

export { Input };
