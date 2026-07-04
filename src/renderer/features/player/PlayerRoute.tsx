import { useEffect, useMemo, useRef, useState } from "react";
import type { ButtonHTMLAttributes, MouseEvent, ReactNode, SyntheticEvent } from "react";
import { useNavigate } from "react-router-dom";
import {
  ChevronLeft,
  Expand,
  MessageSquareText,
  Pause,
  Play,
  Send,
  SkipBack,
  SkipForward,
  Volume2
} from "lucide-react";
import type {
  DanmakuItemView,
  PlaybackSessionView,
  SubtitleTrackView
} from "@shared/contracts/playback";
import {
  DANMAKU_COLORS,
  DANMAKU_MESSAGES,
  NOW_PLAYING,
  PLAYER_EPISODES,
  SPEEDS,
  type PlayerEpisode
} from "@/data/player";
import { WindowFrame } from "@/app/shell/WindowFrame";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";

type RightPanel = "episodes" | "settings";
type DanmakuArea = "quarter" | "half" | "full";
type SendMode = "scroll" | "top" | "bottom";
type OverlayDanmakuMessage = Pick<DanmakuItemView, "text" | "color" | "mode">;

const colorChoices = ["#fff", "#ffd56b", "#ff9eb5", "#86c5ff", "#9be7c4", "#c8a8f0"];

type HlsInstance = {
  on(event: string, listener: (event: string, data: unknown) => void): void;
  once(event: string, listener: (event: string, data: unknown) => void): void;
  loadSource(url: string): void;
  attachMedia(video: HTMLVideoElement): void;
  destroy(): void;
};

type HlsConstructor = {
  Events: {
    ERROR: string;
    MANIFEST_PARSED: string;
    MEDIA_ATTACHED: string;
  };
  isSupported(): boolean;
  new (): HlsInstance;
};

