import { ExternalLink, ListChecks, Play } from "lucide-react";
import type { SubjectDetail } from "@shared/contracts/bangumi";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { collectionStatusMeta } from "@/components/melon/status";
import { ArtworkCard } from "@/components/melon/artwork";

export function SubjectHero({
  subject,
  onOpenEpisodes
}: {
  subject: SubjectDetail;
  onOpenEpisodes: () => void;
}) {
  const collectionMeta = subject.collection
    ? collectionStatusMeta[subject.collection.status]
    : null;

  return (
    <Card className="border-border/90 relative overflow-hidden p-7">
      <div className="absolute inset-0 opacity-10 [background:radial-gradient(ellipse_650px_460px_at_22%_32%,#ffb84d,transparent),radial-gradient(ellipse_500px_360px_at_72%_52%,var(--mint-300),transparent),radial-gradient(ellipse_380px_300px_at_55%_92%,#ff8a5b,transparent)]" />
      <div className="relative grid grid-cols-[230px_1fr] gap-16">
        <div>
          <ArtworkCard
            id={subject.subjectId}
            title={subject.nameCn ?? subject.name}
            className="aspect-[3/4] rounded-[14px]"
          />
        </div>
        <div className="flex min-w-0 flex-col gap-3">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0">
              <h1 className="pr-12 text-[26px] font-black tracking-[0.01em]">
                {subject.nameCn ?? subject.name}
              </h1>
              <div className="text-muted-foreground mt-1 text-sm font-semibold">{subject.name}</div>
            </div>
            {collectionMeta ? (
              <Badge variant={collectionMeta.badgeVariant}>{collectionMeta.label}</Badge>
            ) : null}
          </div>

          <div className="flex flex-wrap gap-2">
            <Badge variant="gold">Rank #{subject.rank ?? "—"}</Badge>
            <Badge variant="outline">{subject.airDate ?? "未知日期"}</Badge>
            <Badge variant="outline">全 {subject.episodeTotal ?? "?"} 话</Badge>
          </div>

          <p className="text-muted-foreground max-w-[760px] text-sm leading-7">{subject.summary}</p>

          <div className="grid grid-cols-[auto_1fr] items-start gap-10 pt-2">
            <div>
              <div className="flex items-baseline gap-1">
                <span className="text-5xl font-black">{subject.score?.toFixed(1) ?? "—"}</span>
                <span className="text-muted-foreground text-xl font-bold">/10</span>
              </div>
              <div className="text-muted-foreground mt-2 text-xs font-semibold">
                Bangumi 用户评分
              </div>
            </div>

            <div className="grid grid-cols-5 gap-4 text-center">
              <Stat label="条目排名" value={`#${subject.rank ?? "—"}`} />
              <Stat label="总集数" value={String(subject.episodeTotal ?? "—")} />
              <Stat label="我的评分" value={String(subject.collection?.score || "—")} />
              <Stat
                label="状态"
                value={
                  subject.collection
                    ? collectionStatusMeta[subject.collection.status].label
                    : "未收藏"
                }
              />
              <Stat
                label="下一话"
                value={
                  subject.episodes.find(
                    (episode) => episode.status === "queue" || episode.status === "unwatched"
                  )?.nameCn ?? "已看完"
                }
              />
            </div>
          </div>

          <Separator className="my-1" />

          <div className="flex flex-wrap gap-3">
            <Button size="lg">
              <Play className="size-4 fill-current" />
              继续播放
            </Button>
            <Button size="lg" variant="secondary" onClick={onOpenEpisodes}>
              <ListChecks className="size-4" />
              选集
            </Button>
            <Button size="lg" variant="outline" asChild>
              <a
                href={`https://bgm.tv/subject/${subject.subjectId}`}
                target="_blank"
                rel="noreferrer"
              >
                <ExternalLink className="size-4" />
                打开 Bangumi
              </a>
            </Button>
          </div>
        </div>
      </div>
    </Card>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-[20px] font-black">{value}</div>
      <div className="text-muted-foreground mt-1 text-[11px] font-semibold">{label}</div>
    </div>
  );
}
