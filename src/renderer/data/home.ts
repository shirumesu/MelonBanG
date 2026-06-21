export type Season = "summer" | "winter" | "spring" | "fall";

export type HeroSlide = {
  kanji: string;
  badge: string;
  season: Season;
  seasonLabel: string;
  kind: string;
  title: string;
  ep: string;
  desc: string;
  background: string;
};

export const HERO_SLIDES: HeroSlide[] = [
  {
    kanji: "夏",
    badge: "🔥 本季热度 #1",
    season: "summer",
    seasonLabel: "2026 SUMMER",
    kind: "原创 · TV",
    title: "夏日终幕的我们",
    ep: "EP07",
    desc: "当蝉鸣盖过心跳，三个少女在最后一个夏天许下不会褪色的约定——一部关于离别与重逢的青春群像剧。",
    background:
      "radial-gradient(130% 130% at 86% 6%,rgba(255,255,255,.20),transparent 44%),linear-gradient(115deg,#0f7d5e,#1aa183 42%,#3f7fd8)"
  },
  {
    kanji: "神",
    badge: "🆕 本周新上架",
    season: "summer",
    seasonLabel: "2026 SUMMER",
    kind: "漫画改 · TV",
    title: "缔造神话的少女们",
    ep: "EP03",
    desc: "传说的尽头，是被遗忘的名字。少女们以歌声为剑，在崩坏的神域里重写属于人类的神话。",
    background:
      "radial-gradient(130% 130% at 86% 6%,rgba(255,255,255,.16),transparent 44%),linear-gradient(115deg,#a8336e,#d65189 44%,#8a5fd8)"
  },
  {
    kanji: "刃",
    badge: "⭐ 高分推荐",
    season: "summer",
    seasonLabel: "2026 SUMMER",
    kind: "小说改 · TV",
    title: "刀锋上的舞者",
    ep: "EP05",
    desc: "每一次出鞘都是一次告别。流浪剑客与失忆少女的旅途，在刀光与樱雨之间缓缓展开。",
    background:
      "radial-gradient(130% 130% at 86% 6%,rgba(255,255,255,.16),transparent 44%),linear-gradient(115deg,#c0641d,#ef7f43 44%,#ff5f7a)"
  }
];

export type ContinueItem = {
  index: number;
  title: string;
  score: string;
  currentEp: number;
  progress: number;
};

const continueSeed = [
  { currentEp: 7, progress: 62 },
  { currentEp: 3, progress: 24 },
  { currentEp: 11, progress: 84 },
  { currentEp: 5, progress: 20 },
  { currentEp: 9, progress: 38 },
  { currentEp: 2, progress: 12 },
  { currentEp: 16, progress: 67 },
  { currentEp: 8, progress: 44 }
];

export const CONTINUE_ITEMS: ContinueItem[] = continueSeed.map((entry, index) => ({
  index,
  title: ["夏日终幕的我们", "缔造神话的少女们", "刀锋上的舞者", "天空彼端的信", "星之追忆", "光与影的协奏", "绯色的契约", "创世笔记"][index]!,
  score: (8 + (index % 3) * 0.3).toFixed(1),
  currentEp: entry.currentEp,
  progress: entry.progress
}));

export type TimelineItem = {
  time: string;
  index: number;
  title: string;
  ep: number;
  total: number;
  done: boolean;
};

export const TODAY_ITEMS: TimelineItem[] = [
  { time: "02:00", index: 7, title: "创世笔记", ep: 6, total: 12, done: true },
  { time: "12:30", index: 3, title: "天空彼端的信", ep: 5, total: 24, done: true },
  { time: "19:00", index: 8, title: "千里旅人", ep: 9, total: 13, done: true },
  { time: "22:00", index: 0, title: "夏日终幕的我们", ep: 8, total: 24, done: false },
  { time: "23:30", index: 2, title: "刀锋上的舞者", ep: 5, total: 11, done: false },
  { time: "24:00", index: 4, title: "星之追忆", ep: 7, total: 24, done: false }
];

export const TODAY_SUBTITLE = `周五 · ${TODAY_ITEMS.length} 部有新集`;
