import type { BangumiBridge } from "./bangumi";
import type { DownloadBridge } from "./download";
import type { WindowControlsBridge } from "./window";

export interface MelonbangBridge {
  bangumi: BangumiBridge;
  download: DownloadBridge;
  windowControls: WindowControlsBridge;
}

declare global {
  interface Window {
    melonbang: MelonbangBridge;
  }
}
