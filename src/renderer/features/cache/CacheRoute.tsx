import { useEffect, useMemo, useState, type FormEvent } from "react";
import {
  ArrowDownToLine,
  CheckCircle2,
  ChevronRight,
  Clock3,
  Folder,
  FolderOpen,
  Pause,
  Play,
  Trash2
} from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import type {
  DownloadSnapshot,
  DownloadStatus,
  DownloadTaskView
} from "@shared/contracts/download";
import { IconButton, PageContent, Section, SectionHead, Topbar } from "@/components/melon/layout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { artGradient } from "@/data/artwork";
import { cn } from "@/lib/utils";

const CACHE_TAB_ICONS = [ArrowDownToLine, Clock3, CheckCircle2, FolderOpen];
const emptySnapshot: DownloadSnapshot = { tasks: [], files: [] };

function Cover({
  index,
  kanji,
  imageUrl,
  desaturate
}: {
  index: number;
  kanji: string;
  imageUrl?: string;
  desaturate?: boolean;
}) {
  return (
    <div
      className={cn(
        "relative flex-none overflow-hidden shadow-[var(--shadow-sm)]",
        imageUrl ? "h-[84px] w-[150px] rounded-[12px]" : "h-[82px] w-[64px] rounded-[10px]"
      )}
      style={{ background: artGradient(index), filter: desaturate ? "saturate(.7)" : undefined }}
    >
      {imageUrl ? (
        <img
          src={imageUrl}
          alt=""
          className="absolute inset-0 size-full object-cover"
          loading="lazy"
          decoding="async"
          referrerPolicy="no-referrer"
        />
      ) : (
        <span className="absolute inset-0 grid place-items-center text-[24px] font-extrabold text-white/35">
          {kanji}
        </span>
      )}
    </div>
  );
}

function DownloadRow({
  task,
  imageUrl,
  first,
  onPause,
  onRemove
}: {
  task: DownloadTaskView;
  imageUrl?: string;
  first: boolean;
  onPause: (downloadId: string) => void;
  onRemove: (downloadId: string) => void;
}) {
  const pct = progressPercent(task);
  return (
    <div className={cn("flex items-center gap-4 px-[18px] py-4", !first && "border-line border-t")}>
      <Cover index={coverIndex(task.id)} kanji={coverMark(task.title)} imageUrl={imageUrl} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-[13.5px] font-bold">{formatTaskTitle(task)}</span>
          {task.status === "metadata" ? (
            <Badge variant="mint" className="text-[10px]">
              解析中
            </Badge>
          ) : null}
          {task.status === "ready" ? (
            <Badge variant="mint" className="text-[10px]">
              可播放
            </Badge>
          ) : null}
        </div>
        <div className="mt-[7px] flex items-center gap-3">
          <div className="bg-surface-3 h-1.5 flex-1 overflow-hidden rounded-full">
            <div
              className="h-full rounded-full"
              style={{
                width: `${pct}%`,
                background: "linear-gradient(90deg,var(--mint-400),var(--mint-300))"
              }}
            />
          </div>
          <span className="text-ink-soft w-[42px] flex-none text-right text-[13px] font-extrabold">
            {pct}%
          </span>
        </div>
        <div className="text-ink-faint mt-1.5 flex flex-wrap gap-3.5 text-[11.5px] font-semibold">
          <span className="text-mint-600">
            ↓ {formatMegabytesPerSecond(task.downloadSpeedBytesPerSecond)} MB/s
          </span>
          <span>
            {formatBytes(task.downloadedBytes)} / {formatBytes(task.totalBytes)}
          </span>
          <span>剩余 {formatEta(task.etaSeconds)}</span>
          <span>
            做种 ↑{formatMegabytesPerSecond(task.uploadSpeedBytesPerSecond)} 连接 ↓{task.peerCount}
          </span>
        </div>
        <PreviewSourceLine task={task} />
      </div>
      <div className="flex flex-none gap-2">
        <IconButton title="暂停" onClick={() => onPause(task.id)}>
          <Pause />
        </IconButton>
        <IconButton title="删除" onClick={() => onRemove(task.id)}>
          <Trash2 />
        </IconButton>
      </div>
    </div>
  );
}

