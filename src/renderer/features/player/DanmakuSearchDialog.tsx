import { useState } from "react";
import { Search } from "lucide-react";
import type { DanmakuEpisodeSearchResult, PlaybackSessionView } from "@shared/contracts/playback";
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

type DanmakuSearchDialogProps = {
  open: boolean;
  sessionId: string | null;
  currentCount: number;
  providerError: string | null;
  onOpenChange: (open: boolean) => void;
  onSession: (session: PlaybackSessionView) => void;
};

export function DanmakuSearchDialog({
  open,
  sessionId,
  currentCount,
  providerError,
  onOpenChange,
  onSession
}: DanmakuSearchDialogProps) {
  const [anime, setAnime] = useState("");
  const [results, setResults] = useState<DanmakuEpisodeSearchResult[]>([]);
  const [searched, setSearched] = useState(false);
  const [searching, setSearching] = useState(false);
  const [selectingEpisodeId, setSelectingEpisodeId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function searchEpisodes(): Promise<void> {
    const bridge = window.melonbang?.playback;
    const keyword = anime.trim();
    if (!bridge || !sessionId) {
      setError("当前播放会话不可用，请重新从缓存页进入播放。");
      return;
    }
    if (!keyword) {
      setError("请输入番剧名称。");
      return;
    }
    setSearching(true);
    setError(null);
    try {
      const candidates = await bridge.searchDanmakuEpisodes({
        sessionId,
        anime: keyword
      });
      setResults(candidates);
      setSearched(true);
    } catch (reason) {
      setResults([]);
      setSearched(true);
      setError(toMessage(reason, "弹弹play剧集搜索失败。"));
    } finally {
      setSearching(false);
    }
  }

  async function selectEpisode(candidate: DanmakuEpisodeSearchResult): Promise<void> {
    const bridge = window.melonbang?.playback;
    if (!bridge || !sessionId || selectingEpisodeId !== null) return;

    setSelectingEpisodeId(candidate.episodeId);
    setError(null);
    try {
      const nextSession = await bridge.selectDanmakuEpisode({
        sessionId,
        episodeId: candidate.episodeId
      });
      onSession(nextSession);
      onOpenChange(false);
    } catch (reason) {
      setError(toMessage(reason, "无法加载所选剧集的弹幕。"));
    } finally {
      setSelectingEpisodeId(null);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader className="items-start">
          <div className="flex min-w-0 flex-col gap-1">
            <DialogTitle>选择弹弹play弹幕库</DialogTitle>
            <DialogDescription>
              当前已加载 {currentCount} 条。搜索番剧后，点选具体剧集即可替换当前弹幕。
            </DialogDescription>
          </div>
        </DialogHeader>
        <DialogBody className="flex max-h-[70vh] flex-col gap-4 overflow-y-auto">
          <form
            className="flex flex-col gap-3"
            onSubmit={(event) => {
              event.preventDefault();
              void searchEpisodes();
            }}
          >
            <label className="flex flex-col gap-1.5">
              <span className="text-[12px] font-bold">番剧名称</span>
              <Input
                value={anime}
                onChange={(event) => setAnime(event.target.value)}
                placeholder="例如：元祖！BanG Dream Chan"
                autoFocus
              />
            </label>
            <Button type="submit" disabled={searching || !sessionId}>
              <Search data-icon="inline-start" />
              {searching ? "搜索中…" : "搜索弹幕库"}
            </Button>
          </form>

          {providerError && !error ? (
            <p className="text-ink-faint text-[12px] leading-5">自动匹配：{providerError}</p>
          ) : null}
          {error ? (
            <p className="text-destructive text-[12px] leading-5 font-semibold" role="alert">
              {error}
            </p>
          ) : null}

          <div className="flex flex-col gap-2" aria-live="polite">
            {results.map((candidate) => (
              <button
                key={candidate.episodeId}
                type="button"
                disabled={selectingEpisodeId !== null}
                onClick={() => void selectEpisode(candidate)}
                className="border-line bg-card hover:border-mint-300 hover:bg-mint-50 flex w-full items-center gap-3 rounded-2xl border px-4 py-3 text-left transition disabled:opacity-60"
              >
                <span className="min-w-0 flex-1">
                  <b className="block truncate text-[13px]">{candidate.animeTitle}</b>
                  <span className="text-ink-faint block truncate text-[11px] font-medium">
                    {candidate.episodeTitle}
                    {candidate.typeDescription ? ` · ${candidate.typeDescription}` : ""}
                  </span>
                </span>
                <span className="text-mint-600 shrink-0 text-[11px] font-bold">
                  {selectingEpisodeId === candidate.episodeId ? "加载中…" : "选择"}
                </span>
              </button>
            ))}
            {searched && results.length === 0 && !error ? (
              <p className="text-ink-faint py-4 text-center text-[12px] font-medium">
                没有找到符合条件的剧集，请尝试缩短番剧名称。
              </p>
            ) : null}
          </div>
        </DialogBody>
      </DialogContent>
    </Dialog>
  );
}

function toMessage(reason: unknown, fallback: string): string {
  return reason instanceof Error && reason.message ? reason.message : fallback;
}
