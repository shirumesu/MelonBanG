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
  const { getSubject, updateTracking } = useAppState();
  const [subject, setSubject] = useState<SubjectDetail | null>(null);
  const [loadingError, setLoadingError] = useState<string | null>(null);
  const [epOpen, setEpOpen] = useState(false);
  const [pvOpen, setPvOpen] = useState(false);
  const [detailDialog, setDetailDialog] = useState<DetailDialog>(null);

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
  const synopsisHasMore = synopsis.length > 2 || synopsis.join("").length > 260;
  const visibleSynopsis = useMemo(
    () => (synopsisHasMore ? previewSynopsis(synopsis, 260) : synopsis),
    [synopsis, synopsisHasMore]
  );
  const characters = useMemo(() => buildCharacters(subject), [subject]);
  const visibleCharacters = useMemo(() => {
    const mainCharacters = characters.filter((character) => isMainCharacterRole(character.role));
    return (mainCharacters.length > 0 ? mainCharacters : characters).slice(0, 6);
  }, [characters]);
  const staff = useMemo(() => buildStaff(subject), [subject]);
  const visibleStaff = staff.slice(0, 6);
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

          <SubjectTabs comments={subject.comments ?? []} topics={subject.topics ?? []} />
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

      <Dialog
        open={detailDialog === "synopsis"}
        onOpenChange={(open) => !open && setDetailDialog(null)}
      >
        <DialogContent className="w-[min(720px,94vw)]">
          <DialogHeader>
            <DialogTitle>简介 · {subject.nameCn ?? subject.name}</DialogTitle>
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
            <DialogTitle>全部角色 · {subject.nameCn ?? subject.name}</DialogTitle>
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
            <DialogTitle>全部制作团队 · {subject.nameCn ?? subject.name}</DialogTitle>
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