function PlayerIconButton({
  active,
  className,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { active?: boolean }) {
  return (
    <button
      type="button"
      className={cn(
        "grid flex-none place-items-center rounded-lg bg-transparent p-1 text-white/90 transition hover:text-white",
        active && "text-mint-300",
        className
      )}
      {...props}
    >
      {children}
    </button>
  );
}

function PlayerPop({ children, onClick }: { children: ReactNode; onClick?: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-full bg-white/[0.15] px-2.5 py-1 text-xs font-bold whitespace-nowrap text-white transition hover:bg-white/[0.25]"
    >
      {children}
    </button>
  );
}

function EpisodeItem({
  episode,
  selected,
  onSelect
}: {
  episode: PlayerEpisode;
  selected: boolean;
  onSelect: () => void;
}) {
  const current = selected || episode.state === "current";
  const watched = episode.state === "watched";
  const unaired = episode.state === "unaired";

  return (
    <button
      type="button"
      disabled={unaired}
      onClick={onSelect}
      className={cn(
        "flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition",
        current && "outline-mint-200 bg-mint-50 dark:bg-mint-400/15 outline outline-1",
        !current && "hover:bg-surface-2",
        unaired && "cursor-not-allowed opacity-60"
      )}
    >
      <span
        className={cn(
          "bg-surface-3 text-ink-soft grid size-[30px] flex-none place-items-center rounded-[9px] text-[13px] font-extrabold",
          current && "bg-mint-400 text-on-accent",
          watched && !current && "bg-mint-100 text-mint-600"
        )}
      >
        {episode.n}
      </span>
      <span className="min-w-0 flex-1">
        <b className="block truncate text-[13px]">
          第{episode.n}话 · {episode.title}
        </b>
        <span className="text-ink-faint text-[11px]">{episode.duration}</span>
      </span>
      {current ? (
        <Badge variant="mint" className="text-[10px]">
          播放中
        </Badge>
      ) : watched ? (
        <span className="text-ink-faint text-[11px]">已看</span>
      ) : unaired ? (
        <Badge variant="outline" className="text-[10px]">
          待播
        </Badge>
      ) : null}
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

export function PlayerRoute() {
  const navigate = useNavigate();
  const playerAreaRef = useRef<HTMLDivElement | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const lastProgressReportRef = useRef(0);
  const [session, setSession] = useState<PlaybackSessionView | null>(null);
  const [playing, setPlaying] = useState(true);
  const [playbackError, setPlaybackError] = useState<string | null>(null);
  const [danmakuEnabled, setDanmakuEnabled] = useState(true);
  const [panel, setPanel] = useState<RightPanel>("episodes");
  const [speedIndex, setSpeedIndex] = useState(2);
  const [selectedEpisode, setSelectedEpisode] = useState(7);
  const [danmakuText, setDanmakuText] = useState("");
  const [localDanmaku, setLocalDanmaku] = useState<OverlayDanmakuMessage[]>([]);
  const [showDanmaku, setShowDanmaku] = useState(true);
  const [danmakuArea, setDanmakuArea] = useState<DanmakuArea>("half");
  const [sendMode, setSendMode] = useState<SendMode>("scroll");
  const [selectedColor, setSelectedColor] = useState(colorChoices[0]);
  const [blockedTypes, setBlockedTypes] = useState(new Set(["top", "bottom"]));
  const [selectedSubtitleId, setSelectedSubtitleId] = useState("auto");
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState<number | null>(null);
  const [volume, setVolume] = useState(0.64);
  const [danmakuOpacity, setDanmakuOpacity] = useState(80);
  const [danmakuFontSize, setDanmakuFontSize] = useState(18);
  const [danmakuSpeed, setDanmakuSpeed] = useState(6);
  const [danmakuDensity, setDanmakuDensity] = useState(7);
  const source = session?.source ?? null;
  const sourceKind = source?.kind;
  const sourceUrl = source?.url;
  const subtitleTracks = useMemo(() => nativeSubtitleTracks(session), [session]);
  const activeSubtitleId = resolveSubtitleId(subtitleTracks, selectedSubtitleId);

  useEffect(() => {
    const bridge = window.melonbang?.playback;
    if (!bridge) {
      return;
    }

    let cancelled = false;
    const unsubscribe = bridge.onEvent((nextSession) => {
      if (!cancelled) {
        setSession(nextSession);
      }
    });

    void bridge
      .getSession()
      .then((nextSession) => {
        if (!cancelled) {
          setSession(nextSession);
        }
      })
      .catch(() => undefined);

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, []);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !sourceKind || !sourceUrl) {
      return;
    }

    let cancelled = false;
    let hls: HlsInstance | null = null;
    setPlaybackError(null);
    lastProgressReportRef.current = 0;

    const play = (): void => {
      if (cancelled) {
        return;
      }

      void video
        .play()
        .then(() => setPlaying(true))
        .catch((error: unknown) => {
          if (!cancelled) {
            setPlaying(false);
            setPlaybackError(toPlaybackErrorMessage(video, error));
          }
        });
    };

    const playDirect = (): void => {
      video.src = sourceUrl;
      play();
    };

    if (sourceKind === "hls") {
      void import("hls.js")
        .then(({ default: Hls }) => {
          if (cancelled) {
            return;
          }

          const HlsRuntime = Hls as HlsConstructor;
          if (!HlsRuntime.isSupported()) {
            if (canPlayHlsNatively(video)) {
              playDirect();
              return;
            }

            setPlaying(false);
            setPlaybackError("当前 Electron/Chromium 环境不支持 HLS 播放，HLS.js 也无法初始化。");
            return;
          }

          hls = new HlsRuntime();
          hls.once(HlsRuntime.Events.MEDIA_ATTACHED, () => {
            if (!cancelled) {
              hls?.loadSource(sourceUrl);
            }
          });
          hls.once(HlsRuntime.Events.MANIFEST_PARSED, () => {
            play();
          });
          hls.on(HlsRuntime.Events.ERROR, (_event, data) => {
            if (cancelled) {
              return;
            }

            const error = normalizeHlsError(data);
            if (error.fatal) {
              setPlaying(false);
              setPlaybackError(error.message);
            }
          });
          hls.attachMedia(video);
        })
        .catch((error: unknown) => {
          if (!cancelled) {
            if (canPlayHlsNatively(video)) {
              playDirect();
              return;
            }

            setPlaying(false);
            setPlaybackError(toPlaybackErrorMessage(video, error));
          }
        });
    } else {
      playDirect();
    }

    return () => {
      cancelled = true;
      hls?.destroy();
      video.removeAttribute("src");
      video.load();
    };
  }, [sourceKind, sourceUrl]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) {
      return;
    }

    video.volume = volume;
  }, [volume]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) {
      return;
    }

    video.playbackRate = speedValue(SPEEDS[speedIndex]);
  }, [speedIndex]);

  useEffect(() => {
    applySubtitleMode(videoRef.current, subtitleTracks, activeSubtitleId);
  }, [activeSubtitleId, subtitleTracks]);

  function cycleSpeed(): void {
    setSpeedIndex((value) => (value + 1) % SPEEDS.length);
  }

  function cycleSubtitle(): void {
    if (!subtitleTracks.length) {
      setSelectedSubtitleId("off");
      return;
    }

    setSelectedSubtitleId((current) => {
      const options = ["off", ...subtitleTracks.map((track) => track.id)];
      const currentIndex = Math.max(0, options.indexOf(resolveSubtitleId(subtitleTracks, current)));
      return options[(currentIndex + 1) % options.length];
    });
  }

  function seekFromPointer(event: MouseEvent<HTMLDivElement>): void {
    const video = videoRef.current;
    const activeDuration = duration ?? video?.duration ?? null;
    if (!video || !activeDuration || !Number.isFinite(activeDuration)) {
      return;
    }

    const rect = event.currentTarget.getBoundingClientRect();
    const ratio = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width));
    video.currentTime = ratio * activeDuration;
    setCurrentTime(video.currentTime);
    reportVideoProgress(video);
  }

  function toggleFullscreen(): void {
    const target = playerAreaRef.current;
    if (!target) {
      return;
    }

    if (document.fullscreenElement) {
      void document.exitFullscreen();
      return;
    }

    void target.requestFullscreen();
  }

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

  function togglePlayback(): void {
    const video = videoRef.current;
    if (!video || !session?.source) {
      setPlaying((value) => !value);
      return;
    }

    if (video.paused) {
      void video.play().catch((error: unknown) => {
        setPlaying(false);
        setPlaybackError(toPlaybackErrorMessage(video, error));
      });
    } else {
      video.pause();
    }
  }

  function sendDanmaku(): void {
    const text = danmakuText.trim().slice(0, 28);
    if (!text) {
      return;
    }

    setLocalDanmaku((items) => [
      ...items,
      {
        text,
        mode: sendMode,
        color: selectedColor
      }
    ]);
    setDanmakuText("");
  }

  function handleVideoProgress(event: SyntheticEvent<HTMLVideoElement>): void {
    setCurrentTime(finiteOrZero(event.currentTarget.currentTime));
    setDuration(Number.isFinite(event.currentTarget.duration) ? event.currentTarget.duration : null);
    reportVideoProgress(event.currentTarget);
  }

  function handleVideoLoadedMetadata(event: SyntheticEvent<HTMLVideoElement>): void {
    setPlaybackError(null);
    setCurrentTime(finiteOrZero(event.currentTarget.currentTime));
    setDuration(Number.isFinite(event.currentTarget.duration) ? event.currentTarget.duration : null);
    applySubtitleMode(event.currentTarget, subtitleTracks, activeSubtitleId);
    reportVideoProgress(event.currentTarget);
  }

  function handleVideoError(event: SyntheticEvent<HTMLVideoElement>): void {
    const video = event.currentTarget;
    setPlaying(false);
    if (source?.kind === "hls") {
      setPlaybackError((message) => message ?? "HLS 转码流加载失败，播放器没有收到可用的视频片段。");
      return;
    }
    setPlaybackError(toPlaybackErrorMessage(video));
  }

  function reportVideoProgress(video: HTMLVideoElement): void {
    if (!session) {
      return;
    }

    const now = Date.now();
    if (!video.ended && now - lastProgressReportRef.current < 1000) {
      return;
    }

    lastProgressReportRef.current = now;
    const bridge = window.melonbang?.playback;
    if (!bridge) {
      return;
    }

    void bridge
      .updateProgress({
        sessionId: session.id,
        positionSeconds: finiteOrZero(video.currentTime),
        durationSeconds: Number.isFinite(video.duration) ? video.duration : null,
        paused: video.paused,
        ended: video.ended
      })
      .then(setSession)
      .catch(() => undefined);
  }

  const overlayDanmaku = getOverlayDanmaku(session, localDanmaku);
  const visibleDanmaku = filterDanmaku(overlayDanmaku, blockedTypes, danmakuDensity);
  const progressDuration = duration ?? session?.durationSeconds ?? null;
  const progressPosition = currentTime || session?.positionSeconds || 0;
  const progressRatio =
    progressDuration && progressDuration > 0
      ? Math.min(1, Math.max(0, progressPosition / progressDuration))
      : 0;
  const displayedTitle = session?.title ?? NOW_PLAYING.title;
  const displayedEpisode = session ? "本地播放" : `${NOW_PLAYING.ep}「${NOW_PLAYING.epTitle}」`;
  const displayedSource = source
    ? `来源：本地缓存 · ${source.mimeType ?? "HTMLVideoElement"}`
    : NOW_PLAYING.source;
  const displayedTime = session
    ? formatClock(progressPosition, progressDuration)
    : NOW_PLAYING.time;
  const subtitleLabel = selectedSubtitleLabel(subtitleTracks, activeSubtitleId);
  const mainIcon = playing ? (
    <Pause className="size-8 fill-current" />
  ) : (
    <Play className="size-8 fill-current" />
  );
  const smallIcon = playing ? (
    <Pause className="size-[18px] fill-current" />
  ) : (
    <Play className="size-[18px] fill-current" />
  );

  return (
    <WindowFrame crumb="正在播放">
      <div className="grid h-full min-h-0 grid-cols-[1fr_344px] max-[1080px]:grid-cols-1">
        <section className="flex min-w-0 flex-col bg-[var(--player-bg)]">
          <div
            ref={playerAreaRef}
            className="relative min-h-0 flex-1 overflow-hidden bg-[radial-gradient(120%_100%_at_70%_20%,rgba(22,64,74,.6),var(--player-bg)_70%)]"
          >
            <div
              className={cn(
                "absolute inset-0 bg-[linear-gradient(135deg,var(--mint-600),var(--sky-500))] opacity-[.18]",
                source && "opacity-0"
              )}
            />

            {source ? (
              <video
                key={sourceUrl}
                ref={videoRef}
                className="absolute inset-0 z-[1] size-full bg-black object-contain"
                playsInline
                onPlay={() => setPlaying(true)}
                onPause={(event) => {
                  setPlaying(false);
                  handleVideoProgress(event);
                }}
                onLoadedMetadata={handleVideoLoadedMetadata}
                onProgress={handleVideoProgress}
                onTimeUpdate={handleVideoProgress}
                onSeeking={handleVideoProgress}
                onSeeked={handleVideoProgress}
                onEnded={handleVideoProgress}
                onError={handleVideoError}
              >
                {nativeSubtitleTracks(session).map((track) => (
                  <track
                    key={track.id}
                    kind="subtitles"
                    src={track.url ?? undefined}
                    srcLang={track.language ?? undefined}
                    label={track.label}
                    default={track.default}
                  />
                ))}
              </video>
            ) : null}

            <div
              className={cn(
                "pointer-events-none absolute inset-0 z-[4] overflow-hidden transition-opacity",
                danmakuEnabled && showDanmaku ? "opacity-100" : "opacity-0"
              )}
              style={{ opacity: danmakuEnabled && showDanmaku ? danmakuOpacity / 100 : 0 }}
            >
              {visibleDanmaku.map((message, i) => (
                <span
                  key={`${message.text}-${i}`}
                  className="absolute text-[18px] font-bold whitespace-nowrap text-white will-change-transform [text-shadow:0_1px_4px_rgba(0,0,0,.6)]"
                  style={{
                    top: `${getDanmakuTop(message.mode, i, danmakuArea)}%`,
                    color: message.color ?? DANMAKU_COLORS[i % DANMAKU_COLORS.length],
                    fontSize: `${danmakuFontSize + (i % 3)}px`,
                    animation: `danmaku-fly ${danmakuDurationSeconds(danmakuSpeed, i)}s linear ${i * 0.55}s infinite`
                  }}
                >
                  {message.text}
                </span>
              ))}
            </div>

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
              <span className="rounded-full bg-white/[0.15] px-2.5 py-1 text-[11.5px] font-bold text-white">
                {displayedSource}
              </span>
            </div>

            <div
              className={cn(
                "absolute inset-0 z-[5] grid place-items-center transition",
                playing && "opacity-0"
              )}
            >
              <button
                type="button"
                onClick={togglePlayback}
                className="grid size-[78px] place-items-center rounded-full border border-white/[0.3] bg-white/[0.15] text-white backdrop-blur-md transition hover:scale-105 hover:bg-white/[0.25]"
                aria-label={playing ? "暂停" : "播放"}
              >
                {mainIcon}
              </button>
            </div>

            {playbackError ? (
              <div className="absolute right-6 bottom-6 left-6 z-[9] rounded-xl border border-white/[0.18] bg-black/70 px-4 py-3 text-white shadow-[0_16px_36px_rgba(0,0,0,.35)] backdrop-blur-md">
                <div className="text-sm font-extrabold">
                  {source?.kind === "hls" ? "转码播放失败" : "当前文件无法直接播放"}
                </div>
                <div className="mt-1 text-[12px] leading-5 text-white/75">{playbackError}</div>
              </div>
            ) : null}
          </div>

          <div className="border-t border-[var(--player-border)] bg-[var(--player-surface)] px-4 pt-2.5 pb-3.5 text-white">
            <div
              className="mb-2.5 h-[5px] cursor-pointer rounded-full bg-white/20"
              onClick={seekFromPointer}
            >
              <div className="relative h-full rounded-full">
                <div
                  className="absolute top-0 bottom-0 left-0 rounded-full bg-white/[0.3]"
                  style={{ width: `${Math.max(progressRatio * 100, 0)}%` }}
                />
                <div
                  className="absolute top-0 bottom-0 left-0 rounded-full bg-[linear-gradient(90deg,var(--mint-400),var(--mint-300))]"
                  style={{ width: `${Math.max(progressRatio * 100, 0)}%` }}
                />
                <div
                  className="absolute top-1/2 size-[13px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-white shadow-[0_2px_6px_rgba(0,0,0,.4)]"
                  style={{ left: `${Math.max(progressRatio * 100, 0)}%` }}
                />
              </div>
            </div>

            <div className="flex items-center gap-3 text-sm">
              <div className="flex flex-none items-center gap-2.5">
                <PlayerIconButton onClick={togglePlayback}>{smallIcon}</PlayerIconButton>
                <PlayerIconButton title="上一集">
                  <SkipBack className="size-[18px] fill-current" />
                </PlayerIconButton>
                <PlayerIconButton title="下一集">
                  <SkipForward className="size-[18px] fill-current" />
                </PlayerIconButton>
                <PlayerIconButton title="音量">
                  <Volume2 className="size-5" />
                </PlayerIconButton>
                <input
                  aria-label="音量"
                  type="range"
                  min="0"
                  max="1"
                  step="0.01"
                  value={volume}
                  onChange={(event) => setVolume(Number(event.target.value))}
                  className="w-[60px] flex-none accent-white"
                />
                <span className="font-semibold whitespace-nowrap text-white/90 tabular-nums">
                  {displayedTime}
                </span>
              </div>

              <div className="flex min-w-0 flex-1 items-center justify-center gap-2">
                <PlayerIconButton
                  active={danmakuEnabled}
                  title="弹幕开关"
                  onClick={() => setDanmakuEnabled((value) => !value)}
                  aria-pressed={danmakuEnabled}
                >
                  <MessageSquareText className="size-4" />
                </PlayerIconButton>
                <div className="flex max-w-[520px] flex-1 items-center gap-2 rounded-full border border-[var(--player-border)] bg-[var(--player-bg)] px-3.5 py-2 text-white">
                  <input
                    value={danmakuText}
                    onChange={(event) => setDanmakuText(event.target.value)}
                    placeholder="发个友善的弹幕，见证当下…"
                    className="min-w-0 flex-1 bg-transparent text-[13px] outline-none placeholder:text-[#6c7c85]"
                  />
                  <span className="text-[11px] text-[#6c7c85]">
                    {Math.max(0, 28 - danmakuText.length)}
                  </span>
                </div>
                <Button size="sm" onClick={sendDanmaku} disabled={!danmakuText.trim()}>
                  <Send className="size-4" />
                  发送
                </Button>
              </div>

              <div className="flex flex-none items-center gap-2.5">
                <PlayerPop>1080P</PlayerPop>
                <PlayerPop onClick={cycleSubtitle}>{subtitleLabel}</PlayerPop>
                <PlayerPop onClick={() => setPanel("episodes")}>选集</PlayerPop>
                <PlayerPop onClick={cycleSpeed}>{SPEEDS[speedIndex]}</PlayerPop>
                <PlayerIconButton title="全屏" onClick={toggleFullscreen}>
                  <Expand className="size-[18px]" />
                </PlayerIconButton>
              </div>
            </div>
          </div>
        </section>

        <aside className="border-line bg-surface flex min-h-0 flex-col border-l max-[1080px]:hidden">
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
                onClick={() => setPanel("settings")}
                className={cn(
                  "flex flex-1 justify-center rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                  panel === "settings"
                    ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_5px_12px_rgba(34,179,136,.28)]"
                    : "text-ink-soft hover:text-ink"
                )}
              >
                弹幕设置
              </button>
            </div>
          </div>

          <div className="min-h-0 flex-1 overflow-auto px-3.5 py-3">
            {panel === "episodes" ? (
              <div className="flex flex-col gap-1">
                {PLAYER_EPISODES.map((episode) => (
                  <EpisodeItem
                    key={episode.n}
                    episode={episode}
                    selected={episode.n === selectedEpisode}
                    onSelect={() => setSelectedEpisode(episode.n)}
                  />
                ))}
              </div>
            ) : (
              <div>
                <SettingRow title="显示弹幕" description="关闭后将隐藏所有弹幕">
                  <Switch checked={showDanmaku} onCheckedChange={setShowDanmaku} />
                </SettingRow>
                <SettingRow title="弹幕透明度">
                  <input
                    type="range"
                    min="10"
                    max="100"
                    value={danmakuOpacity}
                    onChange={(event) => setDanmakuOpacity(Number(event.target.value))}
                    className="w-[120px]"
                  />
                </SettingRow>
                <SettingRow title="显示区域">
                  <Segmented<DanmakuArea>
                    value={danmakuArea}
                    onChange={setDanmakuArea}
                    options={[
                      { value: "quarter", label: "1/4" },
                      { value: "half", label: "半屏" },
                      { value: "full", label: "全屏" }
                    ]}
                  />
                </SettingRow>
                <SettingRow title="字体大小">
                  <input
                    type="range"
                    min="12"
                    max="36"
                    value={danmakuFontSize}
                    onChange={(event) => setDanmakuFontSize(Number(event.target.value))}
                    className="w-[120px]"
                  />
                </SettingRow>
                <SettingRow title="弹幕速度">
                  <input
                    type="range"
                    min="1"
                    max="10"
                    value={danmakuSpeed}
                    onChange={(event) => setDanmakuSpeed(Number(event.target.value))}
                    className="w-[120px]"
                  />
                </SettingRow>
                <SettingRow title="弹幕密度">
                  <input
                    type="range"
                    min="1"
                    max="10"
                    value={danmakuDensity}
                    onChange={(event) => setDanmakuDensity(Number(event.target.value))}
                    className="w-[120px]"
                  />
                </SettingRow>

                <div className="bg-line my-[18px] h-px" />
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

                <div className="bg-line my-[18px] h-px" />
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
                <SettingRow title="描边阴影" description="提升暗背景下可读性">
                  <Switch defaultChecked />
                </SettingRow>

                <div className="bg-line my-[18px] h-px" />
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
            )}
          </div>
        </aside>
      </div>
    </WindowFrame>
  );
}

