import { useState } from "react";
import type { ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { ChevronLeft, Play } from "lucide-react";
import { SUBJECT_DEMO, buildEpisodes } from "@/data/subject";
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
  const subject = SUBJECT_DEMO;
  const episodes = buildEpisodes();
  const [epOpen, setEpOpen] = useState(false);
  const [pvOpen, setPvOpen] = useState(false);

  const playEpisode = (): void => {
    setEpOpen(false);
    void navigate("/player");
  };

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
        <SubjectHero onOpenEpisodes={() => setEpOpen(true)} onOpenPv={() => setPvOpen(true)} />

        <div className="border-line bg-surface mt-5 rounded-[20px] border p-[18px] shadow-[var(--shadow-sm)]">
          <SectionTitle size={18}>简介</SectionTitle>
          <div className="[&>p]:text-ink-soft [&>p]:mt-3 [&>p]:leading-[1.85] [&>p:first-child]:mt-0">
            {subject.synopsis.map((paragraph, i) => (
              <p key={i}>{paragraph}</p>
            ))}
          </div>

          <Divider />

          <SectionTitle size={16}>主要声优</SectionTitle>
          <div className="grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-4">
            {subject.voiceActors.map((va) => (
              <div key={va.name} className="flex flex-col items-center gap-1.5">
                <div
                  className="relative grid aspect-2/3 w-full place-items-center overflow-hidden rounded-[14px] shadow-[var(--shadow-sm)]"
                  style={{ background: va.gradient }}
                >
                  <span className="text-[48px] font-extrabold text-white/20">{va.kanji}</span>
                </div>
                <div className="text-ink text-[15px] font-extrabold">{va.name}</div>
                <div className="text-ink-faint text-xs font-semibold">{va.role}</div>
              </div>
            ))}
          </div>

          <Divider />

          <SectionTitle size={16}>制作团队</SectionTitle>
          <div className="grid grid-cols-2 gap-2.5">
            {subject.staff.map((member) => (
              <div key={member.role} className="flex items-center gap-2.5">
                <GradientAvatar initial={member.initial} gradient={member.gradient} size="sm" />
                <div>
                  <b className="text-[13px]">{member.name}</b>
                  <small className="text-ink-faint block text-[11px]">{member.role}</small>
                </div>
              </div>
            ))}
          </div>

          <Divider />

          <SubjectTabs />
        </div>
      </PageContent>

      {/* 选集 modal */}
      <Dialog open={epOpen} onOpenChange={setEpOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>选集 · {subject.title}</DialogTitle>
          </DialogHeader>
          <DialogBody>
            <div className="mb-3.5 flex items-center gap-2">
              <Badge variant="mint">本地缓存 1080P</Badge>
              <Badge variant="outline">在线 720P</Badge>
              <span className="text-ink-faint text-xs">来源：melonbang BT · 已缓存 6 话</span>
            </div>
            <div className="grid grid-cols-[repeat(auto-fill,minmax(58px,1fr))] gap-[9px]">
              {episodes.map((ep) => (
                <button
                  key={ep.n}
                  type="button"
                  disabled={ep.unaired}
                  onClick={ep.unaired ? undefined : playEpisode}
                  className={cn(
                    "relative grid aspect-square place-items-center rounded-[11px] border text-[15px] font-extrabold transition",
                    ep.current &&
                      "text-on-accent border-transparent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_6px_14px_rgba(34,179,136,.3)]",
                    ep.watched && !ep.current && "border-mint-200 bg-mint-50 text-mint-600",
                    ep.unaired &&
                      "text-ink-faint border-line cursor-not-allowed bg-[repeating-linear-gradient(45deg,var(--surface-2),var(--surface-2)_6px,var(--surface-3)_6px,var(--surface-3)_12px)] opacity-45",
                    !ep.current &&
                      !ep.watched &&
                      !ep.unaired &&
                      "border-line bg-surface text-ink-soft hover:border-mint-300 hover:text-mint-600 hover:-translate-y-0.5"
                  )}
                >
                  {ep.n}
                  {ep.watched && !ep.current ? (
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

      {/* PV modal */}
      <Dialog open={pvOpen} onOpenChange={setPvOpen}>
        <DialogContent className="w-[min(680px,94vw)]">
          <DialogHeader>
            <DialogTitle>PV / 预告片</DialogTitle>
          </DialogHeader>
          <DialogBody>
            <div className="grid aspect-video place-items-center overflow-hidden rounded-[14px] bg-[linear-gradient(135deg,#243239,#0d4d3a)]">
              <span className="text-mint-600 grid size-[66px] cursor-pointer place-items-center rounded-full bg-white/90 shadow-[var(--shadow-md)]">
                <Play className="size-7 fill-current" />
              </span>
            </div>
            <div className="mt-3.5 flex flex-wrap gap-2">
              {subject.pvTags.map((pvTag, i) => (
                <Badge key={pvTag} variant={i === 0 ? "mint" : "outline"}>
                  {pvTag}
                </Badge>
              ))}
            </div>
          </DialogBody>
        </DialogContent>
      </Dialog>
    </>
  );
}
