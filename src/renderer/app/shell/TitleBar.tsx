import { useEffect, useState } from "react";
import { useLocation } from "react-router-dom";
import { X } from "lucide-react";

const CRUMBS: { match: (path: string) => boolean; label: string }[] = [
  { match: (p) => p.startsWith("/home"), label: "探索" },
  { match: (p) => p.startsWith("/tracking"), label: "追番" },
  { match: (p) => p.startsWith("/cache"), label: "缓存" },
  { match: (p) => p.startsWith("/subject"), label: "探索 › 番剧详情" },
  { match: (p) => p.startsWith("/schedule"), label: "探索 › 新番时间表" },
  { match: (p) => p.startsWith("/settings"), label: "设置" },
  { match: (p) => p.startsWith("/player"), label: "正在播放" }
];

function useCrumb(): string {
  const { pathname } = useLocation();
  return CRUMBS.find((entry) => entry.match(pathname))?.label ?? "";
}

function WinButton({
  title,
  onClick,
  danger,
  children
}: {
  title: string;
  onClick: () => void;
  danger?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      title={title}
      onClick={onClick}
      className={
        "text-ink-soft grid h-7 w-[38px] place-items-center rounded-lg transition " +
        (danger ? "hover:bg-cherry-500 hover:text-white" : "hover:bg-surface-3")
      }
    >
      {children}
    </button>
  );
}

export function TitleBar({ crumb }: { crumb?: string }) {
  const routeCrumb = useCrumb();
  const label = crumb ?? routeCrumb;
  const [maximized, setMaximized] = useState(false);
  const controls = window.melonbang.windowControls;

  useEffect(() => {
    void controls.isMaximized().then(setMaximized);
    return controls.onMaximizeChange(setMaximized);
  }, [controls]);

  return (
    <div className="drag-region border-line flex h-10 items-center gap-2.5 border-b bg-[linear-gradient(180deg,rgba(255,255,255,.55),rgba(255,255,255,0))] pr-2 pl-3.5 select-none dark:bg-[linear-gradient(180deg,rgba(255,255,255,.05),rgba(255,255,255,0))]">
      <div className="flex items-center gap-2 font-extrabold tracking-[0.02em]">
        <span className="size-[18px] rounded-md bg-[linear-gradient(135deg,var(--mint-300),var(--mint-500))] shadow-[inset_0_0_0_2px_rgba(255,255,255,.4)]" />
        melonbang
      </div>
      {label ? <span className="text-ink-faint text-xs">— {label}</span> : null}
      <div className="flex-1" />
      <div className="no-drag flex gap-0.5">
        <WinButton title="最小化" onClick={() => controls.minimize()}>
          <svg
            viewBox="0 0 24 24"
            width="14"
            height="14"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.6"
          >
            <path d="M5 12h14" />
          </svg>
        </WinButton>
        <WinButton title="最大化" onClick={() => controls.toggleMaximize()}>
          {maximized ? (
            <svg
              viewBox="0 0 24 24"
              width="13"
              height="13"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
            >
              <rect x="7" y="7" width="11" height="11" rx="2" />
              <path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4H18.5A1.5 1.5 0 0 1 20 5.5v8A1.5 1.5 0 0 1 18.5 15H17" />
            </svg>
          ) : (
            <svg
              viewBox="0 0 24 24"
              width="13"
              height="13"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
            >
              <rect x="5" y="5" width="14" height="14" rx="2" />
            </svg>
          )}
        </WinButton>
        <WinButton title="关闭" danger onClick={() => controls.close()}>
          <X className="size-4" />
        </WinButton>
      </div>
    </div>
  );
}
