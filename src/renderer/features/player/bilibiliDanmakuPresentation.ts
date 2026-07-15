export type BilibiliDanmakuArea = "quarter" | "half" | "threeQuarter" | "full";
export type BilibiliDanmakuBorder = "heavy" | "outline" | "shadow45";
export type BilibiliDanmakuDensity = "normal" | "more" | "overlap";
export type BilibiliDanmakuFont =
  | "simhei"
  | "simsun"
  | "nsimsun"
  | "fangsong"
  | "microsoftYahei"
  | "microsoftYaheiLight"
  | "notoSansDemiLight"
  | "notoSansRegular";
export type BilibiliDanmakuSpeed = "slowest" | "slow" | "normal" | "fast" | "fastest";

export type BilibiliDanmakuSettings = {
  opacityPercent: number;
  area: BilibiliDanmakuArea;
  fontScalePercent: number;
  speed: BilibiliDanmakuSpeed;
  density: BilibiliDanmakuDensity;
  font: BilibiliDanmakuFont;
  bold: boolean;
  border: BilibiliDanmakuBorder;
  scaleWithPlayer: boolean;
  speedSync: boolean;
};

export const bilibiliDanmakuDefaults: BilibiliDanmakuSettings = {
  opacityPercent: 80,
  area: "half",
  fontScalePercent: 100,
  speed: "normal",
  density: "normal",
  font: "simhei",
  bold: true,
  border: "heavy",
  scaleWithPlayer: true,
  speedSync: false
};

export const bilibiliDanmakuFontOptions: Array<{
  value: BilibiliDanmakuFont;
  label: string;
}> = [
  { value: "simhei", label: "黑体" },
  { value: "simsun", label: "宋体" },
  { value: "nsimsun", label: "新宋体" },
  { value: "fangsong", label: "仿宋" },
  { value: "microsoftYahei", label: "微软雅黑" },
  { value: "microsoftYaheiLight", label: "微软雅黑 Light" },
  { value: "notoSansDemiLight", label: "Noto Sans DemiLight" },
  { value: "notoSansRegular", label: "Noto Sans Regular" }
];

export const bilibiliDanmakuSpeedOptions: Array<{
  value: BilibiliDanmakuSpeed;
  label: string;
}> = [
  { value: "slowest", label: "极慢" },
  { value: "slow", label: "较慢" },
  { value: "normal", label: "适中" },
  { value: "fast", label: "较快" },
  { value: "fastest", label: "极快" }
];

export type BilibiliDanmakuPresentation = {
  opacity: number;
  fontFamily: string;
  fontWeight: 400 | 700;
  fontSizeCss: string;
  textShadow: string;
  speedSeconds: number;
  margin: [number | `${number}%`, number | `${number}%`];
  densityThreshold: number;
  antiOverlap: boolean;
  synchronousPlayback: boolean;
};

const fontFamilies: Record<BilibiliDanmakuFont, string> = {
  simhei: 'SimHei, "Microsoft JhengHei", Arial, Helvetica, sans-serif',
  simsun: 'SimSun, "Microsoft JhengHei", Arial, Helvetica, sans-serif',
  nsimsun: 'NSimSun, "Microsoft JhengHei", Arial, Helvetica, sans-serif',
  fangsong: 'FangSong, "Microsoft JhengHei", Arial, Helvetica, sans-serif',
  microsoftYahei: '"Microsoft YaHei", Arial, Helvetica, sans-serif',
  microsoftYaheiLight: '"Microsoft YaHei Light", "Microsoft YaHei", sans-serif',
  notoSansDemiLight: '"Noto Sans CJK SC DemiLight", "Microsoft YaHei", sans-serif',
  notoSansRegular: '"Noto Sans CJK SC", "Microsoft YaHei", sans-serif'
};

const speedSeconds: Record<BilibiliDanmakuSpeed, number> = {
  slowest: 10,
  slow: 9.5,
  normal: 8.8,
  fast: 7,
  fastest: 5.5
};

const textShadows: Record<BilibiliDanmakuBorder, string> = {
  heavy:
    "rgb(0, 0, 0) 1px 0 1px, rgb(0, 0, 0) 0 1px 1px, rgb(0, 0, 0) 0 -1px 1px, rgb(0, 0, 0) -1px 0 1px",
  outline:
    "rgb(0, 0, 0) 1px 0 0, rgb(0, 0, 0) -1px 0 0, rgb(0, 0, 0) 0 1px 0, rgb(0, 0, 0) 0 -1px 0",
  shadow45: "rgb(0, 0, 0) 2px 2px 1px"
};

export function resolveBilibiliDanmakuPresentation(
  settings: BilibiliDanmakuSettings
): BilibiliDanmakuPresentation {
  const fontScale = clamp(settings.fontScalePercent, 40, 160) / 100;
  return {
    opacity: clamp(settings.opacityPercent, 10, 100) / 100,
    fontFamily: fontFamilies[settings.font],
    fontWeight: settings.bold ? 700 : 400,
    fontSizeCss: settings.scaleWithPlayer
      ? `clamp(12px, ${formatNumber(2.6205 * fontScale)}cqw, 64px)`
      : `${formatNumber(25 * fontScale)}px`,
    textShadow: textShadows[settings.border],
    speedSeconds: speedSeconds[settings.speed],
    margin: resolveMargin(settings.area),
    densityThreshold: settings.density === "more" ? 9 : 10,
    antiOverlap: settings.density === "normal",
    synchronousPlayback: settings.speedSync
  };
}

function resolveMargin(area: BilibiliDanmakuArea): [number | `${number}%`, number | `${number}%`] {
  if (area === "quarter") return [10, "75%"];
  if (area === "half") return [10, "50%"];
  if (area === "threeQuarter") return [10, "25%"];
  return [10, 10];
}

function clamp(value: number, minimum: number, maximum: number): number {
  if (!Number.isFinite(value)) return minimum;
  return Math.min(maximum, Math.max(minimum, value));
}

function formatNumber(value: number): string {
  return Number(value.toFixed(4)).toString();
}
