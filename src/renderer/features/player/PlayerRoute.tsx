import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import {
  ChevronLeft,
  ChevronRight,
  Link2,
  LoaderCircle,
  PanelRightClose,
  PanelRightOpen
} from "lucide-react";
import type { EpisodeCollectionState, SubjectDetail } from "@shared/contracts/bangumi";
import type { DownloadSnapshot, DownloadTaskView } from "@shared/contracts/download";
import type {
  DanmakuSourceId,
  DanmakuSourceView,
  MediaBindingView,
  PlaybackDeliveryMode,
  PlaybackSessionView,
  SubtitleTrackView
} from "@shared/contracts/playback";
import { WindowFrame } from "@/app/shell/WindowFrame";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";
import { createAssSubtitleRenderer, type AssSubtitleRendererHandle } from "./assSubtitleRenderer";
import { createArtPlayerController, type ArtPlayerController } from "./artPlayerController";
import {
  createRemoteSeekCoordinator,
  type RemoteSeekCoordinator
} from "./remoteSeekCoordinator";
import {
  bilibiliDanmakuDefaults,
  bilibiliDanmakuFontOptions,
  bilibiliDanmakuSpeedOptions,
  resolveBilibiliDanmakuPresentation,
  type BilibiliDanmakuArea,
  type BilibiliDanmakuBorder,
  type BilibiliDanmakuDensity,
  type BilibiliDanmakuFont,
  type BilibiliDanmakuSpeed
} from "./bilibiliDanmakuPresentation";
import { DanmakuSearchDialog } from "./DanmakuSearchDialog";
import { DirectDanmakuSourceDialog } from "./DirectDanmakuSourceDialog";
import { EpisodeBindingDialog } from "./EpisodeBindingDialog";
import { filterDanmakuItems, toArtPlayerDanmuku, toArtPlayerDanmakuMode } from "./danmaku";
import {
  resolvePlaybackDuration,
  resolveSeekAction,
  toLocalTime,
  toSourceTime
} from "@shared/playerTiming";

type RightPanel = "episodes" | "danmaku" | "settings";
type SendMode = "scroll" | "top" | "bottom";
type EpisodeMediaState = "current" | "cached" | "downloading" | "missing";

type PlayerEpisodeItem = {
  episode: EpisodeCollectionState;
  mediaState: EpisodeMediaState;
};

const colorChoices = ["#fff", "#ffd56b", "#ff9eb5", "#86c5ff", "#9be7c4", "#c8a8f0"];
const emptySubtitleTracks: SubtitleTrackView[] = [];
const emptyDownloadSnapshot: DownloadSnapshot = { tasks: [], files: [] };
const sourceSubtitleCueTimes = new WeakMap<TextTrackCue, { startTime: number; endTime: number }>();
const sourceSubtitleTrackIds = new WeakMap<TextTrack, string>();

function EpisodeItem({
  item,
  switching,
  onSelect
}: {
  item: PlayerEpisodeItem;
  switching: boolean;
  onSelect: () => void;
}) {
  const { episode, mediaState } = item;
  const current = mediaState === "current";
  const watched = episode.status === "watched";
  const cached = mediaState === "cached";
  const downloading = mediaState === "downloading";

  return (
    <button
      type="button"
      disabled={switching}
      onClick={onSelect}
      className={cn(
        "flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition",
        current && "outline-mint-200 bg-mint-50 dark:bg-mint-400/15 outline outline-1",
        !current && "hover:bg-surface-2",
        switching && "opacity-70"
      )}
    >
      <span
        className={cn(
          "bg-surface-3 text-ink-soft grid size-[30px] flex-none place-items-center rounded-[9px] text-[13px] font-extrabold",
          current && "bg-mint-400 text-on-accent",
          (watched || cached) && !current && "bg-mint-100 text-mint-600"
        )}
      >
        {episode.sort}
      </span>
      <span className="min-w-0 flex-1">
        <b className="block truncate text-[13px]">
          第{episode.sort}话 · {episode.nameCn ?? episode.name}
        </b>
        <span className="text-ink-faint text-[11px]">
          {current
            ? "正在播放"
            : cached
              ? "已缓存 · 点击切换"
              : downloading
                ? "缓存中 · 点击查看任务"
                : "未缓存 · 点击搜索下载"}
        </span>
      </span>
      {switching ? (
        <LoaderCircle className="text-mint-500 size-4 animate-spin" />
      ) : current ? (
        <Badge variant="mint" className="text-[10px]">
          播放中
        </Badge>
      ) : cached ? (
        <Badge variant="outline" className="text-[10px]">
          已缓存
        </Badge>
      ) : downloading ? (
        <Badge variant="outline" className="text-[10px]">
          缓存中
        </Badge>
      ) : watched ? (
        <span className="text-ink-faint text-[11px]">已看</span>
      ) : (
        <span className="text-mint-600 text-[11px] font-bold">下载</span>
      )}
    </button>
  );
}

function SettingRow({
  title,
  description,
  children
}: {
  title: string;
  description?: string;
  children: ReactNode;
}) {
  return (
    <div className="border-line flex items-center gap-3 py-[11px] [&:not(:first-child)]:border-t">
      <div className="flex-1">
        <div className="text-[13px] font-semibold">{title}</div>
        {description ? (
          <div className="text-ink-faint text-[11px] font-medium">{description}</div>
        ) : null}
      </div>
      {children}
    </div>
  );
}

function DanmakuSourceRow({
  source,
  onSelect,
  onEnabledChange
}: {
  source: DanmakuSourceView;
  onSelect: () => void;
  onEnabledChange: (enabled: boolean) => void;
}) {
  const status = source.enabled
    ? source.status === "loading"
      ? "正在自动匹配…"
      : source.status === "ready"
        ? `${source.matchLabel ?? "已匹配"} · ${source.count} 条`
        : source.status === "error"
          ? "自动匹配失败 · 点击手动选择"
          : "等待自动匹配"
    : `已关闭${source.count > 0 ? ` · 已缓存 ${source.count} 条` : ""}`;

  return (
    <div className="border-line bg-surface-1 flex min-h-[68px] w-full items-stretch overflow-hidden rounded-2xl border">
      <button
        type="button"
        onClick={onSelect}
        className="hover:bg-surface-2 flex min-w-0 flex-1 items-center gap-3 px-4 py-3 text-left transition"
      >
        <span className="min-w-0 flex-1">
          <b className="block truncate text-[13px]">{source.label}</b>
          <span className="text-ink-faint mt-0.5 block truncate text-[11px] font-semibold">
            {status}
          </span>
        </span>
        <ChevronRight className="text-ink-faint size-4 flex-none" />
      </button>
      <div className="border-line flex flex-none items-center border-l px-3">
        <Switch
          checked={source.enabled}
          onCheckedChange={onEnabledChange}
          aria-label={`${source.enabled ? "关闭" : "开启"}${source.label}弹幕`}
        />
      </div>
    </div>
  );
}