function QueueRow({
  task,
  imageUrl,
  first,
  onResume,
  onRemove
}: {
  task: DownloadTaskView;
  imageUrl?: string;
  first: boolean;
  onResume: (downloadId: string) => void;
  onRemove: (downloadId: string) => void;
}) {
  return (
    <div className={cn("flex items-center gap-4 px-[18px] py-4", !first && "border-line border-t")}>
      <Cover
        index={coverIndex(task.id)}
        kanji={coverMark(task.title)}
        imageUrl={imageUrl}
        desaturate
      />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-[13.5px] font-bold">{formatTaskTitle(task)}</span>
          <Badge variant={task.status === "failed" ? "outline" : "mint"} className="text-[10px]">
            {statusLabel(task.status)}
          </Badge>
        </div>
        <div className="text-ink-faint mt-1.5 flex flex-wrap gap-3.5 text-[11.5px] font-semibold">
          <span>
            {task.errorMessage ? task.errorMessage : `已缓存 ${formatBytes(task.downloadedBytes)}`}
          </span>
          <span>任务状态 {statusLabel(task.status)}</span>
        </div>
        <PreviewSourceLine task={task} />
      </div>
      <div className="flex flex-none gap-2">
        <IconButton
          title={task.status === "failed" ? "重试" : "继续"}
          onClick={() => onResume(task.id)}
        >
          <Play />
        </IconButton>
        <IconButton title="删除" onClick={() => onRemove(task.id)}>
          <Trash2 />
        </IconButton>
      </div>
    </div>
  );
}

function CompletedDownloadCard({
  item,
  onPlay
}: {
  item: DownloadTaskView;
  onPlay: (item: DownloadTaskView) => void;
}) {
  return (
    <div className="flex min-w-0 flex-col">
      <Link
        to="/player"
        onClick={(event) => {
          event.preventDefault();
          onPlay(item);
        }}
        className="group flex min-w-0 flex-col transition-transform duration-200 hover:-translate-y-0.5"
      >
        <div
          className={cn(
            "relative overflow-hidden rounded-[14px] shadow-[var(--shadow-md)] transition group-hover:shadow-[var(--shadow-lg)]",
            item.previewImageUrl ? "aspect-video" : "aspect-3/4"
          )}
          style={{ background: artGradient(coverIndex(item.id)) }}
        >
          {item.previewImageUrl ? (
            <img
              src={item.previewImageUrl}
              alt=""
              className="absolute inset-0 size-full object-cover"
              loading="lazy"
              decoding="async"
              referrerPolicy="no-referrer"
            />
          ) : (
            <span className="absolute inset-0 grid place-items-center text-6xl font-extrabold text-white/20 [text-shadow:0_2px_10px_rgba(0,0,0,.15)]">
              {coverMark(item.title)}
            </span>
          )}
          <div className="absolute inset-0 bg-[linear-gradient(180deg,transparent_38%,rgba(0,0,0,.62))]" />
          <div className="absolute top-2 right-2 z-[2]">
            <Badge variant="mint" className="text-[10px]">
              已缓存
            </Badge>
          </div>
          <span className="absolute inset-0 grid place-items-center opacity-0 transition group-hover:opacity-100">
            <span className="text-mint-600 grid size-[46px] place-items-center rounded-full bg-white/90 shadow-[var(--shadow-md)]">
              <Play className="size-5 fill-current" />
            </span>
          </span>
          <div className="absolute right-2 bottom-2 left-2 z-[2] flex items-center justify-between text-[11.5px] font-bold text-white">
            <span>{formatBytes(item.totalBytes ?? item.downloadedBytes)}</span>
          </div>
        </div>
        <div className="px-0.5 pt-2">
          <div className="line-clamp-2 min-h-[34px] text-[13.5px] leading-tight font-bold">
            {item.title}
          </div>
          <div className="text-ink-faint mt-1 flex items-center gap-1.5 text-[11.5px] font-semibold">
            <span className="text-gold-500 font-extrabold">★ 本地</span>·
            <span>{inferQuality(item.title)}</span>
          </div>
        </div>
      </Link>
      <div className="px-0.5">
        <PreviewSourceLine task={item} compact />
      </div>
    </div>
  );
}

