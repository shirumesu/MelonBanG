import { Compass, Download, Heart, Settings } from "lucide-react";
import { NavLink } from "react-router-dom";
import { useAppState } from "../AppStateProvider";
import { GradientAvatar } from "@/components/melon/GradientAvatar";
import { cn } from "@/lib/utils";

function MelonMark({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <circle cx="12" cy="13" r="8" />
      <path d="M12 5c-1.3 0-2.4.5-3.2 1.3M15.2 6.3A4.5 4.5 0 0 0 12 5" />
      <path d="M9 10v6M12 10v6M15 10v6" />
    </svg>
  );
}

const navItems = [
  { to: "/home", label: "探索", icon: Compass, pill: undefined as string | undefined },
  { to: "/tracking", label: "追番", icon: Heart, pill: "128" },
  { to: "/cache", label: "缓存", icon: Download, pill: "3" }
];

function navClass({ isActive }: { isActive: boolean }): string {
  return cn(
    "relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition",
    isActive
      ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_8px_18px_rgba(34,179,136,.3)]"
      : "text-ink-soft hover:bg-surface-2 hover:text-ink"
  );
}

export function Sidebar() {
  const { session } = useAppState();
  const nickname = session?.nickname ?? "melonbang";
  const username = session?.username ?? "guest";

  return (
    <aside className="border-line flex min-h-0 flex-col gap-1 border-r bg-[linear-gradient(180deg,rgba(255,255,255,.75),rgba(255,255,255,.45))] px-3.5 py-4 dark:bg-[linear-gradient(180deg,rgba(255,255,255,.04),rgba(255,255,255,.01))]">
      <div className="flex items-center gap-2.5 px-2 pt-2 pb-3.5">
        <span className="text-on-accent grid size-[34px] place-items-center rounded-[11px] bg-[linear-gradient(135deg,var(--mint-300),var(--mint-500))] shadow-[0_6px_14px_rgba(34,179,136,.35),inset_0_0_0_2px_rgba(255,255,255,.45)]">
          <MelonMark className="size-[18px]" />
        </span>
        <span>
          <b className="block text-[17px] font-extrabold tracking-[0.02em]">melonbang</b>
          <small className="text-ink-faint block text-[10px] font-semibold tracking-[0.15em] uppercase">
            anime tracker
          </small>
        </span>
      </div>

      <div className="text-ink-faint px-2.5 pt-2.5 pb-1 text-[10px] font-bold tracking-[0.14em] uppercase">
        浏览
      </div>
      <nav className="flex flex-col gap-1">
        {navItems.map(({ to, label, icon: Icon, pill }) => (
          <NavLink key={to} to={to} className={navClass}>
            {({ isActive }) => (
              <>
                <Icon className="size-5 opacity-85" />
                <span>{label}</span>
                {pill ? (
                  <span
                    className={cn(
                      "ml-auto rounded-full px-2 py-0.5 text-[11px] font-extrabold",
                      isActive ? "text-on-accent bg-white/45" : "text-mint-600 bg-white/60"
                    )}
                  >
                    {pill}
                  </span>
                ) : null}
              </>
            )}
          </NavLink>
        ))}
      </nav>

      <div className="flex-1" />

      <NavLink to="/settings" className={navClass}>
        <Settings className="size-5 opacity-85" />
        <span>设置</span>
      </NavLink>

      <NavLink
        to="/settings"
        className="border-line bg-surface hover:border-mint-200 flex items-center gap-2.5 rounded-[14px] border p-2.5 shadow-[var(--shadow-sm)] transition"
      >
        <GradientAvatar initial={nickname.slice(0, 1)} />
        <span className="min-w-0">
          <b className="block truncate text-[13px] leading-tight">{nickname}</b>
          <span className="text-ink-faint text-[11px]">@{username}</span>
        </span>
        <span className="bg-mint-400 ml-auto size-2 rounded-full shadow-[0_0_0_3px_var(--mint-100)]" />
      </NavLink>
    </aside>
  );
}
