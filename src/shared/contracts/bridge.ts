import type { BangumiBridge } from "./bangumi";
import type { WindowControlsBridge } from "./window";

export interface MelonbangBridge {
  bangumi: BangumiBridge;
  windowControls: WindowControlsBridge;
}

declare global {
  interface Window {
    melonbang: MelonbangBridge;
  }
}
