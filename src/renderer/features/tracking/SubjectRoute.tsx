import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";
import type {
  CollectionStatus,
  EpisodeCollectionState,
  SubjectDetail
} from "@shared/contracts/bangumi";
import { useAppState } from "@/app/AppStateProvider";
import { PageHeader, PageSection } from "@/components/melon/page";
import { collectionStatusMeta } from "@/components/melon/status";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { SubjectHero } from "./components/SubjectHero";
import { EpisodeGrid } from "./components/EpisodeGrid";

const subjectStatuses: CollectionStatus[] = ["watching", "wish", "on_hold", "completed", "dropped"];

export function SubjectRoute() {
  const { subjectId } = useParams();
  const { getSubject, updateTracking } = useAppState();
  const [subject, setSubject] = useState<SubjectDetail | null>(null);
  const [showAllEpisodes, setShowAllEpisodes] = useState(false);

  useEffect(() => {
    if (!subjectId) {
      return;
    }
    void getSubject(Number(subjectId)).then((nextSubject) => {
      setSubject(nextSubject);
    });
  }, [getSubject, subjectId]);

  const visibleEpisodes = useMemo(() => {
    if (!subject) {
      return [];
    }
    return showAllEpisodes ? subject.episodes : subject.episodes.slice(0, 12);
  }, [showAllEpisodes, subject]);

  if (!subject) {
    return <div className="text-muted-foreground py-8 text-sm font-semibold">加载条目中…</div>;
  }

  return (
    <div className="pb-8">
      <PageHeader title="番剧详情" subtitle={`${subject.name} · Bangumi 条目详情`} />

      <SubjectHero subject={subject} onOpenEpisodes={() => setShowAllEpisodes((value) => !value)} />

      <PageSection>
        <Card>
          <CardHeader>
            <CardTitle>追番状态</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-wrap items-center gap-3">
            {subjectStatuses.map((status) => {
              const meta = collectionStatusMeta[status];
              const active = subject.collection?.status === status;
              return (
                <Button
                  key={status}
                  variant={active ? "default" : "outline"}
                  onClick={() =>
                    void updateTracking({
                      kind: "subjectCollection",
                      subjectId: subject.subjectId,
                      status
                    })
                      .then(() => getSubject(subject.subjectId))
                      .then((nextSubject) => {
                        setSubject(nextSubject);
                      })
                  }
                >
                  {meta.label}
                </Button>
              );
            })}
          </CardContent>
        </Card>
      </PageSection>

      <PageSection>
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <div>
              <CardTitle>章节进度</CardTitle>
              <div className="text-muted-foreground mt-1 text-sm font-semibold">
                章节状态与 Bangumi 追番进度分开维护。
              </div>
            </div>
            <Button variant="outline" onClick={() => setShowAllEpisodes((value) => !value)}>
              {showAllEpisodes ? "收起" : "查看全部"}
            </Button>
          </CardHeader>
          <CardContent>
            <EpisodeGrid
              episodes={visibleEpisodes}
              onSelect={(episode) =>
                void toggleEpisode(episode, updateTracking)
                  .then(() => getSubject(subject.subjectId))
                  .then((nextSubject) => {
                    setSubject(nextSubject);
                  })
              }
            />
          </CardContent>
        </Card>
      </PageSection>

      <PageSection>
        <Tabs defaultValue="comments">
          <TabsList>
            <TabsTrigger value="comments">吐槽箱</TabsTrigger>
            <TabsTrigger value="pv">PV</TabsTrigger>
            <TabsTrigger value="discussions">讨论版</TabsTrigger>
          </TabsList>

          <TabsContent value="comments" className="mt-5">
            <Card>
              <CardContent className="grid gap-4 p-6">
                {commentSeeds.map((comment) => (
                  <div
                    key={comment.name + comment.time}
                    className="border-border bg-secondary/50 rounded-[16px] border p-4"
                  >
                    <div className="flex items-center gap-2">
                      <div className="text-sm font-black">{comment.name}</div>
                      <Badge variant={comment.status === "看过" ? "sky" : "mint"}>
                        {comment.status}
                      </Badge>
                      <div className="text-muted-foreground ml-auto text-xs font-semibold">
                        {comment.time}
                      </div>
                    </div>
                    <div className="text-muted-foreground mt-3 text-sm leading-7">
                      {comment.text}
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="pv" className="mt-5">
            <Card>
              <CardContent className="p-6">
                <div className="grid aspect-video place-items-center rounded-[16px] bg-linear-to-br from-[#243239] to-[#0d4d3a] text-white">
                  <div className="grid size-16 place-items-center rounded-full bg-white/90 text-[var(--mint-600)]">
                    ▶
                  </div>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="discussions" className="mt-5">
            <Card>
              <CardContent className="p-6">
                <div className="grid gap-3">
                  {discussionSeeds.map((discussion) => (
                    <div
                      key={discussion.title}
                      className="border-border flex items-center gap-3 border-b pb-3 last:border-0"
                    >
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-sm font-black">{discussion.title}</div>
                      </div>
                      <div className="text-muted-foreground text-xs font-semibold">
                        {discussion.author} · {discussion.replies}
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </PageSection>
    </div>
  );
}

async function toggleEpisode(
  episode: EpisodeCollectionState,
  updateTracking: (input: {
    kind: "episodeCollection";
    episodeId: number;
    status: EpisodeCollectionState["status"];
  }) => Promise<void>
): Promise<void> {
  const nextStatus =
    episode.status === "watched"
      ? "queue"
      : episode.status === "queue"
        ? "watched"
        : episode.status === "dropped"
          ? "queue"
          : "watched";
  await updateTracking({
    kind: "episodeCollection",
    episodeId: episode.episodeId,
    status: nextStatus
  });
}

const commentSeeds = [
  {
    name: "宅宅鸿",
    status: "看过",
    time: "21h ago",
    text: "这季作画稳得离谱，每一帧都能当壁纸，EP07 直接破防。"
  },
  {
    name: "012606",
    status: "在看",
    time: "22h ago",
    text: "冈崎线之后的情绪递进很成熟，原创动画能写成这样不容易。"
  },
  { name: "Mi", status: "在看", time: "1d ago", text: "请用眼泪付款。" }
] as const;

const discussionSeeds = [
  { title: "难以理解的误解与批评", author: "愿世长安", replies: "10 replies" },
  { title: "第二季作画的一点疑问", author: "泽渡真琴", replies: "249 replies" },
  { title: "浅谈大家心目中“神作”的槽点", author: "饿龙ou", replies: "82 replies" }
] as const;
