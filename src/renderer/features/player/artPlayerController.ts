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
        fontSize: 25
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
  try {
    disposeTimeline = installSourceTimeline(
      art,
      video,
      input.source,
      input.durationSeconds,
      (positionSeconds) => {
        input.callbacks.onSeekRequest(positionSeconds, !video.paused);
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

    const danmaku = art.plugins.artplayerPluginDanmuku as DanmakuPlugin;
    let danmakuLoadVersion = 0;
    let danmakuLoadTask = Promise.resolve();
    let danmakuLayoutKey = "";

    return {
      art,
      video,
      configureDanmaku(configuration) {
        input.container.style.setProperty("--melon-danmaku-font-family", configuration.fontFamily);
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
        const nextLayoutKey = JSON.stringify([
          configuration.fontSizeCss,
          configuration.speed,
          configuration.margin,
          configuration.antiOverlap,
          configuration.synchronousPlayback,
          configuration.modes
        ]);
        if (danmakuLayoutKey && danmakuLayoutKey !== nextLayoutKey) {
          danmaku.reset();
        }
        danmakuLayoutKey = nextLayoutKey;
        if (configuration.visible) {
          danmaku.show();
        } else {
          danmaku.hide();
        }
      },
      loadDanmaku(items) {
        const version = ++danmakuLoadVersion;
        danmakuLoadTask = danmakuLoadTask
          .catch(() => undefined)
          .then(async () => {
            if (version !== danmakuLoadVersion) return;
            await danmaku.load();
            if (version !== danmakuLoadVersion) return;
            await danmaku.load(items);
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
        disposeTimeline();
        destroyHls(hls);
        hls = null;
        art.destroy(false);
      }
    };
  } catch (error) {
    disposeTimeline();
    destroyHls(hls);
    hls = null;
    art.destroy(false);
    throw error;
  }
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
