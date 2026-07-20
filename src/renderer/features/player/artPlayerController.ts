import Artplayer from "artplayer";
import Hls from "hls.js";
import artplayerPluginDanmuku, {
  type Danmu,
  type Mode,
  type Result as DanmakuPlugin
} from "artplayer-plugin-danmuku";
import type { PlaybackSourceView, SubtitleTrackView } from "@shared/contracts/playback";
import { installSourceTimeline } from "./artPlayerTimeline";

export type ArtPlayerVideoCallbacks = {
  onPlay(video: HTMLVideoElement): void;
  onPause(video: HTMLVideoElement): void;
  onLoadedMetadata(video: HTMLVideoElement): void;
  onProgress(video: HTMLVideoElement): void;
  onSeeking(video: HTMLVideoElement): void;
  onSeekRequest(positionSeconds: number, shouldPlay: boolean): void;
  onSubtitleSelect(subtitleId: string): void;
  onDanmakuToggle(): void;
  onError(video: HTMLVideoElement, error?: unknown): void;
};

export type DanmakuConfiguration = {
  visible: boolean;
  opacity: number;
  fontFamily: string;
  fontWeight: 400 | 700;
  fontSizeCss: string;
  textShadow: string;
  speed: number;
  margin: [number | `${number}%`, number | `${number}%`];
  antiOverlap: boolean;
  synchronousPlayback: boolean;
  modes: Mode[];
  mode: Mode;
  color: string;
};

export type ArtPlayerController = {
  art: Artplayer;
  video: HTMLVideoElement;
  configureDanmaku(configuration: DanmakuConfiguration): void;
  loadDanmaku(items: Danmu[]): Promise<void>;
  updateSubtitles(tracks: SubtitleTrackView[], selectedSubtitleId: string): void;
  destroy(): void;
};

type CreateArtPlayerControllerInput = {
  container: HTMLDivElement;
  source: PlaybackSourceView;
  durationSeconds: number | null;
  subtitles: SubtitleTrackView[];
  selectedSubtitleId: string;
  volume: number;
  playbackRate: number;
  autoplay: boolean;
  callbacks: ArtPlayerVideoCallbacks;
};

