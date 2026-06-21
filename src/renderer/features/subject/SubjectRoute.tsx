import { useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { ChevronLeft, Play } from "lucide-react";
import type {
  CollectionStatus,
  EpisodeCollectionState,
  SubjectDetail
} from "@shared/contracts/bangumi";
import { useAppState } from "@/app/AppStateProvider";
import { SubjectHero } from "./components/SubjectHero";
import { SubjectTabs } from "./components/SubjectTabs";
import { GradientAvatar } from "@/components/melon/GradientAvatar";
import { IconButton, PageContent, Topbar } from "@/components/melon/layout";
import { Badge } from "@/components/ui/badge";
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

function SectionTitle({ size, children }: { size: 16 | 18; children: ReactNode }) {
  return (
    <div className="mb-3 font-extrabold" style={{ fontSize: size }}>
      {children}
    </div>
  );
}

export function SubjectRoute() {
  const navigate = useNavigate();
  const { subjectId } = useParams();
  const { getSubject, updateTracking } = useAppState();
  const [subject, setSubject] = useState<SubjectDetail | null>(null);
  const [loadingError, setLoadingError] = useState<string | null>(null);
  const [epOpen, setEpOpen] = useState(false);
  const [pvOpen, setPvOpen] = useState(false);

  useEffect(() => {
    if (!subjectId) {
      return;
    }

    let ignore = false;
    void getSubject(Number(subjectId))
      .then((nextSubject) => {
        if (!ignore) {
          setLoadingError(null);
          setSubject(nextSubject);
        }
      })
      .catch((error) => {
        if (!ignore) {
          setLoadingError(error instanceof Error ? error.message : "条目加载失败");
        }
      });

    return () => {
      ignore = true;
    };
  }, [getSubject, subjectId]);

  const synopsis = useMemo(() => splitSynopsis(subject?.summary), [subject?.summary]);
  const staff = useMemo(() => buildStaff(subject), [subject]);
  const nextEpisode = useMemo(
    () =>
      subject?.episodes.find(
        (episode) => episode.status === "queue" || episode.status === "unwatched"
      ),
    [subject?.episodes]
  );

  async function reloadSubject(): Promise<void> {
    if (!subject) {
      return;
    }
    setSubject(await getSubject(subject.subjectId));
  }

  async function changeStatus(status: CollectionStatus): Promise<void> {
    if (!subject) {
      return;
    }

    await updateTracking({
      kind: "subjectCollection",
      subjectId: subject.subjectId,
      status
    });
    await reloadSubject();
  }

  async function toggleEpisode(episode: EpisodeCollectionState): Promise<void> {
    await updateTracking({
      kind: "episodeCollection",
      episodeId: episode.episodeId,
      status: episode.status === "watched" ? "queue" : "watched"
    });
    await reloadSubject();
  }

  if (!subject) {
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
            {loadingError ?? "加载条目中…"}
          </div>
        </PageContent>
      </>
    );
  }

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
          subject={subject}
          onOpenEpisodes={() => setEpOpen(true)}
          onOpenPv={() => setPvOpen(true)}
          onChangeStatus={(status) => void changeStatus(status)}
        />

        <div className="border-line bg-surface mt-5 rounded-[20px] border p-[18px] shadow-[var(--shadow-sm)]">
          <SectionTitle size={18}>简介</SectionTitle>
          <div className="[&>p]:text-ink-soft [&>p]:mt-3 [&>p]:leading-[1.85] [&>p:first-child]:mt-0">
            {synopsis.map((paragraph, i) => (
              <p key={i}>{paragraph}</p>
            ))}
          </div>

          <Divider />

          <SectionTitle size={16}>主要声优</SectionTitle>
          <div className="border-line bg-surface-2 text-ink-faint rounded-[14px] border p-5 text-sm font-semibold">
            暂未加载声优信息。
          </div>

          <Divider />

          <SectionTitle size={16}>制作团队</SectionTitle>
          {staff.length > 0 ? (
            <div className="grid grid-cols-2 gap-2.5">
              {staff.map((member, index) => (
                <div key={`${member.role}-${member.name}`} className="flex items-center gap-2.5">
                  <GradientAvatar
                    initial={member.initial}
                    gradient={staffGradient(index)}
                    size="sm"
                  />
                  <div>
                    <b className="text-[13px]">{member.name}</b>
                    <small className="text-ink-faint block text-[11px]">{member.role}</small>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="border-line bg-surface-2 text-ink-faint rounded-[14px] border p-4 text-sm font-semibold">
              Bangumi 条目详情暂未提供可展示的制作团队字段。
            </div>
          )}

          <Divider />

          <SubjectTabs />
        </div>
      </PageContent>

      <Dialog open={epOpen} onOpenChange={setEpOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>选集 · {subject.nameCn ?? subject.name}</DialogTitle>
          </DialogHeader>
          <DialogBody>
            <div className="mb-3.5 flex items-center gap-2">
              <Badge variant="mint">Bangumi 章节进度</Badge>
              <Badge variant="outline">
                {nextEpisode ? `下一话 EP${nextEpisode.sort}` : "已看完"}
              </Badge>
              <span className="text-ink-faint text-xs">点击章节可切换看过状态</span>
            </div>
            <div className="grid grid-cols-[repeat(auto-fill,minmax(58px,1fr))] gap-[9px]">
              {subject.episodes.map((episode) => (
                <button
                  key={episode.episodeId}
                  type="button"
                  onClick={() => void toggleEpisode(episode)}
                  className={cn(
                    "relative grid aspect-square place-items-center rounded-[11px] border text-[15px] font-extrabold transition",
                    episode.episodeId === nextEpisode?.episodeId &&
                      "text-on-accent border-transparent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_6px_14px_rgba(34,179,136,.3)]",
                    episode.status === "watched" &&
                      episode.episodeId !== nextEpisode?.episodeId &&
                      "border-mint-200 bg-mint-50 text-mint-600",
                    episode.status !== "watched" &&
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
              {(subject.tags ?? []).slice(0, 4).map((tag, i) => (
                <Badge key={tag.name} variant={i === 0 ? "mint" : "outline"}>
                  {tag.name}
                </Badge>
              ))}
            </div>
          </DialogBody>
        </DialogContent>
      </Dialog>
    </>
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

function buildStaff(subject: SubjectDetail | null): Array<{
  role: string;
  name: string;
  initial: string;
}> {
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
    .slice(0, 8)
    .map((entry) => ({
      role: entry.key,
      name: entry.value,
      initial: entry.value.slice(0, 1) || entry.key.slice(0, 1)
    }));
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
