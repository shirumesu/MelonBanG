import { Bell, Compass, Search, Settings, Sparkles, Tv } from "lucide-react";
import { NavLink, Outlet } from "react-router-dom";
import { useAppState } from "../AppStateProvider";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { cn } from "../../lib/utils";

const navItems = [
  { to: "/home", label: "探索", icon: Compass, note: "Home" },
  { to: "/tracking", label: "追番", icon: Tv, note: "Tracking" },
  { to: "/search", label: "搜索", icon: Search, note: "Search" },
  { to: "/settings", label: "设置", icon: Settings, note: "Settings" }
];

export function AppShell() {
  const { session, syncState } = useAppState();

  return (
    <div className="grid h-full grid-rows-[40px_1fr] overflow-hidden">
      <header className="border-border/80 flex items-center gap-3 border-b bg-white/55 px-4 backdrop-blur-sm dark:bg-white/5">
        <div className="flex items-center gap-2 text-sm font-extrabold tracking-[0.02em]">
          <div className="text-primary-foreground grid size-5 place-items-center rounded-md bg-linear-to-br from-[var(--mint-300)] to-[var(--mint-500)] text-[11px]">
            <Sparkles className="size-3.5" />
          </div>
          <span>melonbang</span>
        </div>
        <span className="text-muted-foreground text-xs font-semibold">
          Goal 1 · Bangumi UI Foundation
        </span>
        <div className="ml-auto flex items-center gap-3">
          <SyncPill stale={Boolean(syncState?.stale)} />
          <button
            type="button"
            className="border-border bg-card text-muted-foreground hover:text-foreground relative grid size-10 place-items-center rounded-2xl border shadow-[var(--shadow-sm)] transition"
          >
            <Bell className="size-4.5" />
            <span className="bg-accent text-accent-foreground absolute -top-1 -right-1 grid min-h-4 min-w-4 place-items-center rounded-full px-1 text-[10px] font-extrabold">
              5
            </span>
          </button>
        </div>
      </header>
      <div className="grid min-h-0 grid-cols-[236px_1fr]">
        <aside className="border-border flex min-h-0 flex-col gap-3 border-r bg-white/70 px-4 py-4 backdrop-blur-sm dark:bg-white/4">
          <div className="flex items-center gap-3 px-2 pb-2">
            <div className="text-primary-foreground grid size-11 place-items-center rounded-2xl bg-linear-to-br from-[var(--mint-300)] to-[var(--mint-500)] shadow-[0_6px_14px_rgba(34,179,136,.35)]">
              <Sparkles className="size-5" />
            </div>
            <div>
              <div className="text-base font-extrabold tracking-[0.03em]">melonbang</div>
              <div className="text-muted-foreground text-[10px] font-bold tracking-[0.28em] uppercase">
                Melon Soda
              </div>
            </div>
          </div>

          <div className="text-muted-foreground px-2 text-[10px] font-bold tracking-[0.2em] uppercase">
            Navigation
          </div>
          <nav className="flex flex-col gap-1">
            {navItems.map(({ to, label, icon: Icon, note }) => (
              <NavLink
                key={to}
                to={to}
                className={({ isActive }) =>
                  cn(
                    "text-muted-foreground flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-bold transition",
                    isActive
                      ? "text-primary-foreground bg-linear-to-br from-[var(--mint-400)] to-[var(--mint-300)] shadow-[0_8px_18px_rgba(34,179,136,.30)]"
                      : "hover:bg-secondary hover:text-foreground"
                  )
                }
              >
                <Icon className="size-4.5" />
                <span>{label}</span>
                <span className="ml-auto text-[11px] font-extrabold opacity-70">{note}</span>
              </NavLink>
            ))}
          </nav>

          <div className="border-border bg-card mt-auto rounded-2xl border p-3 shadow-[var(--shadow-sm)]">
            <div className="flex items-center gap-3">
              <Avatar className="size-10">
                <AvatarImage alt={session?.nickname ?? "User avatar"} src={session?.avatarUrl} />
                <AvatarFallback>{session?.nickname?.slice(0, 1) ?? "M"}</AvatarFallback>
              </Avatar>
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-extrabold">{session?.nickname}</div>
                <div className="text-muted-foreground truncate text-xs font-semibold">
                  @{session?.username}
                </div>
              </div>
              <span className="size-2.5 rounded-full bg-[var(--mint-400)] shadow-[0_0_0_4px_var(--mint-100)]" />
            </div>
          </div>
        </aside>

        <main className="min-h-0 overflow-auto px-7 pb-10">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

function SyncPill({ stale }: { stale: boolean }) {
  return (
    <div
      className={cn(
        "inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-xs font-extrabold",
        stale
          ? "border-[var(--gold-400)] bg-[#fff5e6] text-[#b5742a]"
          : "border-[var(--mint-200)] bg-[var(--mint-50)] text-[var(--mint-600)]"
      )}
    >
      <span
        className={cn(
          "size-2 rounded-full",
          stale ? "bg-[var(--gold-500)]" : "animate-pulse bg-[var(--mint-400)]"
        )}
      />
      {stale ? "缓存离线" : "已同步"}
    </div>
  );
}
