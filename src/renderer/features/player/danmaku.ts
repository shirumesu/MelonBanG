import type { Danmu, Mode } from "artplayer-plugin-danmuku";
import type { DanmakuItemView } from "@shared/contracts/playback";

const modeMap: Record<DanmakuItemView["mode"], Mode> = {
  scroll: 0,
  top: 1,
  bottom: 2
};

export function toArtPlayerDanmuku(
  items: DanmakuItemView[],
  timelineOffsetSeconds: number
): Danmu[] {
  const offset = Number.isFinite(timelineOffsetSeconds) ? Math.max(0, timelineOffsetSeconds) : 0;

  return items.flatMap((item) => {
    const text = item.text.trim();
    const time = item.timeSeconds - offset;
    if (!text || !Number.isFinite(time) || time < 0) {
      return [];
    }

    return [
      {
        text,
        time,
        mode: modeMap[item.mode],
        color: item.color ?? "#ffffff"
      }
    ];
  });
}

export function toArtPlayerDanmakuMode(mode: DanmakuItemView["mode"]): Mode {
  return modeMap[mode];
}

export function filterDanmakuItems(
  items: DanmakuItemView[],
  blockedTypes: ReadonlySet<string>,
  density: number
): DanmakuItemView[] {
  const threshold = Math.max(1, Math.min(10, Math.round(density)));
  return items.filter((item) => {
    if (blockedTypes.has(item.mode)) return false;
    if (blockedTypes.has("color") && item.color && item.color.toLowerCase() !== "#ffffff") {
      return false;
    }
    return threshold === 10 || stableBucket(`${item.timeSeconds}:${item.text}`) < threshold;
  });
}

function stableBucket(value: string): number {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return hash % 10;
}
