import { TITLES } from "./artwork";

export type TrackingStatus = "watching" | "wish" | "hold" | "done" | "drop";

export type TrackingCard = {
  index: number;
  title: string;
  total: number;
  current: number;
  score: string;
  myScore: string;
  updated: string;
  air: string;
  season: string;
};

export const TRACKING_TABS: { key: TrackingStatus; label: string; count: number }[] = [
  { key: "watching", label: "在看", count: 36 },
  { key: "wish", label: "想看", count: 52 },
  { key: "hold", label: "搁置", count: 9 },
  { key: "done", label: "看过", count: 240 },
  { key: "drop", label: "抛弃", count: 14 }
];

export const TRACKING_COUNT_LABEL: Record<TrackingStatus, string> = {
  watching: "36 部在看中",
  wish: "52 部想看",
  hold: "9 部已搁置",
  done: "240 部看过",
  drop: "14 部已抛弃"
};

export const TRACKING_FILTERS = ["全部", "2026 夏", "2026 春", "2025 秋", "TV", "剧场版", "OVA"];

const SEASON = [
  "2026夏",
  "2026春",
  "2025秋",
  "2026夏",
  "2025夏",
  "2026春",
  "2025秋",
  "2026夏",
  "2025冬",
  "2026春",
  "2025秋",
  "2026夏",
  "2025冬",
  "2026春",
  "2025秋",
  "2026夏"
];
const TOTALS = [12, 13, 24, 24, 11, 25];
const MY = ["9.5", "9.0", "8.5", "10", "8.0", "9.5"];
const UPDATED = ["2天前", "刚刚", "1周前", "3天前", "昨天", "5小时前"];
const AIR = ["每周五更新", "7月开播", "放送中", "已完结"];

function buildCards(count: number, seed: number): TrackingCard[] {
  return Array.from({ length: count }, (_, i) => {
    const idx = (i + seed) % TITLES.length;
    const total = TOTALS[i % TOTALS.length];
    return {
      index: idx,
      title: TITLES[idx],
      total,
      current: Math.max(1, Math.min(total - 1, 3 + i * 2)),
      score: (7.4 + (idx % 5) * 0.4).toFixed(1),
      myScore: MY[i % MY.length],
      updated: UPDATED[i % UPDATED.length],
      air: AIR[i % AIR.length],
      season: SEASON[idx]
    };
  });
}

export const TRACKING_CARDS: Record<TrackingStatus, TrackingCard[]> = {
  watching: buildCards(15, 0),
  wish: buildCards(15, 3),
  hold: buildCards(9, 0),
  done: buildCards(15, 6),
  drop: buildCards(12, 0)
};
