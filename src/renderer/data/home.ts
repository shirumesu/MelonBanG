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

export type TimelineItem = {
  time: string;
  index: number;
  subjectId?: number;
  title: string;
  ep?: number;
  total?: number;
  done: boolean;
  coverUrl?: string;
  subtitle?: string;
  badgeLabel?: string;
  actionLabel?: string;
};
