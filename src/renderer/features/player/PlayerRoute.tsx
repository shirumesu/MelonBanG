import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { ChevronLeft } from "lucide-react";
import type {
  PlaybackSessionView,
  SubtitleTrackView
} from "@shared/contracts/playback";
import { NOW_PLAYING, PLAYER_EPISODES, type PlayerEpisode } from "@/data/player";
import { WindowFrame } from "@/app/shell/WindowFrame";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";
import { createAssSubtitleRenderer, type AssSubtitleRendererHandle } from "./assSubtitleRenderer";
import {
  createArtPlayerController,
  type ArtPlayerController
} from "./artPlayerController";
import {
  filterDanmakuItems,
  toArtPlayerDanmuku,
  toArtPlayerDanmakuMode
} from "./danmaku";
import {
  resolvePlaybackDuration,
  resolveSeekAction,
  toLocalTime,
  toSourceTime
} from "@shared/playerTiming";

type RightPanel = "episodes" | "settings";
type DanmakuArea = "quarter" | "half" | "full";
type SendMode = "scroll" | "top" | "bottom";

const colorChoices = ["#fff", "#ffd56b", "#ff9eb5", "#86c5ff", "#9be7c4", "#c8a8f0"];
const sourceSubtitleCueTimes = new WeakMap<TextTrackCue, { startTime: number; endTime: number }>();
const sourceSubtitleTrackIds = new WeakMap<TextTrack, string>();

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
  const artContainerRef = useRef<HTMLDivElement | null>(null);
  const controllerRef = useRef<ArtPlayerController | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const sessionRef = useRef<PlaybackSessionView | null>(null);
  const timelineOffsetRef = useRef(0);
  const nativeTracksRef = useRef<SubtitleTrackView[]>([]);
  const activeSubtitleIdRef = useRef("off");
  const seekRestartRef = useRef(false);
  const lastProgressReportRef = useRef(0);
  const shouldPlayRef = useRef(true);
  const [session, setSession] = useState<PlaybackSessionView | null>(null);
  const [playbackError, setPlaybackError] = useState<string | null>(null);
  const [subtitleError, setSubtitleError] = useState<string | null>(null);
  const [danmakuError, setDanmakuError] = useState<string | null>(null);
  const [panel, setPanel] = useState<RightPanel>("episodes");
  const [selectedEpisode, setSelectedEpisode] = useState(7);
  const [showDanmaku, setShowDanmaku] = useState(true);
  const [danmakuArea, setDanmakuArea] = useState<DanmakuArea>("half");
  const [sendMode, setSendMode] = useState<SendMode>("scroll");
  const [selectedColor, setSelectedColor] = useState(colorChoices[0]);
  const [blockedTypes, setBlockedTypes] = useState(new Set(["top", "bottom"]));
  const [selectedSubtitleId, setSelectedSubtitleId] = useState("auto");
  const [danmakuOpacity, setDanmakuOpacity] = useState(80);
  const [danmakuFontSize, setDanmakuFontSize] = useState(18);
  const [danmakuSpeed, setDanmakuSpeed] = useState(6);
  const [danmakuDensity, setDanmakuDensity] = useState(7);
  const source = session?.source ?? null;
  const sourceUrl = source?.url;
  const sourceKind = source?.kind;
  const sourceDeliveryMode = source?.deliveryMode;
  const sourceMimeType = source?.mimeType;
  const sourceTitle = source?.title;
  const timelineOffsetSeconds = source?.timelineOffsetSeconds ?? 0;
  const subtitleTracks = useMemo(() => playableSubtitleTracks(session), [session]);
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
    .map((item) => `${item.timeSeconds}:${item.mode}:${item.color}:${item.text}`)
    .join("|");
  const blockedTypesKey = [...blockedTypes].sort().join("|");
  useEffect(() => {
    sessionRef.current = session;
    timelineOffsetRef.current = timelineOffsetSeconds;
    nativeTracksRef.current = nativeTracks;
    activeSubtitleIdRef.current = activeSubtitleId;
  }, [activeSubtitleId, nativeTracks, session, timelineOffsetSeconds]);

  const reportVideoProgress = useCallback((video: HTMLVideoElement): void => {
    const currentSession = sessionRef.current;
    if (!currentSession) return;

    const now = Date.now();
    if (!video.ended && now - lastProgressReportRef.current < 1000) return;

    lastProgressReportRef.current = now;
    const bridge = window.melonbang?.playback;
    if (!bridge) return;

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
      .then(setSession)
      .catch(() => undefined);
  }, []);

  const handleArtPlayerSeeking = useCallback(
    (video: HTMLVideoElement): void => {
      const currentSession = sessionRef.current;
      const currentSource = currentSession?.source;
      if (!currentSession || !currentSource || seekRestartRef.current) return;

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

      const bridge = window.melonbang?.playback;
      if (!bridge) return;
      seekRestartRef.current = true;
      shouldPlayRef.current = !video.paused;
      setPlaybackError(null);
      void bridge
        .seek({ sessionId: currentSession.id, positionSeconds: action.sourceTimeSeconds })
        .then(setSession)
        .catch((error: unknown) => {
          setPlaybackError(error instanceof Error ? error.message : "无法从目标位置重新准备视频。");
        })
        .finally(() => {
          seekRestartRef.current = false;
        });
    },
    [reportVideoProgress]
  );

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
        danmuku: toArtPlayerDanmuku(sessionRef.current?.danmaku ?? [], timelineOffsetRef.current),
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
            applySubtitleMode(
              video,
              activeSubtitleIdRef.current,
              timelineOffsetRef.current
            );
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
          onError(video, error) {
            if (cancelled) return;
            setPlaybackError(toPlaybackErrorMessage(video, error));
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
    timelineOffsetSeconds,
    handleArtPlayerSeeking,
    reportVideoProgress
  ]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    return syncNativeSubtitleTracks(video, nativeTracksRef.current, () =>
      applySubtitleMode(video, activeSubtitleIdRef.current, timelineOffsetRef.current)
    );
  }, [nativeTrackKey, sourceUrl]);

  useEffect(() => {
    applySubtitleMode(
      videoRef.current,
      activeSubtitleId,
      timelineOffsetSeconds
    );
  }, [activeSubtitleId, nativeTrackKey, timelineOffsetSeconds]);

  useEffect(() => {
    const controller = controllerRef.current;
    if (!controller) return;
    const blocked = new Set(blockedTypesKey ? blockedTypesKey.split("|") : []);
    const items = filterDanmakuItems(sessionRef.current?.danmaku ?? [], blocked, danmakuDensity);
    void controller
      .loadDanmaku(toArtPlayerDanmuku(items, timelineOffsetSeconds))
      .then(() => setDanmakuError(null))
      .catch(() => setDanmakuError("弹幕插件无法加载当前弹幕数据，视频播放不受影响。"));
  }, [blockedTypesKey, danmakuDensity, danmakuKey, sourceUrl, timelineOffsetSeconds]);

  useEffect(() => {
    const controller = controllerRef.current;
    if (!controller) return;
    const modes = (["scroll", "top", "bottom"] as const)
      .filter((mode) => !blockedTypes.has(mode))
      .map(toArtPlayerDanmakuMode);
    controller.configureDanmaku({
      visible: showDanmaku,
      opacity: danmakuOpacity / 100,
      fontSize: danmakuFontSize,
      speed: danmakuSpeed,
      margin: danmakuMargin(danmakuArea),
      modes,
      mode: toArtPlayerDanmakuMode(sendMode),
      color: selectedColor
    });
  }, [
    blockedTypes,
    danmakuArea,
    danmakuFontSize,
    danmakuOpacity,
    danmakuSpeed,
    selectedColor,
    sendMode,
    showDanmaku,
    sourceUrl
  ]);

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

  const displayedTitle = session?.title ?? NOW_PLAYING.title;
  const displayedEpisode = session ? "本地播放" : `${NOW_PLAYING.ep}「${NOW_PLAYING.epTitle}」`;
  const displayedSource = source
    ? `来源：本地缓存 · ${source.mimeType ?? "HTMLVideoElement"}`
    : NOW_PLAYING.source;

  return (
    <WindowFrame crumb="正在播放">
      <div className="grid h-full min-h-0 grid-cols-[1fr_344px] max-[1080px]:grid-cols-1">
        <section className="min-w-0 bg-[var(--player-bg)]">
          <div className="relative h-full min-h-0 overflow-hidden bg-[radial-gradient(120%_100%_at_70%_20%,rgba(22,64,74,.6),var(--player-bg)_70%)]">
            <div
              className={cn(
                "absolute inset-0 bg-[linear-gradient(135deg,var(--mint-600),var(--sky-500))] opacity-[.18]",
                source && "opacity-0"
              )}
            />

            {source ? (
              <div ref={artContainerRef} className="melon-artplayer absolute inset-0 z-[1] bg-black" />
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
              <span className="rounded-full bg-white/[0.15] px-2.5 py-1 text-[11.5px] font-bold text-white">
                {displayedSource}
              </span>
            </div>

            {playbackError || subtitleError || danmakuError ? (
              <div className="absolute right-6 bottom-20 left-6 z-20 rounded-xl border border-white/[0.18] bg-black/70 px-4 py-3 text-white shadow-[0_16px_36px_rgba(0,0,0,.35)] backdrop-blur-md">
                <div className="text-sm font-extrabold">
                  {subtitleError
                    ? "字幕加载失败"
                    : danmakuError
                      ? "弹幕加载失败"
                      : source?.deliveryMode === "remux"
                        ? "重封装播放失败"
                        : source?.kind === "hls"
                          ? "转码播放失败"
                          : "当前文件无法直接播放"}
                </div>
                <div className="mt-1 text-[12px] leading-5 text-white/75">
                  {subtitleError ?? danmakuError ?? playbackError}
                </div>
              </div>
            ) : null}
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

function playableSubtitleTracks(session: PlaybackSessionView | null): SubtitleTrackView[] {
  return (session?.subtitles ?? []).filter(
    (track) => track.renderMode !== "unsupported" && Boolean(track.url)
  );
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
      sourceTrackId === selectedSubtitleId && selectedSubtitleId !== "off"
        ? "showing"
        : "disabled";
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

function danmakuMargin(
  area: DanmakuArea
): [number | `${number}%`, number | `${number}%`] {
  if (area === "quarter") return [10, "75%"];
  if (area === "half") return [10, "50%"];
  return [10, "10%"];
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

function toPlaybackErrorMessage(video: HTMLVideoElement, error?: unknown): string {
  if (error instanceof Error && error.message) {
    return error.message;
  }

  switch (video.error?.code) {
    case MediaError.MEDIA_ERR_ABORTED:
      return "播放请求已中断。";
    case MediaError.MEDIA_ERR_NETWORK:
      return "本地媒体 URL 读取失败，请重新从缓存页进入播放。";
    case MediaError.MEDIA_ERR_DECODE:
      return "Electron/Chromium 无法解码当前文件的视频或音频编码。HEVC/H.265、部分 MKV/字幕封装在 Web-native 播放链路里可能不受支持。";
    case MediaError.MEDIA_ERR_SRC_NOT_SUPPORTED:
      return "当前文件格式或编码不受 HTMLVideoElement 支持。请先尝试 H.264/AAC 的 MP4/WebM 文件；HEVC/H.265 需要后续兼容性转换方案。";
    default:
      return "浏览器播放器没有接受这个本地媒体源。";
  }
}