function getOverlayDanmaku(
  session: PlaybackSessionView | null,
  localDanmaku: OverlayDanmakuMessage[]
): OverlayDanmakuMessage[] {
  const sessionDanmaku = session?.danmaku ?? [];
  if (sessionDanmaku.length || localDanmaku.length) {
    return [...sessionDanmaku, ...localDanmaku];
  }

  return DANMAKU_MESSAGES.map((text, index) => ({
    text,
    mode: "scroll",
    color: DANMAKU_COLORS[index % DANMAKU_COLORS.length]
  }));
}

function filterDanmaku(
  messages: OverlayDanmakuMessage[],
  blockedTypes: Set<string>,
  density: number
): OverlayDanmakuMessage[] {
  const limit = Math.max(1, Math.round((density / 10) * 36));
  return messages
    .filter((message) => !blockedTypes.has(message.mode))
    .filter((message) => !(blockedTypes.has("color") && message.color && message.color !== "#fff"))
    .slice(0, limit);
}

function getDanmakuTop(
  mode: DanmakuItemView["mode"],
  index: number,
  area: DanmakuArea
): number {
  const areaMax = area === "quarter" ? 24 : area === "half" ? 52 : 82;
  if (mode === "top") {
    return 8 + (index % 4) * 7;
  }
  if (mode === "bottom") {
    return Math.max(8, areaMax - 12 - (index % 3) * 7);
  }
  return 6 + ((index * 37) % Math.max(12, areaMax - 10));
}