export function createArtPlayerController(
  input: CreateArtPlayerControllerInput
): ArtPlayerController {
  let hls: Hls | null = null;
  let activeDanmakuIds = new Set<string>();

  const art = new Artplayer({
    container: input.container,
    url: input.source.url,
    type: input.source.kind === "hls" ? "m3u8" : "",
    lang: "zh-cn",
    theme: "#45c69b",
    volume: input.volume,
    autoplay: input.autoplay,
    playsInline: true,
    moreVideoAttr: {
      crossOrigin: "anonymous"
    },
    hotkey: true,
    gesture: true,
    backdrop: false,
    pip: true,
    setting: true,
    playbackRate: true,
    aspectRatio: true,
    fullscreen: true,
    fullscreenWeb: true,
    miniProgressBar: true,
    settings: [
      createSubtitleSetting(input.subtitles, input.selectedSubtitleId, (subtitleId) =>
        input.callbacks.onSubtitleSelect(subtitleId)
      )
    ],
    plugins: [
      artplayerPluginDanmuku({
        danmuku: [],
        emitter: true,
        visible: true,
        antiOverlap: true,
        synchronousPlayback: false,
        fontSize: 25,
        beforeVisible: (danmu) => activeDanmakuIds.has(readDanmakuId(danmu))
      })
    ],
    customType: {
      m3u8(video, url, currentArt) {
        if (!Hls.isSupported() && canPlayHlsNatively(video)) {
          video.src = url;
          return;
        }
        if (!Hls.isSupported()) {
          input.callbacks.onError(
            video,
            new Error("当前 Electron/Chromium 环境不支持 HLS 播放，HLS.js 也无法初始化。")
          );
          return;
        }

        hls?.destroy();
        hls = new Hls({
          startPosition: 0,
          lowLatencyMode: false,
          liveSyncDuration: Math.max(1, input.durationSeconds ?? 24 * 60 * 60)
        });
        currentArt.hls = hls;
        hls.loadSource(url);
        hls.attachMedia(video);
        hls.on(Hls.Events.ERROR, (_event, data) => {
          if (data.fatal) {
            input.callbacks.onError(video, new Error(formatHlsError(data)));
          }
        });
      }
    }
  });

  const video = art.video;
  let disposeTimeline = () => undefined;
  let disposeStatusNotice = () => undefined;
  try {
    const statusNotice = createPlayerStatusNotice(input.container);
    let previousMuted = video.muted;
    let previousDanmakuVisible: boolean | null = null;
    const handleVolumeChange = (): void => {
      if (video.muted === previousMuted) return;
      previousMuted = video.muted;
      statusNotice.show(video.muted ? "静音" : "关闭静音");
    };
    video.addEventListener("volumechange", handleVolumeChange);
    disposeStatusNotice = () => {
      video.removeEventListener("volumechange", handleVolumeChange);
      statusNotice.destroy();
    };

    disposeTimeline = installSourceTimeline(
      art,
      video,
      input.source,
      input.durationSeconds,
      (positionSeconds) => {
        input.callbacks.onSeekRequest(positionSeconds, video.ended || !video.paused);
      }
    );
    art.playbackRate = input.playbackRate;
    art.on("video:play", () => input.callbacks.onPlay(video));
    art.on("video:pause", () => input.callbacks.onPause(video));
    art.on("video:loadedmetadata", () => input.callbacks.onLoadedMetadata(video));
    art.on("video:progress", () => input.callbacks.onProgress(video));
    art.on("video:timeupdate", () => input.callbacks.onProgress(video));
    art.on("video:seeking", () => input.callbacks.onSeeking(video));
    art.on("video:seeked", () => input.callbacks.onProgress(video));
    art.on("video:ended", () => input.callbacks.onProgress(video));
    art.on("video:error", (error) => input.callbacks.onError(video, error));
    const disposeShortcuts = installPlayerShortcuts(art, () => input.callbacks.onDanmakuToggle());

    const danmaku = art.plugins.artplayerPluginDanmuku as DanmakuPlugin;
    let danmakuLoadVersion = 0;
    let danmakuLoadTask = Promise.resolve();
    const loadedDanmakuIds = new Set<string>();

    return {
      art,
      video,
      configureDanmaku(configuration) {
        if (
          previousDanmakuVisible !== null &&
          previousDanmakuVisible !== configuration.visible
        ) {
          statusNotice.show(configuration.visible ? "开启弹幕" : "关闭弹幕");
        }
        previousDanmakuVisible = configuration.visible;
        input.container.style.setProperty("--melon-danmaku-font-family", configuration.fontFamily);
        input.container.style.setProperty("--melon-danmaku-opacity", String(configuration.opacity));
        input.container.style.setProperty(
          "--melon-danmaku-font-weight",
          String(configuration.fontWeight)
        );
        input.container.style.setProperty("--melon-danmaku-font-size", configuration.fontSizeCss);
        input.container.style.setProperty("--melon-danmaku-text-shadow", configuration.textShadow);
        danmaku.config({
          visible: configuration.visible,
          opacity: configuration.opacity,
          speed: configuration.speed,
          margin: configuration.margin,
          antiOverlap: configuration.antiOverlap,
          synchronousPlayback: configuration.synchronousPlayback,
          modes: configuration.modes,
          mode: configuration.mode,
          color: configuration.color
        });
        if (configuration.visible) {
          danmaku.show();
        } else {
          danmaku.hide();
        }
      },
      loadDanmaku(items) {
        const version = ++danmakuLoadVersion;
        const previousActiveIds = activeDanmakuIds;
        activeDanmakuIds = new Set(items.map(readDanmakuId));
        hideInactiveDanmaku(input.container, activeDanmakuIds);
        danmakuLoadTask = danmakuLoadTask
          .catch(() => undefined)
          .then(async () => {
            if (version !== danmakuLoadVersion) return;
            const newItems = items.filter((item) => !loadedDanmakuIds.has(readDanmakuId(item)));
            if (newItems.length > 0) {
              await danmaku.load(newItems);
              for (const item of newItems) loadedDanmakuIds.add(readDanmakuId(item));
            }
            if (version !== danmakuLoadVersion) return;
            const replayItems = createCurrentScreenDanmaku(
              items,
              previousActiveIds,
              art.currentTime,
              danmaku.option.speed ?? 5
            );
            for (const item of replayItems) activeDanmakuIds.add(readDanmakuId(item));
            if (replayItems.length > 0) await danmaku.load(replayItems);
          });
        return danmakuLoadTask;
      },
      updateSubtitles(tracks, selectedSubtitleId) {
        art.setting.update(
          createSubtitleSetting(tracks, selectedSubtitleId, (subtitleId) =>
            input.callbacks.onSubtitleSelect(subtitleId)
          )
        );
      },
      destroy() {
        disposeStatusNotice();
        disposeShortcuts();
        disposeTimeline();
        destroyHls(hls);
        hls = null;
        art.destroy(false);
      }
    };
  } catch (error) {
    disposeStatusNotice();
    disposeTimeline();
    destroyHls(hls);
    hls = null;
    art.destroy(false);
    throw error;
  }
}

