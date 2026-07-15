import fallbackFontUrl from "@fontsource/m-plus-rounded-1c/files/m-plus-rounded-1c-japanese-400-normal.woff2?url";
import workerUrl from "jassub/dist/worker/worker.js?worker&url";
import modernWasmUrl from "jassub/dist/wasm/jassub-worker-modern.wasm?url";
import wasmUrl from "jassub/dist/wasm/jassub-worker.wasm?url";

export type AssSubtitleRendererHandle = {
  destroy(): Promise<void>;
};

export async function createAssSubtitleRenderer(input: {
  video: HTMLVideoElement;
  subtitleUrl: string;
  fontUrls: string[];
  timelineOffsetSeconds: number;
}): Promise<AssSubtitleRendererHandle> {
  const { default: JASSUB } = await import("jassub");
  const renderer = new JASSUB({
    video: input.video,
    subUrl: input.subtitleUrl,
    fonts: input.fontUrls,
    workerUrl,
    wasmUrl,
    modernWasmUrl,
    timeOffset: input.timelineOffsetSeconds,
    availableFonts: {
      "M PLUS Rounded 1c": fallbackFontUrl
    },
    defaultFont: "M PLUS Rounded 1c",
    queryFonts: false,
    prescaleHeightLimit: 1080
  });
  renderer._canvas.style.zIndex = "20";
  await renderer.ready;
  await renderer.resize(true);
  return renderer;
}