function EmptyRow({ children }: { children: string }) {
  return <div className="text-ink-faint px-4 py-4 text-[12.5px] font-bold">{children}</div>;
}

function PreviewSourceLine({
  task,
  compact = false
}: {
  task: DownloadTaskView;
  compact?: boolean;
}) {
  if (!task.previewSourceName || !task.previewSourceUrl) {
    return null;
  }

  return (
    <div
      className={cn(
        "text-ink-faint font-semibold",
        compact ? "mt-1 text-[10.5px]" : "mt-1.5 text-[10.5px]"
      )}
    >
      {task.previewImageUrl ? "文件信息与预览图来自 " : "文件信息来自 "}
      <a
        href={task.previewSourceUrl}
        target="_blank"
        rel="noreferrer"
        className="underline-offset-2 hover:underline"
      >
        {task.previewSourceName}
      </a>
    </div>
  );
}

export function CacheRoute() {
  const navigate = useNavigate();
  const [tab, setTab] = useState(0);
  const [snapshot, setSnapshot] = useState<DownloadSnapshot>(emptySnapshot);
  const [torrentValue, setTorrentValue] = useState("");
  const [formError, setFormError] = useState<string | null>(() =>
    window.melonbang?.download ? null : "下载桥接不可用，请重启应用。"
  );
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    const bridge = window.melonbang?.download;
    if (!bridge) {
      return;
    }

    let cancelled = false;
    const unsubscribe = bridge.onUpdate((nextSnapshot) => {
      setSnapshot(nextSnapshot);
    });

    void bridge
      .list()
      .then((nextSnapshot) => {
        if (!cancelled) {
          setSnapshot(nextSnapshot);
        }
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setFormError(toMessage(error));
        }
      });

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, []);

  const activeTasks = useMemo(
    () => snapshot.tasks.filter((task) => isActiveStatus(task.status)),
    [snapshot.tasks]
  );
  const queuedTasks = useMemo(
    () => snapshot.tasks.filter((task) => isQueuedStatus(task.status)),
    [snapshot.tasks]
  );
  const completedTasks = useMemo(
    () => snapshot.tasks.filter((task) => task.status === "completed"),
    [snapshot.tasks]
  );
  const cacheTabs = useMemo(
    () => [
      { label: "正在下载", count: activeTasks.length ? String(activeTasks.length) : "" },
      { label: "排队中", count: queuedTasks.length ? String(queuedTasks.length) : "" },
      { label: "已完成", count: completedTasks.length ? String(completedTasks.length) : "" },
      { label: "全部", count: "" }
    ],
    [activeTasks.length, completedTasks.length, queuedTasks.length]
  );
  const storage = useMemo(() => getStorageSummary(snapshot.tasks), [snapshot.tasks]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    const value = torrentValue.trim();
    if (!value) {
      return;
    }

    const bridge = window.melonbang?.download;
    if (!bridge) {
      setFormError("下载桥接不可用，请重启应用。");
      return;
    }

    setSubmitting(true);
    setFormError(null);
    try {
      await bridge.create({ kind: "magnet", uri: value });
      setTorrentValue("");
      setSnapshot(await bridge.list());
    } catch (error) {
      setFormError(toMessage(error));
    } finally {
      setSubmitting(false);
    }
  }

  async function pauseTask(downloadId: string): Promise<void> {
    await runDownloadAction((bridge) => bridge.pause(downloadId), setSnapshot, setFormError);
  }

  async function resumeTask(downloadId: string): Promise<void> {
    await runDownloadAction((bridge) => bridge.resume(downloadId), setSnapshot, setFormError);
  }

  async function removeTask(downloadId: string): Promise<void> {
    await runDownloadAction((bridge) => bridge.remove(downloadId), setSnapshot, setFormError);
  }

  async function pauseAll(): Promise<void> {
    await runDownloadAction(
      async (bridge) => {
        for (const task of activeTasks) {
          await bridge.pause(task.id);
        }
      },
      setSnapshot,
      setFormError
    );
  }

  async function clearCompleted(): Promise<void> {
    await runDownloadAction(
      async (bridge) => {
        for (const task of completedTasks) {
          await bridge.remove(task.id);
        }
      },
      setSnapshot,
      setFormError
    );
  }

  async function playCompletedTask(task: DownloadTaskView): Promise<void> {
    const bridge = window.melonbang?.playback;
    if (!bridge) {
      setFormError("播放桥接不可用，请重启应用。");
      return;
    }

    setFormError(null);
    try {
      if (task.subjectId !== null && task.episodeId !== null) {
        await bridge.startEpisode({
          subjectId: task.subjectId,
          episodeId: task.episodeId
        });
      } else {
        await bridge.startFromDownload({ downloadId: task.id });
      }
      void navigate("/player");
    } catch (error) {
      setFormError(toMessage(error));
    }
  }

  return (
    <>
      <Topbar title="缓存" subtitle="下载与本地缓存">
        <Button variant="outline" size="sm" onClick={() => void pauseAll()}>
          <Pause className="size-4" />
          全部暂停
        </Button>
        <Button variant="outline" size="sm" onClick={() => void clearCompleted()}>
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
              background: `conic-gradient(var(--mint-400) 0 ${storage.pct}%, var(--surface-3) ${storage.pct}% 100%)`
            }}
          >
            <div className="bg-surface text-mint-600 grid size-[42px] place-items-center rounded-full text-[13px] font-extrabold">
              {storage.pct}%
            </div>
          </div>
          <div className="flex-1">
            <div className="flex items-center">
              <b className="text-[15px]">本地缓存</b>
              <div className="flex-1" />
              <span className="text-ink-faint text-xs">
                已用 {storage.used} / {storage.total}
              </span>
            </div>
            <div className="bg-surface-3 mt-2 h-1.5 overflow-hidden rounded-full">
              <div
                className="h-full rounded-full bg-[linear-gradient(90deg,var(--mint-400),var(--mint-300))]"
                style={{ width: `${storage.pct}%` }}
              />
            </div>
            <div className="text-ink-faint mt-2 flex flex-wrap items-center gap-3.5 text-[11.5px] font-semibold">
              <span>
                <span className="text-mint-600">↓ {storage.speed} MB/s</span> 当前总速度
              </span>
              <span>
                {activeTasks.length} 个任务下载中 · {queuedTasks.length} 个排队
              </span>
            </div>
          </div>
        </Card>

        <form onSubmit={(event) => void handleSubmit(event)}>
          <Card className="mt-4 flex flex-wrap items-center gap-3 p-[14px_16px]">
            <Input
              value={torrentValue}
              onChange={(event) => setTorrentValue(event.target.value)}
              placeholder="粘贴 magnet:?xt=urn:btih:..."
              className="min-w-[280px] flex-1"
            />
            <Button type="submit" size="sm" disabled={submitting}>
              <ArrowDownToLine className="size-4" />
              下载
            </Button>
            {formError ? (
              <span className="text-cherry-500 text-[12px] font-bold">{formError}</span>
            ) : null}
          </Card>
        </form>

        <div className="border-line bg-surface mt-5 inline-flex gap-1 rounded-full border p-1.5 shadow-[var(--shadow-sm)]">
          {cacheTabs.map((entry, i) => {
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
            {activeTasks.length ? (
              activeTasks.map((task, i) => (
                <DownloadRow
                  key={task.id}
                  task={task}
                  imageUrl={task.previewImageUrl ?? undefined}
                  first={i === 0}
                  onPause={(downloadId) => void pauseTask(downloadId)}
                  onRemove={(downloadId) => void removeTask(downloadId)}
                />
              ))
            ) : (
              <EmptyRow>暂无下载任务</EmptyRow>
            )}
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
            {queuedTasks.length ? (
              queuedTasks.map((task, i) => (
                <QueueRow
                  key={task.id}
                  task={task}
                  imageUrl={task.previewImageUrl ?? undefined}
                  first={i === 0}
                  onResume={(downloadId) => void resumeTask(downloadId)}
                  onRemove={(downloadId) => void removeTask(downloadId)}
                />
              ))
            ) : (
              <EmptyRow>暂无排队任务</EmptyRow>
            )}
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
          {completedTasks.length ? (
            <div className="grid [grid-template-columns:repeat(auto-fill,minmax(188px,1fr))] gap-4">
              {completedTasks.map((item) => (
                <CompletedDownloadCard
                  key={item.id}
                  item={item}
                  onPlay={(task) => void playCompletedTask(task)}
                />
              ))}
            </div>
          ) : (
            <Card className="overflow-hidden">
              <EmptyRow>暂无已完成缓存</EmptyRow>
            </Card>
          )}
        </Section>
      </PageContent>
    </>
  );
}

async function runDownloadAction(
  action: (bridge: Window["melonbang"]["download"]) => Promise<unknown>,
  setSnapshot: (snapshot: DownloadSnapshot) => void,
  setFormError: (message: string | null) => void
): Promise<void> {
  const bridge = window.melonbang?.download;
  if (!bridge) {
    setFormError("下载桥接不可用，请重启应用。");
    return;
  }

  setFormError(null);
  try {
    await action(bridge);
    setSnapshot(await bridge.list());
  } catch (error) {
    setFormError(toMessage(error));
  }
}

function isActiveStatus(status: DownloadStatus): boolean {
  return status === "metadata" || status === "downloading" || status === "ready";
}

function isQueuedStatus(status: DownloadStatus): boolean {
  return status === "queued" || status === "paused" || status === "failed";
}

function getStorageSummary(tasks: DownloadTaskView[]): {
  pct: number;
  used: string;
  total: string;
  speed: string;
} {
  const downloadedBytes = tasks.reduce((sum, task) => sum + task.downloadedBytes, 0);
  const knownTotalBytes = tasks.reduce((sum, task) => sum + (task.totalBytes ?? 0), 0);
  const downloadSpeedBytesPerSecond = tasks.reduce(
    (sum, task) => sum + task.downloadSpeedBytesPerSecond,
    0
  );
  const pct =
    knownTotalBytes > 0 ? Math.min(100, Math.round((downloadedBytes / knownTotalBytes) * 100)) : 0;

  return {
    pct,
    used: formatBytes(downloadedBytes),
    total: knownTotalBytes > 0 ? formatBytes(knownTotalBytes) : "--",
    speed: formatMegabytesPerSecond(downloadSpeedBytesPerSecond)
  };
}

function statusLabel(status: DownloadStatus): string {
  const labels: Record<DownloadStatus, string> = {
    queued: "排队中",
    metadata: "解析中",
    downloading: "下载中",
    paused: "已暂停",
    ready: "可播放",
    completed: "已完成",
    failed: "失败",
    removed: "已移除"
  };
  return labels[status];
}

function formatTaskTitle(task: DownloadTaskView): string {
  const quality = inferQuality(task.title);
  return `${task.title} [${quality}]`;
}

function inferQuality(title: string): string {
  const match = /(2160|1440|1080|720|480)P?/i.exec(title);
  return match ? `${match[1]}P` : "本地";
}

function progressPercent(task: DownloadTaskView): number {
  return Math.min(100, Math.max(0, Math.round(task.progress * 100)));
}

function formatBytes(value: number | null): string {
  if (!value || value <= 0) {
    return "0 MB";
  }

  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = value;
  let unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }

  return `${size >= 10 || unitIndex < 2 ? size.toFixed(0) : size.toFixed(1)} ${units[unitIndex]}`;
}

function formatMegabytesPerSecond(value: number): string {
  return (value / 1024 / 1024).toFixed(value >= 10 * 1024 * 1024 ? 0 : 1);
}

function formatEta(value: number | null): string {
  if (!value || value <= 0) {
    return "未知";
  }

  if (value < 60) {
    return `${value}秒`;
  }

  const minutes = Math.floor(value / 60);
  const seconds = value % 60;
  if (minutes < 60) {
    return `${minutes}分${seconds}秒`;
  }

  const hours = Math.floor(minutes / 60);
  return `${hours}小时${minutes % 60}分`;
}

function coverMark(title: string): string {
  return title.trim().charAt(0).toUpperCase() || "下";
}

function coverIndex(id: string): number {
  let hash = 0;
  for (const char of id) {
    hash = (hash + char.charCodeAt(0)) % 12;
  }

  return hash;
}

function toMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message || "下载请求失败。";
  }

  return "下载请求失败。";
}