function Segmented<T extends string>({
  options,
  value,
  onChange
}: {
  options: Array<{ value: T; label: string }>;
  value: T;
  onChange: (value: T) => void;
}) {
  return (
    <div className="border-line bg-surface-2 inline-flex rounded-full border p-[3px]">
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          onClick={() => onChange(option.value)}
          className={cn(
            "rounded-full px-2.5 py-1 text-[11.5px] font-bold transition",
            option.value === value ? "bg-mint-400 text-on-accent" : "text-ink-soft hover:text-ink"
          )}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

function RangeSetting({
  label,
  min,
  max,
  step = 1,
  value,
  valueLabel,
  onChange
}: {
  label: string;
  min: number;
  max: number;
  step?: number;
  value: number;
  valueLabel: string;
  onChange: (value: number) => void;
}) {
  return (
    <div className="flex items-center gap-2">
      <input
        aria-label={label}
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
        className="w-[92px]"
      />
      <output className="text-ink-soft w-[38px] text-right text-[11px] font-bold tabular-nums">
        {valueLabel}
      </output>
    </div>
  );
}

export function PlayerRoute() {
  const navigate = useNavigate();
  const artContainerRef = useRef<HTMLDivElement | null>(null);
  const controllerRef = useRef<ArtPlayerController | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const sessionRef = useRef<PlaybackSessionView | null>(null);
  const timelineOffsetRef = useRef(0);
  const subtitleTracksRef = useRef<SubtitleTrackView[]>([]);
  const nativeTracksRef = useRef<SubtitleTrackView[]>([]);
  const activeSubtitleIdRef = useRef("off");
  const remoteSeekCoordinatorRef = useRef<RemoteSeekCoordinator | null>(null);
  const lastProgressReportRef = useRef(0);
  const shouldPlayRef = useRef(true);
  const requestedDanmakuSessionIdsRef = useRef(new Set<string>());
  const [session, setSession] = useState<PlaybackSessionView | null>(null);
  const [playbackError, setPlaybackError] = useState<string | null>(null);
  const [subtitleError, setSubtitleError] = useState<string | null>(null);
  const [danmakuError, setDanmakuError] = useState<string | null>(null);
  const [activeDanmakuDialog, setActiveDanmakuDialog] = useState<DanmakuSourceId | null>(null);
  const [episodeBindingDialogOpen, setEpisodeBindingDialogOpen] = useState(false);
  const [panel, setPanel] = useState<RightPanel>("episodes");
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [subject, setSubject] = useState<SubjectDetail | null>(null);
  const [mediaBindings, setMediaBindings] = useState<MediaBindingView[]>([]);
  const [downloadSnapshot, setDownloadSnapshot] = useState<DownloadSnapshot>(emptyDownloadSnapshot);
  const [episodePanelError, setEpisodePanelError] = useState<string | null>(null);
  const [switchingEpisodeId, setSwitchingEpisodeId] = useState<number | null>(null);
  const [showDanmaku, setShowDanmaku] = useState(true);
  const [danmakuArea, setDanmakuArea] = useState<BilibiliDanmakuArea>(bilibiliDanmakuDefaults.area);
  const [sendMode, setSendMode] = useState<SendMode>("scroll");
  const [selectedColor, setSelectedColor] = useState(colorChoices[0]);
  const [blockedTypes, setBlockedTypes] = useState(new Set<string>());
  const [selectedSubtitleId, setSelectedSubtitleId] = useState("auto");
  const [danmakuOpacity, setDanmakuOpacity] = useState(bilibiliDanmakuDefaults.opacityPercent);
  const [danmakuFontScale, setDanmakuFontScale] = useState(
    bilibiliDanmakuDefaults.fontScalePercent
  );
  const [danmakuSpeed, setDanmakuSpeed] = useState<BilibiliDanmakuSpeed>(
    bilibiliDanmakuDefaults.speed
  );
  const [danmakuDensity, setDanmakuDensity] = useState<BilibiliDanmakuDensity>(
    bilibiliDanmakuDefaults.density
  );
  const [danmakuFont, setDanmakuFont] = useState<BilibiliDanmakuFont>(bilibiliDanmakuDefaults.font);
  const [danmakuBold, setDanmakuBold] = useState(bilibiliDanmakuDefaults.bold);
  const [danmakuBorder, setDanmakuBorder] = useState<BilibiliDanmakuBorder>(
    bilibiliDanmakuDefaults.border
  );
  const [danmakuScaleWithPlayer, setDanmakuScaleWithPlayer] = useState(
    bilibiliDanmakuDefaults.scaleWithPlayer
  );
  const [danmakuSpeedSync, setDanmakuSpeedSync] = useState(bilibiliDanmakuDefaults.speedSync);
  const applySession = useCallback((nextSession: PlaybackSessionView | null): void => {
    if (
      nextSession &&
      remoteSeekCoordinatorRef.current &&
      !remoteSeekCoordinatorRef.current.shouldAcceptSession(nextSession)
    ) {
      return;
    }
    sessionRef.current = nextSession;
    setSession(nextSession);
  }, []);
  const danmakuPresentation = useMemo(
    () =>
      resolveBilibiliDanmakuPresentation({
        opacityPercent: danmakuOpacity,
        area: danmakuArea,
        fontScalePercent: danmakuFontScale,
        speed: danmakuSpeed,
        density: danmakuDensity,
        font: danmakuFont,
        bold: danmakuBold,
        border: danmakuBorder,
        scaleWithPlayer: danmakuScaleWithPlayer,
        speedSync: danmakuSpeedSync
      }),
    [
      danmakuArea,
      danmakuBold,
      danmakuBorder,
      danmakuDensity,
      danmakuFont,
      danmakuFontScale,
      danmakuOpacity,
      danmakuScaleWithPlayer,
      danmakuSpeed,
      danmakuSpeedSync
    ]
  );
  const source = session?.source ?? null;
  const sourceUrl = source?.url;
  const sourceKind = source?.kind;
  const sourceDeliveryMode = source?.deliveryMode;
  const sourceMimeType = source?.mimeType;
  const sourceTitle = source?.title;
  const sourceDurationSeconds = session?.durationSeconds ?? null;
  const timelineOffsetSeconds = source?.timelineOffsetSeconds ?? 0;
  const sessionSubtitles = session?.subtitles ?? emptySubtitleTracks;
  const subtitleTracks = useMemo(
    () => playableSubtitleTracks(sessionSubtitles),
    [sessionSubtitles]
  );
  const nativeTracks = useMemo(
    () => subtitleTracks.filter((track) => track.renderMode === "native-vtt"),
    [subtitleTracks]
  );
  const activeSubtitleId = resolveSubtitleId(subtitleTracks, selectedSubtitleId);
  const activeAssTrack = subtitleTracks.find(
    (track) => track.id === activeSubtitleId && track.renderMode === "ass"
  );
  const activeAssUrl = activeAssTrack?.url ?? null;
  const activeAssFontKey = activeAssTrack?.fontUrls.join("\n") ?? "";
  const nativeTrackKey = nativeTracks
    .map((track) => `${track.id}:${track.url}:${track.default}`)
    .join("|");
  const danmakuKey = (session?.danmaku ?? [])
    .map(
      (item) =>
        `${item.sourceId ?? "unknown"}:${item.timeSeconds}:${item.mode}:${item.color}:${item.text}`
    )
    .join("|");
  const blockedTypesKey = [...blockedTypes].sort().join("|");
  const danmakuSources = session?.danmakuSources ?? [];
  const currentEpisode = useMemo(
    () => subject?.episodes.find((episode) => episode.episodeId === session?.episodeId) ?? null,
    [session?.episodeId, subject?.episodes]
  );
  const episodeItems = useMemo<PlayerEpisodeItem[]>(() => {
    if (!subject || session?.subjectId !== subject.subjectId) {
      return [];
    }

    const bindingsByEpisode = new Map(
      mediaBindings.map((binding) => [binding.episodeId, binding] as const)
    );
    const downloadsByEpisode = new Map<number, DownloadTaskView>();
    for (const task of downloadSnapshot.tasks) {
      if (
        task.subjectId === subject.subjectId &&
        task.episodeId !== null &&
        !downloadsByEpisode.has(task.episodeId)
      ) {
        downloadsByEpisode.set(task.episodeId, task);
      }
    }

    return subject.episodes.map((episode) => {
      if (episode.episodeId === session?.episodeId) {
        return { episode, mediaState: "current" };
      }
      if (bindingsByEpisode.get(episode.episodeId)?.available) {
        return { episode, mediaState: "cached" };
      }
      const download = downloadsByEpisode.get(episode.episodeId);
      if (download?.status === "completed" || download?.status === "ready") {
        return { episode, mediaState: "cached" };
      }
      if (download && download.status !== "failed" && download.status !== "removed") {
        return { episode, mediaState: "downloading" };
      }
      return { episode, mediaState: "missing" };
    });
  }, [downloadSnapshot.tasks, mediaBindings, session?.episodeId, session?.subjectId, subject]);
  useEffect(() => {
    sessionRef.current = session;
    timelineOffsetRef.current = timelineOffsetSeconds;
    subtitleTracksRef.current = subtitleTracks;
    nativeTracksRef.current = nativeTracks;
    activeSubtitleIdRef.current = activeSubtitleId;
  }, [activeSubtitleId, nativeTracks, session, subtitleTracks, timelineOffsetSeconds]);

  useEffect(() => {
    const bridge = window.melonbang?.playback;
    if (!bridge) return;

    const coordinator = createRemoteSeekCoordinator({
      seek: (input) => bridge.seek(input),
      onSession: applySession,
      onError(error) {
        setPlaybackError(error instanceof Error ? error.message : "无法从目标位置重新准备视频。");
      },
      onPlaybackIntent(shouldPlay) {
        shouldPlayRef.current = shouldPlay;
      }
    });
    remoteSeekCoordinatorRef.current = coordinator;

    return () => {
      coordinator.dispose();
      if (remoteSeekCoordinatorRef.current === coordinator) {
        remoteSeekCoordinatorRef.current = null;
      }
    };
  }, [applySession]);

  const reportVideoProgress = useCallback((video: HTMLVideoElement): void => {
    const currentSession = sessionRef.current;
    if (!currentSession) return;

    const now = Date.now();
    if (!video.ended && now - lastProgressReportRef.current < 1000) return;

    lastProgressReportRef.current = now;
    const bridge = window.melonbang?.playback;
    if (!bridge) return;

    const reportedSessionId = currentSession.id;
    const reportedSourceUrl = currentSession.source?.url ?? null;
    void bridge
      .updateProgress({
        sessionId: currentSession.id,
        positionSeconds: toSourceTime(
          finiteOrZero(video.currentTime),
          currentSession.source?.timelineOffsetSeconds ?? 0
        ),
        durationSeconds: resolvePlaybackDuration(currentSession.durationSeconds, video.duration),
        timelineOffsetSeconds: currentSession.source?.timelineOffsetSeconds ?? 0,
        paused: video.paused,
        ended: video.ended
      })
      .then((nextSession) => {
        const latestSession = sessionRef.current;
        if (
          latestSession?.id === reportedSessionId &&
          (latestSession.source?.url ?? null) === reportedSourceUrl
        ) {
          applySession(nextSession);
        }
      })
      .catch(() => undefined);
  }, [applySession]);

  const requestRemoteSeek = useCallback((positionSeconds: number, shouldPlay: boolean): void => {
    const currentSession = sessionRef.current;
    const coordinator = remoteSeekCoordinatorRef.current;
    if (!currentSession || !coordinator) return;

    setPlaybackError(null);
    void coordinator.request({
      sessionId: currentSession.id,
      positionSeconds,
      shouldPlay
    });
  }, []);

  const handleArtPlayerSeeking = useCallback(
    (video: HTMLVideoElement): void => {
      const currentSession = sessionRef.current;
      const currentSource = currentSession?.source;
      if (!currentSession || !currentSource || remoteSeekCoordinatorRef.current?.isSeeking()) {
        return;
      }

      const targetSeconds = toSourceTime(
        finiteOrZero(video.currentTime),
        currentSource.timelineOffsetSeconds
      );
      const action = resolveSeekAction({
        deliveryMode: currentSource.deliveryMode,
        targetSeconds,
        timelineOffsetSeconds: currentSource.timelineOffsetSeconds,
        seekableEndSeconds: getSeekableEndSeconds(video)
      });
      if (action.kind === "local") {
        reportVideoProgress(video);
        return;
      }

      requestRemoteSeek(action.sourceTimeSeconds, !video.paused);
    },
    [reportVideoProgress, requestRemoteSeek]
  );

  useEffect(() => {
    const bridge = window.melonbang?.playback;
    if (!bridge) {
      return;
    }

    let cancelled = false;
    const unsubscribe = bridge.onEvent((nextSession) => {
      if (
        !cancelled &&
        (!nextSession ||
          (remoteSeekCoordinatorRef.current?.shouldAcceptSession(nextSession) ?? true))
      ) {
        applySession(nextSession);
      }
    });

    void bridge
      .getSession()
      .then((nextSession) => {
        if (!cancelled) {
          applySession(nextSession);
        }
      })
      .catch(() => undefined);

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, [applySession]);

  useEffect(() => {
    const bridge = window.melonbang?.download;
    if (!bridge) {
      return;
    }

    let cancelled = false;
    const unsubscribe = bridge.onUpdate((snapshot) => {
      if (!cancelled) {
        setDownloadSnapshot(snapshot);
      }
    });
    void bridge
      .list()
      .then((snapshot) => {
        if (!cancelled) {
          setDownloadSnapshot(snapshot);
        }
      })
      .catch(() => undefined);

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, []);

  useEffect(() => {
    const subjectId = session?.subjectId;
    const playbackBridge = window.melonbang?.playback;
    const bangumiBridge = window.melonbang?.bangumi;
    if (!subjectId || !playbackBridge || !bangumiBridge) {
      setSubject(null);
      setMediaBindings([]);
      setEpisodePanelError(null);
      return;
    }

    let cancelled = false;
    let hasSubject = false;
    setSubject((current) => (current?.subjectId === subjectId ? current : null));
    setMediaBindings([]);
    setEpisodePanelError(null);

    void Promise.all([
      bangumiBridge.getCachedSubject(subjectId).catch(() => null),
      playbackBridge.listEpisodeMediaBindings(subjectId).catch(() => [])
    ]).then(([cachedSubject, bindings]) => {
      if (cancelled) return;
      setMediaBindings(bindings);
      if (cachedSubject) {
        hasSubject = true;
        setSubject(cachedSubject);
        setEpisodePanelError(null);
      }
    });

    void bangumiBridge
      .getSubject(subjectId)
      .then((freshSubject) => {
        if (cancelled) return;
        hasSubject = true;
        setSubject(freshSubject);
        setEpisodePanelError(null);
      })
      .catch((reason: unknown) => {
        if (!cancelled && !hasSubject) {
          setEpisodePanelError(toMessage(reason, "真实章节加载失败。"));
        }
      });

    return () => {
      cancelled = true;
    };
  }, [session?.subjectId]);

  useEffect(() => {
    const bridge = window.melonbang?.playback;
    const sessionId = session?.id;
    if (!bridge || !sessionId || !session.source) {
      return;
    }
    if (requestedDanmakuSessionIdsRef.current.has(sessionId)) {
      return;
    }

    requestedDanmakuSessionIdsRef.current.add(sessionId);
    setDanmakuError(null);
    void bridge
      .loadDanmaku(sessionId)
      .then((nextSession) => {
        if (sessionRef.current?.id !== sessionId) return;
        applySession(nextSession);
      })
      .catch((error: unknown) => {
        setDanmakuError(
          error instanceof Error ? error.message : "弹幕加载失败，视频播放不受影响。"
        );
      });
  }, [applySession, session?.id, session?.source]);

  useEffect(() => {
    const container = artContainerRef.current;
    if (
      !container ||
      !sourceUrl ||
      !sourceKind ||
      !sourceDeliveryMode ||
      sourceTitle === undefined
    ) {
      return;
    }

    let cancelled = false;
    lastProgressReportRef.current = 0;
    try {
      const controller = createArtPlayerController({
        container,
        source: {
          url: sourceUrl,
          kind: sourceKind,
          deliveryMode: sourceDeliveryMode,
          timelineOffsetSeconds,
          mimeType: sourceMimeType ?? null,
          title: sourceTitle
        },
        durationSeconds: sourceDurationSeconds,
        subtitles: subtitleTracksRef.current,
        selectedSubtitleId: activeSubtitleIdRef.current,
        volume: 0.64,
        playbackRate: 1,
        autoplay: shouldPlayRef.current,
        callbacks: {
          onPlay(video) {
            if (cancelled) return;
            shouldPlayRef.current = true;
            reportVideoProgress(video);
          },
          onPause(video) {
            if (cancelled) return;
            reportVideoProgress(video);
          },
          onLoadedMetadata(video) {
            if (cancelled) return;
            setPlaybackError(null);
            applySubtitleMode(video, activeSubtitleIdRef.current, timelineOffsetRef.current);
            reportVideoProgress(video);
          },
          onProgress(video) {
            if (cancelled) return;
            reportVideoProgress(video);
          },
          onSeeking(video) {
            if (cancelled) return;
            handleArtPlayerSeeking(video);
          },
          onSeekRequest(positionSeconds, shouldPlay) {
            if (cancelled) return;
            requestRemoteSeek(positionSeconds, shouldPlay);
          },
          onSubtitleSelect(subtitleId) {
            if (cancelled) return;
            setSelectedSubtitleId(subtitleId);
          },
          onDanmakuToggle() {
            if (cancelled) return;
            setShowDanmaku((visible) => !visible);
          },
          onError(video, error) {
            if (cancelled) return;
            const message = toPlaybackErrorMessage(video, error, sourceDeliveryMode);
            if (message) {
              setPlaybackError(message);
            }
          }
        }
      });
      controllerRef.current = controller;
      videoRef.current = controller.video;
    } catch (error) {
      queueMicrotask(() =>
        setPlaybackError(error instanceof Error ? error.message : "ArtPlayer 初始化失败。")
      );
    }

    return () => {
      cancelled = true;
      controllerRef.current?.destroy();
      controllerRef.current = null;
      videoRef.current = null;
    };
  }, [
    sourceDeliveryMode,
    sourceKind,
    sourceMimeType,
    sourceTitle,
    sourceUrl,
    sourceDurationSeconds,
    timelineOffsetSeconds,
    handleArtPlayerSeeking,
    reportVideoProgress,
    requestRemoteSeek
  ]);

  useEffect(() => {
    controllerRef.current?.updateSubtitles(subtitleTracksRef.current, activeSubtitleId);
  }, [activeSubtitleId, nativeTrackKey, sourceUrl]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    return syncNativeSubtitleTracks(video, nativeTracksRef.current, () =>
      applySubtitleMode(video, activeSubtitleIdRef.current, timelineOffsetRef.current)
    );
  }, [nativeTrackKey, sourceUrl]);

  useEffect(() => {
    applySubtitleMode(videoRef.current, activeSubtitleId, timelineOffsetSeconds);
  }, [activeSubtitleId, nativeTrackKey, timelineOffsetSeconds]);

  useEffect(() => {
    const controller = controllerRef.current;
    if (!controller) return;
    const blocked = new Set(blockedTypesKey ? blockedTypesKey.split("|") : []);
    const items = filterDanmakuItems(
      sessionRef.current?.danmaku ?? [],
      blocked,
      danmakuPresentation.densityThreshold
    );
    void controller
      .loadDanmaku(toArtPlayerDanmuku(items, timelineOffsetSeconds))
      .then(() => setDanmakuError(null))
      .catch(() => setDanmakuError("弹幕插件无法加载当前弹幕数据，视频播放不受影响。"));
  }, [
    blockedTypesKey,
    danmakuKey,
    danmakuPresentation.densityThreshold,
    sourceUrl,
    timelineOffsetSeconds
  ]);

  useEffect(() => {
    const controller = controllerRef.current;
    if (!controller) return;
    const modes = (["scroll", "top", "bottom"] as const)
      .filter((mode) => !blockedTypes.has(mode))
      .map(toArtPlayerDanmakuMode);
    controller.configureDanmaku({
      visible: showDanmaku,
      opacity: danmakuPresentation.opacity,
      fontFamily: danmakuPresentation.fontFamily,
      fontWeight: danmakuPresentation.fontWeight,
      fontSizeCss: danmakuPresentation.fontSizeCss,
      textShadow: danmakuPresentation.textShadow,
      speed: danmakuPresentation.speedSeconds,
      margin: danmakuPresentation.margin,
      antiOverlap: danmakuPresentation.antiOverlap,
      synchronousPlayback: danmakuPresentation.synchronousPlayback,
      modes,
      mode: toArtPlayerDanmakuMode(sendMode),
      color: selectedColor
    });
  }, [blockedTypes, danmakuPresentation, selectedColor, sendMode, showDanmaku, sourceUrl]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !activeAssUrl) {
      return;
    }

    let cancelled = false;
    let renderer: AssSubtitleRendererHandle | null = null;
    void createAssSubtitleRenderer({
      video,
      subtitleUrl: activeAssUrl,
      fontUrls: activeAssFontKey ? activeAssFontKey.split("\n") : [],
      timelineOffsetSeconds
    })
      .then((nextRenderer) => {
        if (cancelled) {
          void nextRenderer.destroy();
          return;
        }
        renderer = nextRenderer;
        setSubtitleError(null);
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setSubtitleError(error instanceof Error ? error.message : "ASS 字幕渲染初始化失败。");
        }
      });

    return () => {
      cancelled = true;
      if (renderer) {
        void renderer.destroy();
      }
    };
  }, [activeAssFontKey, activeAssUrl, sourceUrl, timelineOffsetSeconds]);

  function toggleBlocked(type: string): void {
    setBlockedTypes((current) => {
      const next = new Set(current);
      if (next.has(type)) {
        next.delete(type);
      } else {
        next.add(type);
      }
      return next;
    });
  }

  function resetDanmakuPresentation(): void {
    setShowDanmaku(true);
    setDanmakuOpacity(bilibiliDanmakuDefaults.opacityPercent);
    setDanmakuArea(bilibiliDanmakuDefaults.area);
    setDanmakuFontScale(bilibiliDanmakuDefaults.fontScalePercent);
    setDanmakuSpeed(bilibiliDanmakuDefaults.speed);
    setDanmakuDensity(bilibiliDanmakuDefaults.density);
    setDanmakuFont(bilibiliDanmakuDefaults.font);
    setDanmakuBold(bilibiliDanmakuDefaults.bold);
    setDanmakuBorder(bilibiliDanmakuDefaults.border);
    setDanmakuScaleWithPlayer(bilibiliDanmakuDefaults.scaleWithPlayer);
    setDanmakuSpeedSync(bilibiliDanmakuDefaults.speedSync);
    setBlockedTypes(new Set());
  }

  function setSidebarVisibility(open: boolean): void {
    setSidebarOpen(open);
    requestAnimationFrame(() => controllerRef.current?.art.emit("resize"));
  }

  async function selectEpisode(item: PlayerEpisodeItem): Promise<void> {
    const { episode, mediaState } = item;
    if (mediaState === "current") {
      return;
    }
    if (mediaState === "downloading") {
      void navigate("/cache");
      return;
    }
    if (mediaState === "missing") {
      void navigate(`/subject/${episode.subjectId}/cache?episodeId=${episode.episodeId}`);
      return;
    }

    const bridge = window.melonbang?.playback;
    if (!bridge) {
      setEpisodePanelError("播放桥接不可用，请重启应用。");
      return;
    }

    setSwitchingEpisodeId(episode.episodeId);
    setEpisodePanelError(null);
    shouldPlayRef.current = true;
    try {
      applySession(
        await bridge.startEpisode({
          subjectId: episode.subjectId,
          episodeId: episode.episodeId
        })
      );
    } catch (reason) {
      setEpisodePanelError(toMessage(reason, "章节切换失败。"));
    } finally {
      setSwitchingEpisodeId(null);
    }
  }

  const displayedTitle = subject?.nameCn ?? subject?.name ?? session?.title ?? "暂无播放";
  const displayedEpisode = currentEpisode
    ? `EP${currentEpisode.sort}「${currentEpisode.nameCn ?? currentEpisode.name}」`
    : session
      ? "未关联章节"
      : "暂无播放会话";

  return (
    <WindowFrame crumb="正在播放">
      <div
        className={cn(
          "grid h-full min-h-0",
          sidebarOpen ? "grid-cols-[1fr_344px] max-[1080px]:grid-cols-1" : "grid-cols-1"
        )}
      >
        <section className="min-w-0 bg-[var(--player-bg)]">
          <div className="relative h-full min-h-0 overflow-hidden bg-[radial-gradient(120%_100%_at_70%_20%,rgba(22,64,74,.6),var(--player-bg)_70%)]">
            <div
              className={cn(
                "absolute inset-0 bg-[linear-gradient(135deg,var(--mint-600),var(--sky-500))] opacity-[.18]",
                source && "opacity-0"
              )}
            />

            {source ? (
              <div
                ref={artContainerRef}
                className="melon-artplayer absolute inset-0 z-[1] bg-black"
              />
            ) : null}

            <div className="absolute top-0 right-0 left-0 z-10 flex items-center gap-3 bg-[linear-gradient(180deg,rgba(0,0,0,.4),transparent)] px-[18px] py-4 text-white">
              <button
                type="button"
                onClick={() => void navigate(-1)}
                className="grid size-9 place-items-center rounded-xl bg-white/[0.18] text-white transition hover:bg-white/[0.25]"
                aria-label="返回"
              >
                <ChevronLeft className="size-[18px]" />
              </button>
              <div className="text-sm font-bold">
                {displayedTitle} · {displayedEpisode}
              </div>
              <div className="flex-1" />
              <button
                type="button"
                onClick={() => setSidebarVisibility(!sidebarOpen)}
                className="grid size-9 place-items-center rounded-xl bg-white/[0.18] text-white transition hover:bg-white/[0.25]"
                aria-label={sidebarOpen ? "关闭侧边栏" : "打开侧边栏"}
                title={sidebarOpen ? "关闭侧边栏" : "打开侧边栏"}
              >
                {sidebarOpen ? (
                  <PanelRightClose className="size-[18px]" />
                ) : (
                  <PanelRightOpen className="size-[18px]" />
                )}
              </button>
            </div>

            {playbackError || subtitleError ? (
              <div className="absolute right-6 bottom-20 left-6 z-20 rounded-xl border border-white/[0.18] bg-black/70 px-4 py-3 text-white shadow-[0_16px_36px_rgba(0,0,0,.35)] backdrop-blur-md">
                <div className="text-sm font-extrabold">
                  {subtitleError
                    ? "字幕加载失败"
                    : source?.deliveryMode === "remux"
                      ? "重封装播放失败"
                      : source?.kind === "hls"
                        ? "转码播放失败"
                        : "当前文件无法直接播放"}
                </div>
                <div className="mt-1 text-[12px] leading-5 text-white/75">
                  {subtitleError ?? playbackError}
                </div>
              </div>
            ) : null}
          </div>
        </section>

        <aside
          className={cn(
            "border-line bg-surface flex min-h-0 flex-col border-l max-[1080px]:hidden",
            !sidebarOpen && "hidden"
          )}
        >
          <div className="border-line border-b px-3.5 py-3">
            <div className="border-line bg-surface inline-flex w-full gap-1 rounded-full border p-1.5 shadow-none">
              <button
                type="button"
                onClick={() => setPanel("episodes")}
                className={cn(
                  "flex flex-1 justify-center rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                  panel === "episodes"
                    ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_5px_12px_rgba(34,179,136,.28)]"
                    : "text-ink-soft hover:text-ink"
                )}
              >
                选集
              </button>
              <button
                type="button"
                onClick={() => setPanel("danmaku")}
                className={cn(
                  "flex flex-1 justify-center rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                  panel === "danmaku"
                    ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_5px_12px_rgba(34,179,136,.28)]"
                    : "text-ink-soft hover:text-ink"
                )}
              >
                弹幕
              </button>
              <button
                type="button"
                onClick={() => setPanel("settings")}
                className={cn(
                  "flex flex-1 justify-center rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                  panel === "settings"
                    ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_5px_12px_rgba(34,179,136,.28)]"
                    : "text-ink-soft hover:text-ink"
                )}
              >
                设置
              </button>
            </div>
          </div>

          <div className="min-h-0 flex-1 overflow-auto px-3.5 py-3">
            {panel === "episodes" ? (
              <div className="flex flex-col gap-1">
                {episodeItems.length > 0 ? (
                  episodeItems.map((item) => (
                    <EpisodeItem
                      key={item.episode.episodeId}
                      item={item}
                      switching={switchingEpisodeId === item.episode.episodeId}
                      onSelect={() => void selectEpisode(item)}
                    />
                  ))
                ) : session?.subjectId && !subject && !episodePanelError ? (
                  <div className="border-line bg-surface-2 text-ink-faint rounded-[16px] border px-4 py-8 text-center text-sm font-semibold">
                    正在加载真实章节…
                  </div>
                ) : subject ? (
                  <div className="border-line bg-surface-2 text-ink-faint rounded-[16px] border px-4 py-8 text-center text-sm font-semibold">
                    当前条目没有可显示的正片章节。
                  </div>
                ) : session ? (
                  <div className="border-line bg-surface-2 flex flex-col items-center gap-3 rounded-[16px] border px-4 py-8 text-center">
                    <div>
                      <div className="text-sm font-extrabold">当前视频未关联章节</div>
                      <p className="text-ink-faint mt-1 text-[11.5px] leading-5 font-semibold">
                        外部下载或手动导入的视频不会自动猜测章节。
                      </p>
                    </div>
                    <Button size="sm" onClick={() => setEpisodeBindingDialogOpen(true)}>
                      <Link2 data-icon="inline-start" />
                      搜索并关联
                    </Button>
                  </div>
                ) : (
                  <div className="border-line bg-surface-2 text-ink-faint rounded-[16px] border px-4 py-8 text-center text-sm font-semibold">
                    当前没有播放会话。
                  </div>
                )}
                {episodePanelError ? (
                  <p className="text-cherry-500 px-1 pt-2 text-[11.5px] leading-5 font-bold">
                    {episodePanelError}
                  </p>
                ) : null}
              </div>
            ) : panel === "danmaku" ? (
              <div>
                <div className="mb-3 flex flex-col gap-1">
                  <div className="text-ink-faint text-xs font-bold">弹幕源</div>
                  <p className="text-ink-faint text-[11px] font-medium">
                    点击来源可手动匹配，右侧开关控制是否合并显示
                  </p>
                </div>
                <div className="flex flex-col gap-2">
                  {danmakuSources.map((sourceView) => (
                    <DanmakuSourceRow
                      key={sourceView.id}
                      source={sourceView}
                      onSelect={() => setActiveDanmakuDialog(sourceView.id)}
                      onEnabledChange={(enabled) => {
                        const bridge = window.melonbang?.playback;
                        const sessionId = sessionRef.current?.id;
                        if (!bridge || !sessionId) return;
                        setDanmakuError(null);
                        void bridge
                          .setDanmakuSourceEnabled({
                            sessionId,
                            providerId: sourceView.id,
                            enabled
                          })
                          .then(applySession)
                          .catch((reason: unknown) =>
                            setDanmakuError(toMessage(reason, "无法更新弹幕源开关。"))
                          );
                      }}
                    />
                  ))}
                </div>
                {danmakuError ? (
                  <p className="text-cherry-500 mt-2 text-[11px] leading-5 font-bold">
                    {danmakuError}
                  </p>
                ) : null}

                <Separator className="bg-line my-[18px]" />
                <div className="mb-2 flex items-center justify-between">
                  <div className="text-ink-faint text-xs font-bold">弹幕设置</div>
                  <button
                    type="button"
                    onClick={resetDanmakuPresentation}
                    className="text-ink-faint hover:text-mint-600 text-[11px] font-bold transition"
                  >
                    恢复默认
                  </button>
                </div>
                <SettingRow title="显示弹幕" description="关闭后将隐藏所有弹幕">
                  <Switch checked={showDanmaku} onCheckedChange={setShowDanmaku} />
                </SettingRow>
                <SettingRow title="弹幕透明度">
                  <RangeSetting
                    label="弹幕透明度"
                    min={10}
                    max={100}
                    value={danmakuOpacity}
                    valueLabel={`${danmakuOpacity}%`}
                    onChange={setDanmakuOpacity}
                  />
                </SettingRow>
                <SettingRow title="显示区域">
                  <Segmented<BilibiliDanmakuArea>
                    value={danmakuArea}
                    onChange={setDanmakuArea}
                    options={[
                      { value: "quarter", label: "1/4" },
                      { value: "half", label: "半屏" },
                      { value: "threeQuarter", label: "3/4" },
                      { value: "full", label: "全屏" }
                    ]}
                  />
                </SettingRow>
                <SettingRow title="弹幕字号">
                  <RangeSetting
                    label="弹幕字号"
                    min={50}
                    max={150}
                    step={5}
                    value={danmakuFontScale}
                    valueLabel={`${danmakuFontScale}%`}
                    onChange={setDanmakuFontScale}
                  />
                </SettingRow>
                <SettingRow title="弹幕速度">
                  <RangeSetting
                    label="弹幕速度"
                    min={0}
                    max={bilibiliDanmakuSpeedOptions.length - 1}
                    value={Math.max(
                      0,
                      bilibiliDanmakuSpeedOptions.findIndex(
                        (option) => option.value === danmakuSpeed
                      )
                    )}
                    valueLabel={
                      bilibiliDanmakuSpeedOptions.find((option) => option.value === danmakuSpeed)
                        ?.label ?? "适中"
                    }
                    onChange={(index) =>
                      setDanmakuSpeed(
                        bilibiliDanmakuSpeedOptions[index]?.value ?? bilibiliDanmakuDefaults.speed
                      )
                    }
                  />
                </SettingRow>
                <SettingRow title="弹幕密度">
                  <Segmented<BilibiliDanmakuDensity>
                    value={danmakuDensity}
                    onChange={setDanmakuDensity}
                    options={[
                      { value: "normal", label: "正常" },
                      { value: "more", label: "较多" },
                      { value: "overlap", label: "重叠" }
                    ]}
                  />
                </SettingRow>
                <SettingRow title="弹幕字体">
                  <select
                    aria-label="弹幕字体"
                    value={danmakuFont}
                    onChange={(event) => setDanmakuFont(event.target.value as BilibiliDanmakuFont)}
                    className="border-line bg-surface-2 text-ink-soft max-w-[170px] rounded-full border px-3 py-1.5 text-[11px] font-bold outline-none"
                  >
                    {bilibiliDanmakuFontOptions.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </select>
                </SettingRow>
                <SettingRow title="粗体">
                  <Switch checked={danmakuBold} onCheckedChange={setDanmakuBold} />
                </SettingRow>
                <SettingRow title="描边类型">
                  <Segmented<BilibiliDanmakuBorder>
                    value={danmakuBorder}
                    onChange={setDanmakuBorder}
                    options={[
                      { value: "heavy", label: "重墨" },
                      { value: "outline", label: "描边" },
                      { value: "shadow45", label: "45°" }
                    ]}
                  />
                </SettingRow>
                <SettingRow title="随屏幕缩放">
                  <Switch
                    checked={danmakuScaleWithPlayer}
                    onCheckedChange={setDanmakuScaleWithPlayer}
                  />
                </SettingRow>
                <SettingRow title="速度同步倍数">
                  <Switch checked={danmakuSpeedSync} onCheckedChange={setDanmakuSpeedSync} />
                </SettingRow>

                <Separator className="bg-line my-[18px]" />
                <div className="text-ink-faint mb-2 text-xs font-bold">发送偏好</div>

                <SettingRow title="发送模式">
                  <Segmented<SendMode>
                    value={sendMode}
                    onChange={setSendMode}
                    options={[
                      { value: "scroll", label: "滚动" },
                      { value: "top", label: "顶部" },
                      { value: "bottom", label: "底部" }
                    ]}
                  />
                </SettingRow>
                <SettingRow title="弹幕颜色">
                  <div className="flex gap-1.5">
                    {colorChoices.map((color) => (
                      <button
                        key={color}
                        type="button"
                        aria-label={`选择颜色 ${color}`}
                        onClick={() => setSelectedColor(color)}
                        className={cn(
                          "size-[22px] rounded-full",
                          selectedColor === color && "outline-mint-400 outline-2 outline-offset-2"
                        )}
                        style={{ background: color }}
                      />
                    ))}
                  </div>
                </SettingRow>
                <Separator className="bg-line my-[18px]" />
                <div className="text-ink-faint mb-2 text-xs font-bold">屏蔽类型</div>
                <div className="flex flex-wrap gap-2">
                  {[
                    { key: "scroll", label: "滚动" },
                    { key: "top", label: "顶部" },
                    { key: "bottom", label: "底部" },
                    { key: "color", label: "彩色" }
                  ].map((entry) => {
                    const blocked = blockedTypes.has(entry.key);
                    return (
                      <button
                        key={entry.key}
                        type="button"
                        onClick={() => toggleBlocked(entry.key)}
                        className={cn(
                          "rounded-full border px-3 py-1.5 text-xs font-bold transition",
                          blocked
                            ? "bg-cherry-400 border-transparent text-white"
                            : "border-line bg-surface-2 text-ink-soft"
                        )}
                      >
                        {entry.label}
                      </button>
                    );
                  })}
                </div>
              </div>
            ) : (
              <div>
                <div className="text-ink-faint mb-2 text-xs font-bold">字幕</div>
                <SettingRow title="字幕轨道">
                  <Segmented<string>
                    value={activeSubtitleId}
                    onChange={setSelectedSubtitleId}
                    options={[
                      { value: "off", label: "关闭" },
                      ...subtitleTracks.slice(0, 3).map((track) => ({
                        value: track.id,
                        label: shortLabel(track.label)
                      }))
                    ]}
                  />
                </SettingRow>
                {(session?.subtitles ?? []).some((track) => track.errorMessage) ? (
                  <div className="text-ink-faint text-[11px] leading-5">
                    {(session?.subtitles ?? [])
                      .filter((track) => track.errorMessage)
                      .slice(0, 2)
                      .map((track) => `${track.label}: ${track.errorMessage}`)
                      .join(" / ")}
                  </div>
                ) : null}
              </div>
            )}
          </div>
        </aside>
      </div>
      <EpisodeBindingDialog
        open={episodeBindingDialogOpen}
        session={session}
        onOpenChange={setEpisodeBindingDialogOpen}
        onSession={(nextSession) => {
          applySession(nextSession);
          setEpisodePanelError(null);
        }}
      />
      <DanmakuSearchDialog
        open={activeDanmakuDialog === "dandanplay"}
        sessionId={session?.id ?? null}
        currentCount={
          danmakuSources.find((sourceView) => sourceView.id === "dandanplay")?.count ?? 0
        }
        providerError={
          danmakuSources.find((sourceView) => sourceView.id === "dandanplay")?.errorMessage ?? null
        }
        onOpenChange={(open) => setActiveDanmakuDialog(open ? "dandanplay" : null)}
        onSession={(nextSession) => {
          applySession(nextSession);
          setDanmakuError(null);
        }}
      />
      <DirectDanmakuSourceDialog
        open={activeDanmakuDialog === "bilibili"}
        providerId="bilibili"
        source={danmakuSources.find((sourceView) => sourceView.id === "bilibili") ?? null}
        sessionId={session?.id ?? null}
        onOpenChange={(open) => setActiveDanmakuDialog(open ? "bilibili" : null)}
        onSession={(nextSession) => {
          applySession(nextSession);
          setDanmakuError(null);
        }}
      />
      <DirectDanmakuSourceDialog
        open={activeDanmakuDialog === "bahamut"}
        providerId="bahamut"
        source={danmakuSources.find((sourceView) => sourceView.id === "bahamut") ?? null}
        sessionId={session?.id ?? null}
        onOpenChange={(open) => setActiveDanmakuDialog(open ? "bahamut" : null)}
        onSession={(nextSession) => {
          applySession(nextSession);
          setDanmakuError(null);
        }}
      />
    </WindowFrame>
  );
}

