import { useState } from "react";
import { Download, LoaderCircle } from "lucide-react";
import type {
  DanmakuSourceId,
  DanmakuSourceView,
  PlaybackSessionView
} from "@shared/contracts/playback";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";

type DirectProviderId = Exclude<DanmakuSourceId, "dandanplay">;

type DirectDanmakuSourceDialogProps = {
  open: boolean;
  providerId: DirectProviderId;
  source: DanmakuSourceView | null;
  sessionId: string | null;
  onOpenChange: (open: boolean) => void;
  onSession: (session: PlaybackSessionView) => void;
};

const providerCopy: Record<
  DirectProviderId,
  { title: string; inputLabel: string; placeholder: string; hint: string }
> = {
  bilibili: {
    title: "选择 Bilibili 弹幕",
    inputLabel: "BV / EP",
    placeholder: "例如：BV18j411i7iu、ep779775 或播放链接",
    hint: "BV 多分P时可在链接后保留 ?p=2；EP 会精确加载对应番剧剧集。"
  },
  bahamut: {
    title: "选择巴哈姆特动画疯弹幕",
    inputLabel: "动画疯 sn",
    placeholder: "例如：35241 或 animeVideo.php?sn=35241",
    hint: "自动匹配可能受地区或站点限制，手动 sn 会直接加载对应集弹幕。"
  }
};

export function DirectDanmakuSourceDialog({
  open,
  providerId,
  source,
  sessionId,
  onOpenChange,
  onSession
}: DirectDanmakuSourceDialogProps) {
  const copy = providerCopy[providerId];
  const [locator, setLocator] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function handleOpenChange(nextOpen: boolean): void {
    if (!nextOpen) {
      setError(null);
      setLoading(false);
    }
    onOpenChange(nextOpen);
  }

  async function loadSource(): Promise<void> {
    const bridge = window.melonbang?.playback;
    const value = locator.trim();
    if (!bridge || !sessionId) {
      setError("当前播放会话不可用，请重新从缓存页进入播放。");
      return;
    }
    if (!value) {
      setError(`请输入${copy.inputLabel}。`);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const nextSession = await bridge.loadDanmakuSource({
        sessionId,
        providerId,
        locator: value
      });
      onSession(nextSession);
      handleOpenChange(false);
    } catch (reason) {
      setError(toMessage(reason, `无法加载${source?.label ?? "所选来源"}弹幕。`));
    } finally {
      setLoading(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent>
        <DialogHeader className="items-start">
          <div className="flex min-w-0 flex-col gap-1">
            <DialogTitle>{copy.title}</DialogTitle>
            <DialogDescription>
              当前来源已加载 {source?.count ?? 0} 条。自动匹配失败时可在这里精确指定。
            </DialogDescription>
          </div>
        </DialogHeader>
        <DialogBody className="flex flex-col gap-4">
          <form
            className="flex flex-col gap-3"
            onSubmit={(event) => {
              event.preventDefault();
              void loadSource();
            }}
          >
            <label className="flex flex-col gap-1.5">
              <span className="text-[12px] font-bold">{copy.inputLabel}</span>
              <Input
                value={locator}
                onChange={(event) => setLocator(event.target.value)}
                placeholder={copy.placeholder}
                autoFocus
              />
            </label>
            <p className="text-ink-faint text-[11px] leading-5 font-medium">{copy.hint}</p>
            <Button type="submit" disabled={loading || !sessionId}>
              {loading ? (
                <LoaderCircle data-icon="inline-start" className="animate-spin" />
              ) : (
                <Download data-icon="inline-start" />
              )}
              {loading ? "加载中…" : "加载弹幕"}
            </Button>
          </form>

          {source?.matchLabel ? (
            <p className="text-ink-faint text-[12px] leading-5">当前匹配：{source.matchLabel}</p>
          ) : null}
          {source?.errorMessage && !error ? (
            <p className="text-ink-faint text-[12px] leading-5">自动匹配：{source.errorMessage}</p>
          ) : null}
          {error ? (
            <p className="text-destructive text-[12px] leading-5 font-semibold" role="alert">
              {error}
            </p>
          ) : null}
        </DialogBody>
      </DialogContent>
    </Dialog>
  );
}

function toMessage(reason: unknown, fallback: string): string {
  return reason instanceof Error && reason.message ? reason.message : fallback;
}
