import { useState } from "react";
import { useLocation } from "react-router-dom";
import { AlertCircle, Check, ExternalLink } from "lucide-react";
import { useAppState } from "../../app/AppStateProvider";
import { WindowFrame } from "../../app/shell/WindowFrame";
import { Button } from "@/components/ui/button";
import { GRADIENTS } from "@/data/artwork";

function MelonMark() {
  return (
    <svg
      className="size-10"
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

const NOTES = [
  "采用 Bangumi 官方 OAuth 授权，会在系统浏览器中打开授权页面。",
  "melonbang 不会接触你的密码，仅获取你授权的收藏与进度权限。",
  "登录凭证经加密后仅保存在本地，可随时在设置中断开。"
];

export function SignInRoute() {
  const { cancelSignIn, signIn, syncState } = useAppState();
  const location = useLocation();
  const [authorizing, setAuthorizing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const locationState = location.state as { reason?: string } | null;
  const notice =
    locationState?.reason === "signed-out" ? "账户已解绑，请重新连接 Bangumi 后继续使用。" : null;
  const authError = error ?? syncState?.lastSyncError;

  async function connect(): Promise<void> {
    setAuthorizing(true);
    setError(null);
    try {
      await signIn();
    } catch (connectError) {
      const message = errorMessage(connectError);
      if (message !== "Bangumi OAuth sign-in was cancelled.") {
        setError(message);
      }
      setAuthorizing(false);
    }
  }

  async function cancelAuthorization(): Promise<void> {
    setError(null);
    setAuthorizing(false);
    await cancelSignIn();
  }

  return (
    <WindowFrame crumb="连接账户">
      <div className="relative grid h-full place-items-center overflow-hidden">
        {/* ghosted poster wall */}
        <div className="pointer-events-none absolute inset-0 grid [transform:rotate(-8deg)_scale(1.25)] grid-cols-8 gap-4 p-[30px] opacity-50 blur-[2px]">
          {Array.from({ length: 24 }, (_, i) => {
            const [a, b] = GRADIENTS[i % GRADIENTS.length];
            return (
              <div
                key={i}
                className="aspect-3/4 rounded-[14px]"
                style={{ background: `linear-gradient(135deg, ${a}, ${b})` }}
              />
            );
          })}
        </div>
        <span className="bg-mint-300 pointer-events-none absolute top-[8%] left-[6%] size-[340px] rounded-full opacity-50 blur-[30px]" />
        <span className="bg-cherry-300 pointer-events-none absolute right-[4%] bottom-[6%] size-[300px] rounded-full opacity-50 blur-[30px]" />
        <span className="pointer-events-none absolute top-[2%] right-[24%] size-[260px] rounded-full bg-sky-300 opacity-50 blur-[30px]" />

        {authorizing ? (
          <div className="border-line relative z-[2] w-[min(440px,92vw)] rounded-[28px] border bg-white/60 px-9 py-[38px] text-center shadow-[var(--shadow-lg)] backdrop-blur-[10px] dark:bg-[rgba(22,32,45,.6)]">
            <div className="border-mint-100 border-t-mint-400 mx-auto mb-3.5 size-[42px] animate-spin rounded-full border-[3px]" />
            <div className="text-xl font-extrabold">正在等待浏览器授权…</div>
            <div className="text-ink-soft my-3.5 text-sm leading-relaxed">
              已在浏览器中打开 Bangumi 授权页面，
              <br />
              请在浏览器内完成登录并点击「授权」后返回本应用。
            </div>
            <Button
              variant="outline"
              className="w-full"
              onClick={() => window.open("https://bgm.tv", "_blank")}
            >
              重新打开授权页面
            </Button>
            <div
              className="text-ink-faint hover:text-ink-soft mt-4 cursor-pointer text-[12.5px] font-semibold"
              onClick={() => void cancelAuthorization()}
            >
              取消登录
            </div>
          </div>
        ) : (
          <div className="border-line relative z-[2] w-[min(440px,92vw)] rounded-[28px] border bg-white/60 px-9 py-[38px] text-center shadow-[var(--shadow-lg)] backdrop-blur-[10px] dark:bg-[rgba(22,32,45,.6)]">
            <div className="text-on-accent mx-auto mb-3.5 grid size-[74px] place-items-center rounded-[22px] bg-[linear-gradient(135deg,var(--mint-300),var(--mint-500))] shadow-[0_12px_28px_rgba(34,179,136,.4),inset_0_0_0_2px_rgba(255,255,255,.45)]">
              <MelonMark />
            </div>
            <div className="text-[26px] font-extrabold tracking-[0.01em]">melonbang</div>
            <div className="text-ink-faint mt-0.5 text-[13px] font-semibold">你的桌面追番伙伴</div>
            <div className="text-ink-soft my-5 text-sm leading-relaxed">
              连接你的 <b>Bangumi</b> 账户，
              <br />
              开始管理你的追番收藏与放送进度。
            </div>

            <Button size="lg" className="w-full" onClick={() => void connect()}>
              <svg
                viewBox="0 0 24 24"
                width="18"
                height="18"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.8"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M4 5h16v11H8l-4 3z" />
                <path d="M8 10h8M8 13h5" />
              </svg>
              使用 Bangumi 账户登录
            </Button>

            <div className="border-line bg-surface-2 mt-[18px] rounded-[14px] border p-4 text-left">
              {NOTES.map((note, i) => (
                <div
                  key={i}
                  className={
                    "text-ink-soft flex items-start gap-2.5 text-[12.5px] leading-relaxed " +
                    (i > 0 ? "mt-2" : "")
                  }
                >
                  <Check className="text-mint-500 mt-0.5 size-4 flex-none" />
                  <span>{note}</span>
                </div>
              ))}
            </div>

            {notice ? (
              <div className="border-mint-200 bg-mint-50 text-mint-600 dark:border-mint-400/20 dark:bg-mint-400/10 mt-4 flex items-start gap-2.5 rounded-[14px] border p-3 text-left text-[12.5px] leading-relaxed font-semibold">
                <Check className="mt-0.5 size-4 flex-none" />
                <span>{notice}</span>
              </div>
            ) : null}

            {authError ? (
              <div className="border-cherry-500/30 text-cherry-600 dark:border-cherry-500/25 dark:bg-cherry-500/10 mt-4 flex items-start gap-2.5 rounded-[14px] border bg-[#ffe6ea] p-3 text-left text-[12.5px] leading-relaxed font-semibold">
                <AlertCircle className="mt-0.5 size-4 flex-none" />
                <span>{authError}</span>
              </div>
            ) : null}

            <a
              className="text-ink-faint mt-4 flex items-center justify-center gap-1.5 text-[12.5px] font-semibold"
              href="https://bgm.tv"
              target="_blank"
              rel="noreferrer"
            >
              <ExternalLink className="size-4" />
              什么是 Bangumi？
            </a>
            <div className="text-ink-faint mt-4 text-[12.5px] font-semibold">
              登录成功后会自动进入首页。
            </div>
          </div>
        )}
      </div>
    </WindowFrame>
  );
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "Bangumi 授权失败，请稍后重试。";
}
