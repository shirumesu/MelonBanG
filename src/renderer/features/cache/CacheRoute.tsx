import { useState } from "react";
import {
  ArrowDownToLine,
  ArrowUp,
  CheckCircle2,
  ChevronRight,
  Clock3,
  Folder,
  FolderOpen,
  Pause,
  Trash2
} from "lucide-react";
import {
  CACHE_TABS,
  COMPLETED,
  DOWNLOADING,
  QUEUED,
  STORAGE,
  type DownloadTask,
  type QueuedTask
} from "@/data/cache";
import { Poster } from "@/components/melon/Poster";
import { IconButton, PageContent, Section, SectionHead, Topbar } from "@/components/melon/layout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { artGradient } from "@/data/artwork";
import { cn } from "@/lib/utils";

const CACHE_TAB_ICONS = [ArrowDownToLine, Clock3, CheckCircle2, FolderOpen];

function Cover({
  index,
  kanji,
  desaturate
}: {
  index: number;
  kanji: string;
  desaturate?: boolean;
}) {
  return (
    <div
      className="relative h-16 w-12 flex-none overflow-hidden rounded-[9px] shadow-[var(--shadow-sm)]"
      style={{ background: artGradient(index), filter: desaturate ? "saturate(.7)" : undefined }}
    >
      <span className="absolute inset-0 grid place-items-center text-[22px] font-extrabold text-white/35">
        {kanji}
      </span>
    </div>
  );
}

function DownloadRow({ task, first }: { task: DownloadTask; first: boolean }) {
  return (
    <div className={cn("flex items-center gap-3.5 px-4 py-3.5", !first && "border-line border-t")}>
      <Cover index={task.index} kanji={task.kanji} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-[13.5px] font-bold">
            {task.title} · EP{task.ep} [{task.quality}]
          </span>
          {task.tag ? (
            <Badge variant="mint" className="text-[10px]">
              {task.tag}
            </Badge>
          ) : null}
        </div>
        <div className="mt-[7px] flex items-center gap-3">
          <div className="bg-surface-3 h-1.5 flex-1 overflow-hidden rounded-full">
            <div
              className="h-full rounded-full"
              style={{
                width: `${task.pct}%`,
                background:
                  task.tag === "校验中"
                    ? "linear-gradient(90deg,#ffd56b,#ffb83d)"
                    : "linear-gradient(90deg,var(--mint-400),var(--mint-300))"
              }}
            />
          </div>
          <span className="text-ink-soft w-[42px] flex-none text-right text-[13px] font-extrabold">
            {task.pct}%
          </span>
        </div>
        <div className="text-ink-faint mt-1.5 flex flex-wrap gap-3.5 text-[11.5px] font-semibold">
          <span className="text-mint-600">↓ {task.speed} MB/s</span>
          <span>
            {task.done} / {task.total}
          </span>
          <span>剩余 {task.eta}</span>
          <span>
            做种 ↑{task.up} 连接 ↓{task.peer}
          </span>
        </div>
      </div>
      <div className="flex flex-none gap-2">
        <IconButton title="暂停">
          <Pause />
        </IconButton>
        <IconButton title="删除">
          <Trash2 />
        </IconButton>
      </div>
    </div>
  );
}

function QueueRow({ task, first }: { task: QueuedTask; first: boolean }) {
  return (
    <div className={cn("flex items-center gap-3.5 px-4 py-3.5", !first && "border-line border-t")}>
      <Cover index={task.index} kanji={task.kanji} desaturate />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-[13.5px] font-bold">
            {task.title} · EP{task.ep} [{task.quality}]
          </span>
          <Badge variant="outline" className="text-[10px]">
            排队中
          </Badge>
        </div>
        <div className="text-ink-faint mt-1.5 flex flex-wrap gap-3.5 text-[11.5px] font-semibold">
          <span>等待下载 · {task.size}</span>
          <span>队列位置 {task.position}</span>
        </div>
      </div>
      <div className="flex flex-none gap-2">
        <IconButton title="优先">
          <ArrowUp />
        </IconButton>
        <IconButton title="删除">
          <Trash2 />
        </IconButton>
      </div>
    </div>
  );
}