function createPlayerStatusNotice(container: HTMLElement): {
  show(message: string): void;
  destroy(): void;
} {
  const notice = document.createElement("div");
  notice.className = "melon-player-status-notice";
  notice.setAttribute("role", "status");
  notice.setAttribute("aria-live", "polite");
  container.append(notice);
  let hideTimer: ReturnType<typeof setTimeout> | null = null;

  return {
    show(message) {
      if (hideTimer) clearTimeout(hideTimer);
      notice.textContent = message;
      notice.dataset.visible = "true";
      hideTimer = setTimeout(() => {
        delete notice.dataset.visible;
        hideTimer = null;
      }, 1_200);
    },
    destroy() {
      if (hideTimer) clearTimeout(hideTimer);
      notice.remove();
    }
  };
}

function installPlayerShortcuts(art: Artplayer, onDanmakuToggle: () => void): () => void {
  const onKeyDown = (event: KeyboardEvent): void => {
    if (event.ctrlKey || event.metaKey || event.altKey || isEditableTarget(event.target)) return;

    let handled = true;
    if (event.code === "KeyF" && !event.repeat) {
      if (art.fullscreen || art.fullscreenWeb) {
        art.fullscreen = false;
        art.fullscreenWeb = false;
      } else {
        art.fullscreen = true;
      }
    } else if (event.code === "KeyD" && !event.repeat) {
      onDanmakuToggle();
    } else if (event.code === "KeyM" && !event.repeat) {
      art.muted = !art.muted;
    } else if (event.code === "ArrowUp") {
      art.volume = Number((art.volume + 0.1).toFixed(2));
    } else if (event.code === "ArrowDown") {
      art.volume = Number((art.volume - 0.1).toFixed(2));
    } else {
      handled = false;
    }

    if (!handled) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  };

  document.addEventListener("keydown", onKeyDown, true);
  return () => document.removeEventListener("keydown", onKeyDown, true);
}

function isEditableTarget(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName))
  );
}

function readDanmakuId(danmu: Danmu): string {
  return String((danmu as Danmu & { id?: string }).id ?? "");
}

function hideInactiveDanmaku(container: HTMLElement, activeIds: ReadonlySet<string>): void {
  for (const node of container.querySelectorAll<HTMLElement>(".art-danmuku > [data-id]")) {
    if (!activeIds.has(node.dataset.id ?? "")) node.style.visibility = "hidden";
  }
}

function createCurrentScreenDanmaku(
  items: Danmu[],
  previousActiveIds: ReadonlySet<string>,
  currentTime: number,
  durationSeconds: number
): Danmu[] {
  if (!Number.isFinite(currentTime) || currentTime <= 0) return [];
  const startTime = Math.max(0, currentTime - Math.max(1, durationSeconds));
  return items
    .filter((item) => {
      const id = readDanmakuId(item);
      const time = item.time ?? 0;
      return !previousActiveIds.has(id) && time >= startTime && time < currentTime - 0.1;
    })
    .map((item, index) => ({
      ...item,
      id: `${readDanmakuId(item)}:replay:${currentTime}:${index}`,
      time: currentTime + Math.min(0.08, index * 0.002)
    }));
}

function destroyHls(instance: Hls | null): void {
  instance?.destroy();
}

function createSubtitleSetting(
  tracks: SubtitleTrackView[],
  selectedSubtitleId: string,
  onSelect: (subtitleId: string) => void
) {
  const selectedTrack = tracks.find((track) => track.id === selectedSubtitleId);
  return {
    name: "melonbang-subtitles",
    html: "字幕",
    tooltip: selectedTrack?.label ?? (selectedSubtitleId === "off" ? "关闭" : "自动"),
    selector: [
      {
        html: "关闭",
        value: "off",
        default: selectedSubtitleId === "off"
      },
      ...tracks.map((track) => ({
        html: track.label,
        value: track.id,
        default: track.id === selectedSubtitleId
      }))
    ],
    onSelect(item: { value?: string }) {
      if (item.value) {
        onSelect(item.value);
      }
    }
  };
}

function canPlayHlsNatively(video: HTMLVideoElement): boolean {
  return Boolean(
    video.canPlayType("application/vnd.apple.mpegurl") || video.canPlayType("application/x-mpegURL")
  );
}

function formatHlsError(data: {
  type?: string;
  details?: string;
  reason?: string;
  error?: { message?: string };
  response?: { code?: number; text?: string };
}): string {
  const details = [data.details, data.reason, data.error?.message].filter(Boolean).join("：");
  const response =
    data.response?.code || data.response?.text
      ? `HTTP ${data.response.code ?? ""} ${data.response.text ?? ""}`.trim()
      : null;
  return [details || data.type, response].filter(Boolean).join("；") || "HLS 转码流加载失败。";
}
