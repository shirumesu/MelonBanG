import type { BangumiBridge } from "./bangumi";
import type { DownloadBridge } from "./download";
import type { PlaybackBridge } from "./playback";
import type { WindowControlsBridge } from "./window";

export interface MelonbangBridge {
  bangumi: BangumiBridge;
  download: DownloadBridge;
  playback: PlaybackBridge;
  windowControls: WindowControlsBridge;
}

declare global {
  interface Window {
    melonbang: MelonbangBridge;
  }
}
