import { useState } from "react";
import { ChevronLeft, LoaderCircle, Search } from "lucide-react";
import type {
  EpisodeCollectionState,
  SubjectDetail,
  SubjectSearchResult
} from "@shared/contracts/bangumi";
import type { PlaybackSessionView } from "@shared/contracts/playback";
import { Badge } from "@/components/ui/badge";
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
import { cn } from "@/lib/utils";

type EpisodeBindingDialogProps = {
  open: boolean;
  session: PlaybackSessionView | null;
  onOpenChange: (open: boolean) => void;
  onSession: (session: PlaybackSessionView) => void;
};

export function EpisodeBindingDialog({
  open,
  session,
  onOpenChange,
  onSession
}: EpisodeBindingDialogProps) {
  const [keyword, setKeyword] = useState("");
  const [results, setResults] = useState<SubjectSearchResult[]>([]);
  const [subject, setSubject] = useState<SubjectDetail | null>(null);
  const [searching, setSearching] = useState(false);
  const [loadingSubjectId, setLoadingSubjectId] = useState<number | null>(null);
  const [bindingEpisodeId, setBindingEpisodeId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  const canBind = Boolean(session?.downloadId && session.fileId && session.source);

  function handleOpenChange(nextOpen: boolean): void {
    if (!nextOpen) {
      setKeyword("");
      setResults([]);
      setSubject(null);
      setSearching(false);
      setLoadingSubjectId(null);
      setBindingEpisodeId(null);
      setError(null);
    }
    onOpenChange(nextOpen);
  }

  async function searchSubjects(): Promise<void> {
    const value = keyword.trim();
    if (!value) {
      setError("请输入番剧名称。");
      return;
    }

    setSearching(true);
    setError(null);
    try {
      const nextResults = await window.melonbang.bangumi.searchSubjects(value);
      setResults(nextResults.slice(0, 12));
    } catch (reason) {
      setError(toMessage(reason, "番剧搜索失败。"));
    } finally {
      setSearching(false);
    }
  }

  async function selectSubject(result: SubjectSearchResult): Promise<void> {
    setLoadingSubjectId(result.subjectId);
    setError(null);
    try {
      setSubject(await window.melonbang.bangumi.getSubject(result.subjectId));
    } catch (reason) {
      setError(toMessage(reason, "番剧章节加载失败。"));
    } finally {
      setLoadingSubjectId(null);
    }
  }

  async function bindEpisode(episode: EpisodeCollectionState): Promise<void> {
    if (!session || !canBind) {
      setError("当前媒体不是可关联的本地缓存视频。");
      return;
    }

    setBindingEpisodeId(episode.episodeId);
    setError(null);
    try {
      const nextSession = await window.melonbang.playback.bindSessionEpisode({
        sessionId: session.id,
        subjectId: episode.subjectId,
        episodeId: episode.episodeId
      });
      onSession(nextSession);
      handleOpenChange(false);
    } catch (reason) {
      setError(toMessage(reason, "章节关联失败。"));
    } finally {
      setBindingEpisodeId(null);
    }
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="w-[min(640px,94vw)]">
        <DialogHeader>
          <div className="min-w-0">
            <DialogTitle>关联真实章节</DialogTitle>
            <DialogDescription className="mt-1">
              搜索 Bangumi 番剧并选择具体章节，当前视频不会重新开始播放。
            </DialogDescription>
          </div>
        </DialogHeader>
        <DialogBody className="max-h-[72vh] overflow-auto">
          {!canBind ? (
            <div className="border-line bg-surface-2 text-ink-faint rounded-[16px] border px-4 py-8 text-center text-sm font-semibold">
              当前播放会话没有可关联的本地缓存文件。
            </div>
          ) : subject ? (
            <div className="flex flex-col gap-3">
              <div className="flex items-center gap-2">
                <Button variant="ghost" size="sm" onClick={() => setSubject(null)}>
                  <ChevronLeft data-icon="inline-start" />
                  返回搜索
                </Button>
                <Badge variant="mint">{subject.nameCn ?? subject.name}</Badge>
              </div>
              <div className="grid grid-cols-[repeat(auto-fill,minmax(150px,1fr))] gap-2">
                {subject.episodes.map((episode) => (
                  <Button
                    key={episode.episodeId}
                    type="button"
                    variant="outline"
                    disabled={bindingEpisodeId !== null}
                    onClick={() => void bindEpisode(episode)}
                    className="h-auto min-h-[58px] items-start justify-start rounded-xl px-3 py-2.5 text-left whitespace-normal"
                  >
                    <span className="min-w-0">
                      <b className="block truncate text-[12.5px]">EP{episode.sort}</b>
                      <span className="text-ink-faint line-clamp-2 text-[11px] font-semibold">
                        {episode.nameCn ?? episode.name}
                      </span>
                    </span>
                    {bindingEpisodeId === episode.episodeId ? (
                      <LoaderCircle data-icon="inline-end" className="animate-spin" />
                    ) : null}
                  </Button>
                ))}
              </div>
            </div>
          ) : (
            <div className="flex flex-col gap-3">
              <form
                className="flex gap-2"
                onSubmit={(event) => {
                  event.preventDefault();
                  void searchSubjects();
                }}
              >
                <label className="min-w-0 flex-1">
                  <span className="sr-only">番剧名称</span>
                  <Input
                    value={keyword}
                    onChange={(event) => setKeyword(event.target.value)}
                    placeholder="输入番剧名称"
                    aria-invalid={Boolean(error)}
                  />
                </label>
                <Button type="submit" disabled={searching}>
                  {searching ? (
                    <LoaderCircle data-icon="inline-start" className="animate-spin" />
                  ) : (
                    <Search data-icon="inline-start" />
                  )}
                  {searching ? "搜索中" : "搜索"}
                </Button>
              </form>

              {results.length > 0 ? (
                <div className="flex flex-col gap-2">
                  {results.map((result) => (
                    <button
                      key={result.subjectId}
                      type="button"
                      disabled={loadingSubjectId !== null}
                      onClick={() => void selectSubject(result)}
                      className={cn(
                        "border-line bg-surface hover:border-mint-300 flex items-center gap-3 rounded-[14px] border p-3 text-left transition",
                        loadingSubjectId !== null && "opacity-70"
                      )}
                    >
                      {result.coverUrl ? (
                        <img
                          src={result.coverUrl}
                          alt=""
                          className="size-12 shrink-0 rounded-[10px] object-cover"
                        />
                      ) : (
                        <span className="bg-mint-100 text-mint-600 grid size-12 shrink-0 place-items-center rounded-[10px] text-sm font-extrabold">
                          番
                        </span>
                      )}
                      <span className="min-w-0 flex-1">
                        <b className="block truncate text-sm">{result.nameCn ?? result.name}</b>
                        <span className="text-ink-faint block truncate text-[11px] font-semibold">
                          {result.name}
                          {result.episodeTotal ? ` · ${result.episodeTotal} 话` : ""}
                        </span>
                      </span>
                      {loadingSubjectId === result.subjectId ? (
                        <LoaderCircle className="text-mint-500 size-4 animate-spin" />
                      ) : null}
                    </button>
                  ))}
                </div>
              ) : keyword.trim() && !searching && !error ? (
                <div className="border-line bg-surface-2 text-ink-faint rounded-[14px] border px-4 py-7 text-center text-sm font-semibold">
                  没有找到匹配番剧，请尝试其它名称。
                </div>
              ) : null}
            </div>
          )}

          {error ? <p className="text-cherry-500 mt-3 text-[12px] font-bold">{error}</p> : null}
        </DialogBody>
      </DialogContent>
    </Dialog>
  );
}

function toMessage(reason: unknown, fallback: string): string {
  return reason instanceof Error && reason.message ? reason.message : fallback;
}
