import { ArrowRight, ShieldCheck, Sparkles } from "lucide-react";
import { useState } from "react";
import { useAppState } from "../../app/AppStateProvider";

export function SignInRoute() {
  const { signIn } = useAppState();
  const [pending, setPending] = useState(false);

  async function handleSignIn(): Promise<void> {
    setPending(true);
    try {
      await signIn();
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="bg-background grid h-full grid-cols-[1.15fr_0.85fr]">
      <section className="relative overflow-hidden p-10">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,_rgba(67,201,159,0.18),_transparent_45%),radial-gradient(circle_at_right,_rgba(255,107,129,0.18),_transparent_42%)]" />
        <div className="relative flex h-full flex-col justify-between rounded-[28px] border border-white/50 bg-linear-to-br from-[#0f7d5e] via-[#1aa183] to-[#3f7fd8] p-10 text-white shadow-[var(--shadow-lg)]">
          <div className="flex items-center gap-3 text-sm font-extrabold tracking-[0.24em] text-white/85 uppercase">
            <Sparkles className="size-5" />
            melonbang
          </div>
          <div className="max-w-xl">
            <div className="mb-4 inline-flex items-center gap-2 rounded-full border border-white/35 bg-white/15 px-4 py-2 text-xs font-bold">
              <ShieldCheck className="size-4" />
              Goal 1 · Secure Bangumi Desktop Shell
            </div>
            <h1 className="text-5xl font-black tracking-[0.01em]">
              把 Bangumi 追番、条目细节和进度更新，收回到桌面里。
            </h1>
            <p className="mt-5 max-w-lg text-sm leading-7 text-white/92">
              当前阶段先完成认证、收藏浏览、条目详情、章节状态和同步诊断。下载、播放、弹幕和缓存管理留到后续
              Goal。
            </p>
          </div>
          <div className="grid max-w-xl grid-cols-3 gap-4 text-sm">
            <InfoTile title="OAuth 2.0" detail="外部浏览器授权 + 本地 loopback 回调" />
            <InfoTile title="SQLite Cache" detail="本地缓存、队列和后续播放状态的基础" />
            <InfoTile title="Renderer Safe" detail="只有 preload bridge，没有直连 Node 或网络" />
          </div>
        </div>
      </section>

      <section className="flex items-center justify-center p-10">
        <div className="border-border bg-card w-full max-w-md rounded-[28px] border p-8 shadow-[var(--shadow-lg)]">
          <div className="mb-6">
            <div className="text-muted-foreground text-sm font-bold tracking-[0.26em] uppercase">
              Sign In
            </div>
            <h2 className="mt-3 text-3xl font-black">连接 Bangumi 账号</h2>
            <p className="text-muted-foreground mt-3 text-sm leading-7">
              授权只在主进程中完成。访问令牌不会进入 renderer，也不会以明文写入磁盘。
            </p>
          </div>

          <button
            type="button"
            onClick={() => void handleSignIn()}
            disabled={pending}
            className="inline-flex w-full items-center justify-center gap-2 rounded-full bg-linear-to-br from-[var(--mint-400)] to-[var(--mint-500)] px-5 py-3.5 text-sm font-extrabold text-white shadow-[0_8px_18px_rgba(34,179,136,.32)] transition hover:brightness-105 disabled:cursor-not-allowed disabled:opacity-60"
          >
            <span>{pending ? "连接中…" : "使用 Bangumi 登录"}</span>
            <ArrowRight className="size-4" />
          </button>

          <div className="bg-secondary text-muted-foreground mt-6 rounded-2xl p-4 text-sm">
            本地凭据未配置时，当前工程先使用 mock service 提供 UI 联调。后续接入真实 OAuth
            与仓储层时，这一页不需要重做。
          </div>
        </div>
      </section>
    </div>
  );
}

function InfoTile({ title, detail }: { title: string; detail: string }) {
  return (
    <div className="rounded-2xl border border-white/15 bg-white/10 p-4 backdrop-blur-sm">
      <div className="text-lg font-black">{title}</div>
      <div className="mt-2 text-xs leading-6 text-white/75">{detail}</div>
    </div>
  );
}