export function CacheRoute() {
  const [tab, setTab] = useState(0);

  return (
    <>
      <Topbar title="缓存" subtitle="下载与本地缓存">
        <Button variant="outline" size="sm">
          <Pause className="size-4" />
          全部暂停
        </Button>
        <Button variant="outline" size="sm">
          <Trash2 className="size-4" />
          清理已完成
        </Button>
        <Button variant="outline" size="sm">
          <Folder className="size-4" />
          缓存目录
        </Button>
      </Topbar>

      <PageContent>
        <Card className="flex items-center gap-[18px] p-[16px_18px]">
          <div
            className="grid size-[54px] flex-none place-items-center rounded-full"
            style={{
              background: "conic-gradient(var(--mint-400) 0 48%, var(--surface-3) 48% 100%)"
            }}
          >
            <div className="bg-surface text-mint-600 grid size-[42px] place-items-center rounded-full text-[13px] font-extrabold">
              {STORAGE.pct}%
            </div>
          </div>
          <div className="flex-1">
            <div className="flex items-center">
              <b className="text-[15px]">本地缓存</b>
              <div className="flex-1" />
              <span className="text-ink-faint text-xs">
                已用 {STORAGE.used} / {STORAGE.total}
              </span>
            </div>
            <div className="bg-surface-3 mt-2 h-1.5 overflow-hidden rounded-full">
              <div
                className="h-full rounded-full bg-[linear-gradient(90deg,var(--mint-400),var(--mint-300))]"
                style={{ width: `${STORAGE.pct}%` }}
              />
            </div>
            <div className="text-ink-faint mt-2 flex flex-wrap items-center gap-3.5 text-[11.5px] font-semibold">
              <span>
                <span className="text-mint-600">↓ {STORAGE.speed} MB/s</span> 当前总速度
              </span>
              <span>
                {STORAGE.downloading} 个任务下载中 · {STORAGE.queued} 个排队
              </span>
              <Badge variant="mint" className="text-[10px]">
                顺序缓存 · 边下边播
              </Badge>
            </div>
          </div>
        </Card>

        <div className="border-line bg-surface mt-5 inline-flex gap-1 rounded-full border p-1.5 shadow-[var(--shadow-sm)]">
          {CACHE_TABS.map((entry, i) => {
            const active = i === tab;
            const TabIcon = CACHE_TAB_ICONS[i] ?? FolderOpen;
            return (
              <button
                key={entry.label}
                type="button"
                onClick={() => setTab(i)}
                className={cn(
                  "inline-flex items-center gap-1.5 rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                  active
                    ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_5px_12px_rgba(34,179,136,.28)]"
                    : "text-ink-soft hover:text-ink"
                )}
              >
                <TabIcon className="size-4" />
                {entry.label}
                {entry.count ? (
                  <span
                    className={cn(
                      "rounded-full px-[7px] text-[11px] font-extrabold",
                      active ? "text-on-accent bg-white/50" : "bg-surface-3 text-ink-faint"
                    )}
                  >
                    {entry.count}
                  </span>
                ) : null}
              </button>
            );
          })}
        </div>

        <Section>
          <SectionHead
            title={
              <>
                <ArrowDownToLine className="text-mint-500 size-[15px]" />
                正在下载
              </>
            }
          />
          <Card className="overflow-hidden">
            {DOWNLOADING.map((task, i) => (
              <DownloadRow key={task.index} task={task} first={i === 0} />
            ))}
          </Card>
        </Section>

        <Section>
          <SectionHead
            title={
              <>
                <Clock3 className="text-gold-500 size-[15px]" />
                排队中
              </>
            }
          />
          <Card className="overflow-hidden">
            {QUEUED.map((task, i) => (
              <QueueRow key={task.index} task={task} first={i === 0} />
            ))}
          </Card>
        </Section>

        <Section>
          <SectionHead
            title={
              <>
                <CheckCircle2 className="size-[15px] text-sky-500" />
                已完成 · 可播放
              </>
            }
            action={
              <span className="text-ink-faint inline-flex cursor-pointer items-center gap-1 text-[12.5px] font-bold">
                管理 <ChevronRight className="size-4" />
              </span>
            }
          />
          <div className="grid [grid-template-columns:repeat(auto-fill,minmax(168px,1fr))] gap-4">
            {COMPLETED.map((item) => (
              <Poster
                key={item.index}
                index={item.index}
                href="/player"
                kanji={item.kanji}
                corner={
                  <Badge variant="mint" className="text-[10px]">
                    已缓存
                  </Badge>
                }
                footer={
                  <span>
                    {item.episodes} 集 · {item.size}
                  </span>
                }
                body={
                  <>
                    <div className="line-clamp-2 min-h-[34px] text-[13.5px] leading-tight font-bold">
                      {item.title}
                    </div>
                    <div className="text-ink-faint mt-1 flex items-center gap-1.5 text-[11.5px] font-semibold">
                      <span className="text-gold-500 font-extrabold">★ {item.score}</span>·
                      <span>本地 {item.quality}</span>
                    </div>
                  </>
                }
              />
            ))}
          </div>
        </Section>
      </PageContent>
    </>
  );
}