function danmakuDurationSeconds(speed: number, index: number): number {
  return Math.max(3, 12 - speed + (index % 3));
}

function nativeSubtitleTracks(session: PlaybackSessionView | null): SubtitleTrackView[] {
  return (session?.subtitles ?? []).filter(
    (track) => track.renderMode === "native-vtt" && Boolean(track.url)
  );
}

function applySubtitleMode(
  video: HTMLVideoElement | null,
  tracks: SubtitleTrackView[],
  selectedSubtitleId: string
): void {
  if (!video) {
    return;
  }

  const textTracks = Array.from(video.textTracks);
  textTracks.forEach((track, index) => {
    const sourceTrack = tracks[index];
    track.mode =
      sourceTrack && sourceTrack.id === selectedSubtitleId && selectedSubtitleId !== "off"
        ? "showing"
        : "disabled";
  });
}

function selectedSubtitleLabel(tracks: SubtitleTrackView[], selectedSubtitleId: string): string {
  if (!tracks.length) {
    return "字幕";
  }
  if (selectedSubtitleId === "off") {
    return "字幕关";
  }
  return shortLabel(tracks.find((track) => track.id === selectedSubtitleId)?.label ?? "字幕");
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

function speedValue(label: string): number {
  const parsed = Number(label.replace("x", ""));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 1;
}

function canPlayHlsNatively(video: HTMLVideoElement): boolean {
  return Boolean(
    video.canPlayType("application/vnd.apple.mpegurl") ||
      video.canPlayType("application/x-mpegURL")
  );
}

function normalizeHlsError(data: unknown): { fatal: boolean; message: string } {
  if (!data || typeof data !== "object") {
    return {
      fatal: true,
      message: "HLS 转码流加载失败。"
    };
  }

  const errorData = data as {
    fatal?: boolean;
    type?: string;
    details?: string;
    error?: { message?: string };
    reason?: string;
    response?: { code?: number; text?: string };
  };
  const details = [errorData.details, errorData.reason, errorData.error?.message]
    .filter(Boolean)
    .join("：");
  const response =
    errorData.response?.code || errorData.response?.text
      ? `HTTP ${errorData.response.code ?? ""} ${errorData.response.text ?? ""}`.trim()
      : null;

  return {
    fatal: Boolean(errorData.fatal),
    message:
      [details || errorData.type, response].filter(Boolean).join("；") ||
      "HLS 转码流加载失败。"
  };
}

function finiteOrZero(value: number): number {
  return Number.isFinite(value) ? value : 0;
}

function formatClock(positionSeconds: number, durationSeconds: number | null): string {
  return `${formatTime(positionSeconds)} / ${durationSeconds ? formatTime(durationSeconds) : "--:--"}`;
}

function formatTime(totalSeconds: number): string {
  const safeSeconds = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(safeSeconds / 60);
  const seconds = safeSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

function toPlaybackErrorMessage(video: HTMLVideoElement, error?: unknown): string {
  if (error instanceof Error && error.message) {
    return error.message;
  }

  switch (video.error?.code) {
    case MediaError.MEDIA_ABORTED:
      return "播放请求已中断。";
    case MediaError.MEDIA_NETWORK:
      return "本地媒体 URL 读取失败，请重新从缓存页进入播放。";
    case MediaError.MEDIA_DECODE:
      return "Electron/Chromium 无法解码当前文件的视频或音频编码。HEVC/H.265、部分 MKV/字幕封装在 Web-native 播放链路里可能不受支持。";
    case MediaError.MEDIA_SRC_NOT_SUPPORTED:
      return "当前文件格式或编码不受 HTMLVideoElement 支持。请先尝试 H.264/AAC 的 MP4/WebM 文件；HEVC/H.265 需要后续兼容性转换方案。";
    default:
      return "浏览器播放器没有接受这个本地媒体源。";
  }
}
