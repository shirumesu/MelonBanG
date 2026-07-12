import Artplayer from "artplayer";
import Hls from "hls.js";
import artplayerPluginDanmuku, {
  type Danmu,
  type Mode,
  type Result as DanmakuPlugin
} from "artplayer-plugin-danmuku";
import type { PlaybackSourceView } from "@shared/contracts/playback";

export type ArtPlayerVideoCallbacks = {
  onPlay(video: HTMLVideoElement): void;
  onPause(video: HTMLVideoElement): void;
  onLoadedMetadata(video: HTMLVideoElement): void;
  onProgress(video: HTMLVideoElement): void;
  onSeeking(video: HTMLVideoElement): void;
  onError(video: HTMLVideoElement, error?: unknown): void;
};

export type DanmakuConfiguration = {
  visible: boolean;
  opacity: number;
  fontSize: number;
  speed: number;
  margin: [number | `${number}%`, number | `${number}%`];
  modes: Mode[];
  mode: Mode;
  color: string;
};

export type ArtPlayerController = {
  art: Artplayer;
  video: HTMLVideoElement;
  configureDanmaku(configuration: DanmakuConfiguration): void;
  loadDanmaku(items: Danmu[]): Promise<void>;
  destroy(): void;
};

type CreateArtPlayerControllerInput = {
  container: HTMLDivElement;
  source: PlaybackSourceView;
  danmuku: Danmu[];
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
    plugins: [
      artplayerPluginDanmuku({
        danmuku: input.danmuku,
        emitter: true,
        visible: true,
        antiOverlap: true,
        synchronousPlayback: true
      })
    ],
    customType: {
      m3u8(video, url, currentArt) {
        if (canPlayHlsNatively(video)) {
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
        hls = new Hls();
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

  return {
    art,
    video,
    configureDanmaku(configuration) {
      danmaku.config({
        ...danmaku.option,
        visible: configuration.visible,
        opacity: configuration.opacity,
        fontSize: configuration.fontSize,
        speed: configuration.speed,
        margin: configuration.margin,
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
    async loadDanmaku(items) {
      await danmaku.load(items);
    },
    destroy() {
      hls?.destroy();
      hls = null;
      art.destroy(false);
    }
  };
}

function canPlayHlsNatively(video: HTMLVideoElement): boolean {
  return Boolean(
    video.canPlayType("application/vnd.apple.mpegurl") ||
      video.canPlayType("application/x-mpegURL")
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