function playableSubtitleTracks(tracks: SubtitleTrackView[]): SubtitleTrackView[] {
  return tracks.filter((track) => track.renderMode !== "unsupported" && Boolean(track.url));
}

function syncNativeSubtitleTracks(
  video: HTMLVideoElement,
  tracks: SubtitleTrackView[],
  onLoad: () => void
): () => void {
  const elements = tracks.flatMap((track) => {
    if (!track.url) return [];
    const element = document.createElement("track");
    element.dataset.melonbangSubtitle = track.id;
    element.kind = "subtitles";
    element.src = track.url;
    element.label = track.label;
    if (track.language) element.srclang = track.language;
    element.default = track.default;
    element.addEventListener("load", onLoad);
    video.append(element);
    sourceSubtitleTrackIds.set(element.track, track.id);
    return [element];
  });

  onLoad();
  return () => {
    for (const element of elements) {
      element.removeEventListener("load", onLoad);
      element.remove();
    }
  };
}

function applySubtitleMode(
  video: HTMLVideoElement | null,
  selectedSubtitleId: string,
  timelineOffsetSeconds: number
): void {
  if (!video) {
    return;
  }

  const textTracks = Array.from(video.textTracks);
  textTracks.forEach((track) => {
    for (const cue of Array.from(track.cues ?? [])) {
      const sourceTimes = sourceSubtitleCueTimes.get(cue) ?? {
        startTime: cue.startTime,
        endTime: cue.endTime
      };
      sourceSubtitleCueTimes.set(cue, sourceTimes);
      cue.startTime = toLocalTime(sourceTimes.startTime, timelineOffsetSeconds);
      cue.endTime = toLocalTime(sourceTimes.endTime, timelineOffsetSeconds);
    }
    const sourceTrackId = sourceSubtitleTrackIds.get(track);
    track.mode =
      sourceTrackId === selectedSubtitleId && selectedSubtitleId !== "off" ? "showing" : "disabled";
  });
}

