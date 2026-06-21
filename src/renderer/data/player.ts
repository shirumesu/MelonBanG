export const NOW_PLAYING = {
  title: "夏日终幕的我们",
  ep: "EP07",
  epTitle: "最后的烟火",
  source: "来源：本地缓存 1080P · melonbang BT",
  time: "12:34 / 24:00"
};

export type PlayerEpisode = {
  n: number;
  title: string;
  duration: string;
  state: "watched" | "current" | "cached" | "online" | "unaired";
};

const EP_TITLES = [
  "初夏的转校生",
  "便利店的深夜",
  "天文部的秘密",
  "雨天与伞",
  "期末考前夜",
  "海边的约定",
  "最后的烟火",
  "误会",
  "文化祭",
  "无法说出口的话"
];

export const PLAYER_EPISODES: PlayerEpisode[] = Array.from({ length: 24 }, (_, i) => {
  const n = i + 1;
  const current = n === 7;
  const watched = n < 7;
  const unaired = n > 10;
  const state: PlayerEpisode["state"] = current
    ? "current"
    : watched
      ? "watched"
      : unaired
        ? "unaired"
        : n <= 6
          ? "cached"
          : "online";
  return {
    n,
    title: EP_TITLES[(n - 1) % EP_TITLES.length],
    duration: unaired ? "未放送" : n <= 6 ? "已缓存" : "在线 1080P",
    state
  };
});

export const DANMAKU_MESSAGES = [
  "key社の世界第一可爱",
  "前方高能",
  "泪目了",
  "awsl",
  "2333333",
  "这作画也太顶了吧",
  "BGM一起鸡皮疙瘩",
  "烟火好美",
  "栞我老婆",
  "导演我谢谢你",
  "刀我可以",
  "名场面+1",
  "破防了家人们",
  "这一帧能当壁纸",
  "二刷依旧哭"
];

export const DANMAKU_COLORS = ["#fff", "#fff", "#fff", "#ffd56b", "#ff9eb5", "#86c5ff", "#9be7c4"];

export const SPEEDS = ["0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x"];
