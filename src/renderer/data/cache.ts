export type DownloadTask = {
  index: number;
  kanji: string;
  title: string;
  ep: string;
  quality: string;
  pct: number;
  speed: string;
  done: string;
  total: string;
  eta: string;
  up: number;
  peer: number;
  tag?: string;
};

export type QueuedTask = {
  index: number;
  kanji: string;
  title: string;
  ep: string;
  quality: string;
  size: string;
  position: number;
};

export type CompletedItem = {
  index: number;
  kanji: string;
  title: string;
  episodes: number;
  size: string;
  score: string;
  quality: string;
};

export const STORAGE = {
  pct: 48,
  used: "48.2 GB",
  total: "100 GB",
  speed: "9.1",
  downloading: 3,
  queued: 2
};

export const CACHE_TABS = [
  { label: "⬇️ 正在下载", count: "3" },
  { label: "⏳ 排队中", count: "2" },
  { label: "✅ 已完成", count: "24" },
  { label: "📂 全部", count: "" }
];

export const DOWNLOADING: DownloadTask[] = [
  {
    index: 0,
    kanji: "夏",
    title: "夏日终幕的我们",
    ep: "08",
    quality: "1080P",
    pct: 62,
    speed: "6.4",
    done: "612 MB",
    total: "1.4 GB",
    eta: "2分11秒",
    up: 12,
    peer: 48
  },
  {
    index: 1,
    kanji: "刃",
    title: "刀锋上的舞者",
    ep: "05",
    quality: "1080P",
    pct: 12,
    speed: "2.1",
    done: "180 MB",
    total: "1.5 GB",
    eta: "9分40秒",
    up: 3,
    peer: 21
  },
  {
    index: 2,
    kanji: "星",
    title: "星之追忆",
    ep: "07",
    quality: "720P",
    pct: 88,
    speed: "0.0",
    done: "520 MB",
    total: "590 MB",
    eta: "即将完成",
    up: 0,
    peer: 30,
    tag: "校验中"
  }
];

export const QUEUED: QueuedTask[] = [
  { index: 3, kanji: "創", title: "创世笔记", ep: "06", quality: "1080P", size: "1.3 GB", position: 1 },
  { index: 4, kanji: "旅", title: "千里旅人", ep: "09", quality: "1080P", size: "1.4 GB", position: 2 }
];

export const COMPLETED: CompletedItem[] = [
  { index: 0, kanji: "夏", title: "光与影的协奏", episodes: 12, size: "4.2 GB", score: "8.0", quality: "1080P" },
  { index: 1, kanji: "刃", title: "绯色的契约", episodes: 13, size: "3.8 GB", score: "8.3", quality: "720P" },
  { index: 2, kanji: "星", title: "蒼之纪元", episodes: 24, size: "9.1 GB", score: "8.6", quality: "1080P" },
  { index: 3, kanji: "創", title: "奏响的青春", episodes: 11, size: "3.1 GB", score: "8.0", quality: "720P" },
  { index: 4, kanji: "旅", title: "幻夜咖啡馆", episodes: 12, size: "4.0 GB", score: "8.3", quality: "1080P" },
  { index: 5, kanji: "奏", title: "逐风之翼", episodes: 24, size: "8.6 GB", score: "8.6", quality: "720P" }
];