function resolveSubtitleId(tracks: SubtitleTrackView[], selectedSubtitleId: string): string {
  if (!tracks.length || selectedSubtitleId === "off") {
    return "off";
  }
  if (selectedSubtitleId !== "auto" && tracks.some((track) => track.id === selectedSubtitleId)) {
    return selectedSubtitleId;
  }
  return tracks.find((track) => track.default)?.id ?? tracks[0].id;
}

function shortLabel(value: string): string {
  return value.length > 8 ? `${value.slice(0, 8)}…` : value;
}

function finiteOrZero(value: number): number {
  return Number.isFinite(value) ? value : 0;
}

function getSeekableEndSeconds(video: HTMLVideoElement): number | null {
  let endSeconds: number | null = null;
  for (let index = 0; index < video.seekable.length; index += 1) {
    const candidate = video.seekable.end(index);
    if (Number.isFinite(candidate)) {
      endSeconds = endSeconds === null ? candidate : Math.max(endSeconds, candidate);
    }
  }
  return endSeconds;
}

function toPlaybackErrorMessage(
  video: HTMLVideoElement,
  error: unknown,
  deliveryMode: PlaybackDeliveryMode
): string | null {
  if (error instanceof Error && error.message) {
    return error.message;
  }

  if (
    deliveryMode !== "direct" &&
    (video.error?.code === MediaError.MEDIA_ERR_DECODE ||
      video.error?.code === MediaError.MEDIA_ERR_SRC_NOT_SUPPORTED)
  ) {
    return null;
  }

  switch (video.error?.code) {
    case MediaError.MEDIA_ERR_ABORTED:
      return "播放请求已中断。";
    case MediaError.MEDIA_ERR_NETWORK:
      return "本地媒体 URL 读取失败，请重新从缓存页进入播放。";
    case MediaError.MEDIA_ERR_DECODE:
      return "实时解码没有生成可播放的视频或音频，请重新进入播放后再试。";
    case MediaError.MEDIA_ERR_SRC_NOT_SUPPORTED:
      return "媒体准备失败，播放器没有收到可用的视频流。";
    default:
      return "浏览器播放器没有接受这个本地媒体源。";
  }
}

function toMessage(reason: unknown, fallback: string): string {
  return reason instanceof Error && reason.message ? reason.message : fallback;
}
