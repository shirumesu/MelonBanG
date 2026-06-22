import { useNavigate } from "react-router-dom";
import { ChevronLeft, Play } from "lucide-react";
import { WindowFrame } from "@/app/shell/WindowFrame";

export function PlayerRoute() {
  const navigate = useNavigate();

  return (
    <WindowFrame crumb="播放">
      <div className="grid h-full place-items-center bg-[var(--player-bg)] px-6">
        <div className="max-w-[420px] text-center text-white">
          <div className="mx-auto grid size-[76px] place-items-center rounded-full border border-white/[0.22] bg-white/[0.12] shadow-[0_18px_42px_rgba(0,0,0,.28)]">
            <Play className="size-8 fill-current text-mint-300" />
          </div>
          <h1 className="mt-5 text-2xl font-extrabold">暂无播放会话</h1>
          <p className="mt-2 text-sm leading-7 text-white/70">
            播放链路尚未接入真实媒体源，因此这里不展示番剧、弹幕或选集数据。
          </p>
          <button
            type="button"
            onClick={() => void navigate(-1)}
            className="mt-6 inline-flex h-10 items-center gap-2 rounded-full border border-white/30 bg-white/[0.14] px-5 text-sm font-extrabold text-white transition hover:bg-white/[0.22]"
          >
            <ChevronLeft className="size-4" />
            返回
          </button>
        </div>
      </div>
    </WindowFrame>
  );
}
