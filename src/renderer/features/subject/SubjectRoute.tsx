import { useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { ChevronLeft, Play } from "lucide-react";
import type {
  CollectionStatus,
  EpisodeCollectionState,
  SubjectDetail,
  SubjectStaffCredit
} from "@shared/contracts/bangumi";
import type { DownloadFileView, DownloadSnapshot, DownloadTaskView } from "@shared/contracts/download";
import type { MediaBindingView } from "@shared/contracts/playback";
import { useAppState } from "@/app/AppStateProvider";
import { SubjectHero } from "./components/SubjectHero";
import { SubjectTabs } from "./components/SubjectTabs";
import { IconButton, PageContent, Topbar } from "@/components/melon/layout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogHeader,
  DialogTitle
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

function Divider() {
  return <div className="bg-line my-[18px] h-px" />;
}

function SectionTitle({
  size,
  children,
  action
}: {
  size: 16 | 18;
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="mb-3 flex items-center gap-3">
      <div className="font-extrabold" style={{ fontSize: size }}>
        {children}
      </div>
      {action ? <div className="ml-auto">{action}</div> : null}
    </div>
  );
}

type DetailDialog = "synopsis" | "characters" | "staff" | null;
const emptyDownloadSnapshot: DownloadSnapshot = { tasks: [], files: [] };

type CharacterCardModel = {
  id: number;
  name: string;
  role: string;
  actorName?: string;
  imageUrl?: string;
  initial: string;
};

type StaffCardModel = {
  key: string;
  name: string;
  role: string;
  imageUrl?: string;
  initial: string;
};

export function SubjectRoute() {
  const navigate = useNavigate();
  const { subjectId } = useParams();
  const { getCachedSubject, getSubject, updateTracking } = useAppState();
  const [subject, setSubject] = useState<SubjectDetail | null>(null);
  const [loadingError, setLoadingError] = useState<{ subjectId: number; message: string } | null>(
    null
  );
  const [refreshingSubjectId, setRefreshingSubjectId] = useState<number | null>(null);
  const [epOpen, setEpOpen] = useState(false);
  const [pvOpen, setPvOpen] = useState(false);
  const [detailDialog, setDetailDialog] = useState<DetailDialog>(null);
  const [selectedMediaEpisodeId, setSelectedMediaEpisodeId] = useState<number | null>(null);
  const [downloadSnapshot, setDownloadSnapshot] = useState<DownloadSnapshot>(emptyDownloadSnapshot);
  const [mediaBinding, setMediaBinding] = useState<MediaBindingView | null>(null);
  const [selectedMediaKey, setSelectedMediaKey] = useState("");
  const [mediaActionError, setMediaActionError] = useState<string | null>(null);

  useEffect(() => {
    if (!subjectId) {
      return;
    }

    let ignore = false;
    const nextSubjectId = Number(subjectId);

    void (async () => {
      const cachedSubject = await getCachedSubject(nextSubjectId).catch(() => null);
      if (!ignore && cachedSubject) {
        setSubject(cachedSubject);
        setRefreshingSubjectId(nextSubjectId);
      }

      try {
        const nextSubject = await getSubject(nextSubjectId);
        if (!ignore) {
          setLoadingError(null);
          setSubject(nextSubject);
          setRefreshingSubjectId(null);
        }
      } catch (error) {
        if (!ignore) {
          setRefreshingSubjectId(null);
          if (!cachedSubject) {
            setLoadingError({
              subjectId: nextSubjectId,
              message: error instanceof Error ? error.message : "条目加载失败"
            });
          }
        }
      }
    })();

    return () => {
      ignore = true;
    };
  }, [getCachedSubject, getSubject, subjectId]);

  const currentSubjectId = subjectId ? Number(subjectId) : null;
  const activeSubject = subject?.subjectId === currentSubjectId ? subject : null;
  const activeLoadingError =
    loadingError?.subjectId === currentSubjectId ? loadingError.message : null;

  const synopsis = useMemo(() => splitSynopsis(activeSubject?.summary), [activeSubject?.summary]);
  const synopsisHasMore = synopsis.length > 2 || synopsis.join("").length > 260;
  const visibleSynopsis = useMemo(
    () => (synopsisHasMore ? previewSynopsis(synopsis, 260) : synopsis),
    [synopsis, synopsisHasMore]
  );
  const characters = useMemo(() => buildCharacters(activeSubject), [activeSubject]);
  const visibleCharacters = useMemo(() => {
    const mainCharacters = characters.filter((character) => isMainCharacterRole(character.role));
    return (mainCharacters.length > 0 ? mainCharacters : characters).slice(0, 6);
  }, [characters]);
  const staff = useMemo(() => buildStaff(activeSubject), [activeSubject]);
  const visibleStaff = staff.slice(0, 6);
  const nextEpisode = useMemo(
    () =>
      activeSubject?.episodes.find(
        (episode) => episode.status === "queue" || episode.status === "unwatched"
      ),
    [activeSubject?.episodes]
  );
  const selectedMediaEpisode = useMemo(
    () =>
      activeSubject?.episodes.find((episode) => episode.episodeId === selectedMediaEpisodeId) ??
      nextEpisode ??
      activeSubject?.episodes[0] ??
      null,
    [activeSubject?.episodes, nextEpisode, selectedMediaEpisodeId]
  );
  const mediaOptions = useMemo(
    () => buildMediaOptions(downloadSnapshot.tasks, downloadSnapshot.files),
    [downloadSnapshot.files, downloadSnapshot.tasks]
  );

  useEffect(() => {
    if (!epOpen) {
      return;
    }

    let ignore = false;
    const bridge = window.melonbang?.download;
    if (!bridge) {
      return;
    }

    void bridge
      .list()
      .then((snapshot) => {
        if (!ignore) {
          setDownloadSnapshot(snapshot);
        }
      })
      .catch(() => undefined);

    return () => {
      ignore = true;
    };
  }, [epOpen]);

  useEffect(() => {
    if (!selectedMediaEpisode) {
      return;
    }

    let ignore = false;
    const bridge = window.melonbang?.playback;
    if (!bridge) {
      return;
    }

    void bridge
      .getEpisodeMediaBinding({
        subjectId: selectedMediaEpisode.subjectId,
        episodeId: selectedMediaEpisode.episodeId
      })
      .then((binding) => {
        if (!ignore) {
          setMediaBinding(binding);
          setSelectedMediaKey(binding ? `${binding.downloadId}|${binding.fileId}` : "");
        }
      })
      .catch(() => {
        if (!ignore) {
          setMediaBinding(null);
        }
      });

    return () => {
      ignore = true;
    };
  }, [selectedMediaEpisode]);

  async function applyCachedSubject(subjectId: number): Promise<void> {
    const cachedSubject = await getCachedSubject(subjectId).catch(() => null);
    if (!cachedSubject) {
      return;
    }

    setSubject((current) => (current?.subjectId === subjectId ? cachedSubject : current));
  }

  async function refreshSubjectFromRemote(subjectId: number): Promise<void> {
    setRefreshingSubjectId(subjectId);
    try {
      const nextSubject = await getSubject(subjectId);
      setLoadingError(null);
      setSubject((current) => (current?.subjectId === subjectId ? nextSubject : current));
    } catch {
      // Keep the locally accepted tracking state visible when the remote refresh is unavailable.
    } finally {
      setRefreshingSubjectId((current) => (current === subjectId ? null : current));
    }
  }

  async function changeStatus(status: CollectionStatus): Promise<void> {
    if (!activeSubject) {
      return;
    }

    const subjectId = activeSubject.subjectId;
    await updateTracking({
      kind: "subjectCollection",
      subjectId,
      status
    });
    await applyCachedSubject(subjectId);
    void refreshSubjectFromRemote(subjectId);
  }

  async function toggleEpisode(episode: EpisodeCollectionState): Promise<void> {
    const subjectId = episode.subjectId;
    await updateTracking({
      kind: "episodeCollection",
      episodeId: episode.episodeId,
      status: episode.status === "watched" ? "queue" : "watched"
    });
    await applyCachedSubject(subjectId);
    void refreshSubjectFromRemote(subjectId);
  }

  async function continuePlayback(): Promise<void> {
    const episode = nextEpisode ?? activeSubject?.episodes[0] ?? null;
    if (!episode) {
      setEpOpen(true);
      return;
    }

    const bridge = window.melonbang?.playback;
    if (!bridge) {
      setMediaActionError("播放桥接不可用，请重启应用。");
      setEpOpen(true);
      return;
    }

    try {
      await bridge.startEpisode({
        subjectId: episode.subjectId,
        episodeId: episode.episodeId
      });
      void navigate("/player");
    } catch {
      setSelectedMediaEpisodeId(episode.episodeId);
      setEpOpen(true);
    }
  }

  async function bindSelectedEpisodeMedia(): Promise<void> {
    if (!selectedMediaEpisode || !selectedMediaKey) {
      return;
    }

    const [downloadId, fileId] = selectedMediaKey.split("|");
    const bridge = window.melonbang?.playback;
    if (!bridge) {
      setMediaActionError("播放桥接不可用，请重启应用。");
      return;
    }

    setMediaActionError(null);
    try {
      const binding = await bridge.bindEpisodeMedia({
        subjectId: selectedMediaEpisode.subjectId,
        episodeId: selectedMediaEpisode.episodeId,
        downloadId,
        fileId
      });
      setMediaBinding(binding);
    } catch (error) {
      setMediaActionError(toMessage(error, "媒体绑定失败。"));
    }
  }

  async function playSelectedEpisode(): Promise<void> {
    if (!selectedMediaEpisode) {
      return;
    }

    const bridge = window.melonbang?.playback;
    if (!bridge) {
      setMediaActionError("播放桥接不可用，请重启应用。");
      return;
    }

    setMediaActionError(null);
    try {
      await bridge.startEpisode({
        subjectId: selectedMediaEpisode.subjectId,
        episodeId: selectedMediaEpisode.episodeId
      });
      void navigate("/player");
    } catch (error) {
      setMediaActionError(toMessage(error, "章节播放失败。"));
    }
  }

  async function clearSelectedEpisodeBinding(): Promise<void> {
    if (!mediaBinding) {
      return;
    }

    const bridge = window.melonbang?.playback;
    if (!bridge) {
      setMediaActionError("播放桥接不可用，请重启应用。");
      return;
    }

    setMediaActionError(null);
    try {
      await bridge.clearEpisodeMediaBinding({ bindingId: mediaBinding.id });
      setMediaBinding(null);
      setSelectedMediaKey("");
    } catch (error) {
      setMediaActionError(toMessage(error, "绑定清除失败。"));
    }
  }

  if (!activeSubject) {
    return (
      <>
        <Topbar
          title="番剧详情"
          titleSize={18}
          leading={
            <IconButton onClick={() => void navigate(-1)}>
              <ChevronLeft />
            </IconButton>
          }
        />
        <PageContent narrow>
          <div className="border-line bg-surface text-ink-faint rounded-[20px] border p-10 text-center text-sm font-bold shadow-[var(--shadow-sm)]">
            {activeLoadingError ?? "加载条目中…"}
          </div>
        </PageContent>
      </>
    );
  }

  const isRefreshingSubject = refreshingSubjectId === activeSubject.subjectId;

  return (
    <>
      <Topbar
        title="番剧详情"
        titleSize={18}
        leading={
          <IconButton onClick={() => void navigate(-1)}>
            <ChevronLeft />
          </IconButton>
        }
      />

      <PageContent narrow>
        <SubjectHero
          subject={activeSubject}
          onOpenEpisodes={() => setEpOpen(true)}
          onOpenCache={() => void navigate(`/subject/${activeSubject.subjectId}/cache`)}
          onOpenPv={() => setPvOpen(true)}
          onContinuePlayback={() => void continuePlayback()}
          onChangeStatus={(status) => void changeStatus(status)}
        />

        <div className="border-line bg-surface mt-5 rounded-[20px] border p-[18px] shadow-[var(--shadow-sm)]">
          <SectionTitle
            size={18}
            action={
              synopsisHasMore ? (
                <Button variant="ghost" size="sm" onClick={() => setDetailDialog("synopsis")}>
                  查看全部
                </Button>
              ) : null
            }
          >
            简介
          </SectionTitle>
          <div className="[&>p]:text-ink-soft [&>p]:mt-3 [&>p]:leading-[1.85] [&>p:first-child]:mt-0">
            {visibleSynopsis.map((paragraph, i) => (
              <p key={i}>{paragraph}</p>
            ))}
          </div>

          <Divider />

          <SectionTitle
            size={16}
            action={
              characters.length > visibleCharacters.length ? (
                <Button variant="ghost" size="sm" onClick={() => setDetailDialog("characters")}>
                  查看全部
                </Button>
              ) : null
            }
          >
            主要角色
          </SectionTitle>
          {visibleCharacters.length > 0 ? (
            <div className="grid grid-cols-[repeat(auto-fill,minmax(120px,1fr))] gap-3">
              {visibleCharacters.map((character, index) => (
                <CreditCard key={character.id} credit={character} index={index} />
              ))}
            </div>
          ) : (
            <div className="border-line bg-surface-2 text-ink-faint rounded-[14px] border p-5 text-sm font-semibold">
              暂未加载角色信息。
            </div>
          )}

          <Divider />

          <SectionTitle
            size={16}
            action={
              staff.length > visibleStaff.length ? (
                <Button variant="ghost" size="sm" onClick={() => setDetailDialog("staff")}>
                  查看全部
                </Button>
              ) : null
            }
          >
            制作团队
          </SectionTitle>
          {visibleStaff.length > 0 ? (
            <div className="grid grid-cols-[repeat(auto-fill,minmax(120px,1fr))] gap-3">
              {visibleStaff.map((member, index) => (
                <CreditCard key={member.key} credit={member} index={index} />
              ))}
            </div>
          ) : (
            <div className="border-line bg-surface-2 text-ink-faint rounded-[14px] border p-4 text-sm font-semibold">
              Bangumi 条目详情暂未提供可展示的制作团队字段。
            </div>
          )}

          <Divider />

          <SubjectTabs
            comments={activeSubject.comments ?? []}
            topics={activeSubject.topics ?? []}
            loading={isRefreshingSubject}
          />
        </div>
      </PageContent>

      <Dialog open={epOpen} onOpenChange={setEpOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>选集 · {activeSubject.nameCn ?? activeSubject.name}</DialogTitle>
          </DialogHeader>
          <DialogBody>
            <div className="mb-3.5 flex items-center gap-2">
              <Badge variant="mint">Bangumi 章节进度</Badge>
              <Badge variant="outline">
                {nextEpisode ? `下一话 EP${nextEpisode.sort}` : "已看完"}
              </Badge>
              <span className="text-ink-faint text-xs">点击章节选择本地媒体或更新进度</span>
            </div>
            <div className="border-line bg-surface-2 mb-3.5 rounded-[14px] border p-3">
              <div className="mb-2 flex flex-wrap items-center gap-2">
                <Badge variant="outline">
                  {selectedMediaEpisode
                    ? `EP${selectedMediaEpisode.sort} · ${
                        selectedMediaEpisode.nameCn ?? selectedMediaEpisode.name
                      }`
                    : "未选择章节"}
                </Badge>
                {mediaBinding ? (
                  <Badge variant={mediaBinding.available ? "mint" : "outline"}>
                    {mediaBinding.available ? "已绑定本地媒体" : "绑定文件不可用"}
                  </Badge>
                ) : null}
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <select
                  value={selectedMediaKey}
                  onChange={(event) => setSelectedMediaKey(event.target.value)}
                  className="border-line bg-surface text-ink min-w-[260px] flex-1 rounded-full border px-3 py-2 text-[12px] font-semibold outline-none"
                >
                  <option value="">选择已完成缓存视频</option>
                  {mediaOptions.map((option) => (
                    <option key={option.key} value={option.key}>
                      {option.label}
                    </option>
                  ))}
                </select>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={!selectedMediaEpisode || !selectedMediaKey}
                  onClick={() => void bindSelectedEpisodeMedia()}
                >
                  绑定
                </Button>
                <Button
                  size="sm"
                  disabled={!selectedMediaEpisode || !mediaBinding?.available}
                  onClick={() => void playSelectedEpisode()}
                >
                  <Play className="size-4 fill-current" />
                  播放
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={!selectedMediaEpisode}
                  onClick={() => selectedMediaEpisode && void toggleEpisode(selectedMediaEpisode)}
                >
                  {selectedMediaEpisode?.status === "watched" ? "标为未看" : "标为看过"}
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={!mediaBinding}
                  onClick={() => void clearSelectedEpisodeBinding()}
                >
                  清除绑定
                </Button>
              </div>
              {mediaActionError ? (
                <div className="text-cherry-500 mt-2 text-[12px] font-bold">{mediaActionError}</div>
              ) : null}
            </div>
            <div className="grid grid-cols-[repeat(auto-fill,minmax(58px,1fr))] gap-[9px]">
              {activeSubject.episodes.map((episode) => (
                <button
                  key={episode.episodeId}
                  type="button"
                  onClick={() => {
                    setSelectedMediaEpisodeId(episode.episodeId);
                    setMediaActionError(null);
                  }}
                  className={cn(
                    "relative grid aspect-square place-items-center rounded-[11px] border text-[15px] font-extrabold transition",
                    episode.episodeId === selectedMediaEpisode?.episodeId &&
                      "text-on-accent border-transparent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_6px_14px_rgba(34,179,136,.3)]",
                    episode.episodeId === nextEpisode?.episodeId &&
                      episode.episodeId !== selectedMediaEpisode?.episodeId &&
                      "text-on-accent border-transparent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_6px_14px_rgba(34,179,136,.3)]",
                    episode.status === "watched" &&
                      episode.episodeId !== selectedMediaEpisode?.episodeId &&
                      episode.episodeId !== nextEpisode?.episodeId &&
                      "border-mint-200 bg-mint-50 text-mint-600",
                    episode.status !== "watched" &&
                      episode.episodeId !== selectedMediaEpisode?.episodeId &&
                      episode.episodeId !== nextEpisode?.episodeId &&
                      "border-line bg-surface text-ink-soft hover:border-mint-300 hover:text-mint-600 hover:-translate-y-0.5"
                  )}
                  title={episode.nameCn ?? episode.name}
                >
                  {episode.sort}
                  {episode.status === "watched" && episode.episodeId !== nextEpisode?.episodeId ? (
                    <span className="text-mint-500 absolute top-[3px] right-[5px] text-[10px]">
                      ✓
                    </span>
                  ) : null}
                </button>
              ))}
            </div>
          </DialogBody>
        </DialogContent>
      </Dialog>

      <Dialog open={pvOpen} onOpenChange={setPvOpen}>
        <DialogContent className="w-[min(680px,94vw)]">
          <DialogHeader>
            <DialogTitle>PV / 预告片</DialogTitle>
          </DialogHeader>
          <DialogBody>
            <div className="grid aspect-video place-items-center overflow-hidden rounded-[14px] bg-[linear-gradient(135deg,#243239,#0d4d3a)]">
              <span className="text-mint-600 grid size-[66px] place-items-center rounded-full bg-white/90 opacity-60 shadow-[var(--shadow-md)]">
                <Play className="size-7 fill-current" />
              </span>
            </div>
            <div className="mt-3.5 flex flex-wrap gap-2">
              <Badge variant="outline">暂无 PV 源</Badge>
              {(activeSubject.tags ?? []).slice(0, 4).map((tag, i) => (
                <Badge key={tag.name} variant={i === 0 ? "mint" : "outline"}>
                  {tag.name}
                </Badge>
              ))}
            </div>
          </DialogBody>
        </DialogContent>
      </Dialog>

      <Dialog
        open={detailDialog === "synopsis"}
        onOpenChange={(open) => !open && setDetailDialog(null)}
      >
        <DialogContent className="w-[min(720px,94vw)]">
          <DialogHeader>
            <DialogTitle>简介 · {activeSubject.nameCn ?? activeSubject.name}</DialogTitle>
          </DialogHeader>
          <DialogBody className="max-h-[70vh] overflow-auto">
            <div className="[&>p]:text-ink-soft [&>p]:mt-3 [&>p]:leading-[1.9] [&>p:first-child]:mt-0">
              {synopsis.map((paragraph, i) => (
                <p key={i}>{paragraph}</p>
              ))}
            </div>
          </DialogBody>
        </DialogContent>
      </Dialog>

      <Dialog
        open={detailDialog === "characters"}
        onOpenChange={(open) => !open && setDetailDialog(null)}
      >
        <DialogContent className="w-[min(860px,94vw)]">
          <DialogHeader>
            <DialogTitle>全部角色 · {activeSubject.nameCn ?? activeSubject.name}</DialogTitle>
          </DialogHeader>
          <DialogBody className="max-h-[72vh] overflow-auto">
            <div className="grid grid-cols-[repeat(auto-fill,minmax(124px,1fr))] gap-3">
              {characters.map((character, index) => (
                <CreditCard key={character.id} credit={character} index={index} />
              ))}
            </div>
          </DialogBody>
        </DialogContent>
      </Dialog>

      <Dialog
        open={detailDialog === "staff"}
        onOpenChange={(open) => !open && setDetailDialog(null)}
      >
        <DialogContent className="w-[min(860px,94vw)]">
          <DialogHeader>
            <DialogTitle>全部制作团队 · {activeSubject.nameCn ?? activeSubject.name}</DialogTitle>
          </DialogHeader>
          <DialogBody className="max-h-[72vh] overflow-auto">
            <div className="grid grid-cols-[repeat(auto-fill,minmax(124px,1fr))] gap-3">
              {staff.map((member, index) => (
                <CreditCard key={member.key} credit={member} index={index} />
              ))}
            </div>
          </DialogBody>
        </DialogContent>
      </Dialog>
    </>
  );
}

function CreditCard({
  credit,
  index
}: {
  credit: CharacterCardModel | StaffCardModel;
  index: number;
}) {
  return (
    <div className="min-w-0">
      <div className="relative aspect-[3/4] overflow-hidden rounded-[14px] shadow-[var(--shadow-sm)]">
        {credit.imageUrl ? (
          <>
            <div
              className="absolute inset-0 opacity-20"
              style={{ background: staffGradient(index) }}
            />
            <img
              src={credit.imageUrl}
              alt=""
              loading="lazy"
              className="absolute inset-0 size-full object-cover object-top"
            />
          </>
        ) : (
          <>
            <div className="absolute inset-0" style={{ background: staffGradient(index) }} />
            <span className="absolute inset-0 grid place-items-center text-4xl font-extrabold text-white/35">
              {credit.initial}
            </span>
          </>
        )}
      </div>
      <b className="mt-2 block truncate text-center text-[13px]">{credit.name}</b>
      <small className="text-ink-faint mt-0.5 block truncate text-center text-[11px] font-bold">
        {"actorName" in credit && credit.actorName
          ? `${credit.role} · ${credit.actorName}`
          : credit.role}
      </small>
    </div>
  );
}

function splitSynopsis(summary: string | undefined): string[] {
  if (!summary?.trim()) {
    return ["暂无简介。"];
  }

  return summary
    .split(/\n{2,}|\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function buildMediaOptions(
  tasks: DownloadTaskView[],
  files: DownloadFileView[]
): Array<{ key: string; label: string }> {
  const completedTasks = new Map(
    tasks.filter((task) => task.status === "completed").map((task) => [task.id, task])
  );

  return files
    .filter((file) => file.mediaKind === "video" && completedTasks.has(file.downloadId))
    .map((file) => {
      const task = completedTasks.get(file.downloadId);
      const priority = task?.selectedFileId === file.id ? "默认" : "视频";
      return {
        key: `${file.downloadId}|${file.id}`,
        label: `${priority} · ${file.name || task?.title || file.id}`
      };
    });
}

function toMessage(error: unknown, fallback: string): string {
  if (error instanceof Error) {
    return error.message || fallback;
  }
  return fallback;
}

function previewSynopsis(paragraphs: string[], maxLength: number): string[] {
  const preview: string[] = [];
  let used = 0;

  for (const paragraph of paragraphs) {
    const remaining = maxLength - used;
    if (remaining <= 0 || preview.length >= 2) {
      break;
    }

    if (paragraph.length > remaining) {
      preview.push(`${paragraph.slice(0, Math.max(0, remaining)).trimEnd()}…`);
      break;
    }

    preview.push(paragraph);
    used += paragraph.length;
  }

  return preview.length > 0 ? preview : paragraphs.slice(0, 1);
}

function buildStaff(subject: SubjectDetail | null): StaffCardModel[] {
  if (subject?.staff?.length) {
    return sortStaffCredits(subject.staff).map((member) => {
      const name = member.displayName || member.nameCn || member.name;
      const role = member.role ?? member.relation ?? "制作人员";
      return {
        key: `${member.personId ?? name}-${role}`,
        role,
        name,
        imageUrl: member.imageUrl || undefined,
        initial: name.slice(0, 1)
      };
    });
  }

  if (!subject?.infoBox) {
    return [];
  }

  const staffKeys = new Set([
    "原作",
    "导演",
    "监督",
    "脚本",
    "系列构成",
    "人物设定",
    "音乐",
    "动画制作",
    "製作",
    "制作"
  ]);

  return subject.infoBox
    .filter((entry) => staffKeys.has(entry.key))
    .sort((a, b) => staffPriority(a.key) - staffPriority(b.key))
    .map((entry) => ({
      key: `${entry.key}-${entry.value}`,
      role: entry.key,
      name: entry.value,
      imageUrl: undefined,
      initial: entry.value.slice(0, 1) || entry.key.slice(0, 1)
    }));
}

function buildCharacters(subject: SubjectDetail | null): CharacterCardModel[] {
  if (!subject?.characters?.length) {
    return [];
  }

  return subject.characters.map((character) => {
    const actor = character.actors[0];
    const characterName = character.displayName || character.nameCn || character.name;
    const actorName = actor ? actor.displayName || actor.nameCn || actor.name : undefined;
    return {
      id: character.characterId,
      role: character.role ?? "角色",
      name: characterName,
      actorName,
      imageUrl: character.imageUrl || undefined,
      initial: characterName.slice(0, 1)
    };
  });
}

function isMainCharacterRole(role: string): boolean {
  return /主角|主人公|main/i.test(role);
}

function sortStaffCredits(staff: SubjectStaffCredit[]): SubjectStaffCredit[] {
  return staff
    .map((member, index) => ({ member, index }))
    .sort((a, b) => {
      const priority = staffPriority(a.member.role ?? a.member.relation ?? "");
      const nextPriority = staffPriority(b.member.role ?? b.member.relation ?? "");
      return priority - nextPriority || a.index - b.index;
    })
    .map((entry) => entry.member);
}

function staffPriority(role: string): number {
  const priorityRoles = [
    /原作|原案|原著/,
    /导演|監督|监督|总导演|总监督/,
    /系列构成|シリーズ構成/,
    /脚本|剧本/,
    /人物设定|角色设计|キャラクターデザイン/,
    /动画制作|アニメーション制作|制作公司|製作会社/,
    /音乐|音楽/,
    /美术|美術/,
    /色彩/,
    /摄影|撮影/,
    /音响|音響/,
    /制片|企画|製作/
  ];
  const index = priorityRoles.findIndex((pattern) => pattern.test(role));
  return index >= 0 ? index : priorityRoles.length;
}

function staffGradient(index: number): string {
  const gradients = [
    "#9be7c4,#3aa17e",
    "#ffd56b,#ff7a5b",
    "#86c5ff,#3f74c4",
    "#ffb3c7,#ff6b9d",
    "#c0a8ff,#7d5fe0",
    "#8fe3d6,#3aa1a8"
  ];

  return `linear-gradient(135deg,${gradients[index % gradients.length]})`;
}
