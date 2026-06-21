/**
 * Shared placeholder artwork helpers. The DESIGN prototype renders every
 * cover as a deterministic gradient + kanji glyph (no real images), keyed by
 * an index. These helpers reproduce that exact palette so React posters match
 * the prototype pixel-for-pixel.
 */

export const GRADIENTS: ReadonlyArray<readonly [string, string]> = [
  ["#7bd0c1", "#3b82c4"],
  ["#f7a8b8", "#9b6ad8"],
  ["#ffd56b", "#ff7a5b"],
  ["#9be7c4", "#3aa17e"],
  ["#a9c7ff", "#6a6ae0"],
  ["#ffb3c7", "#ff6b9d"],
  ["#c0a8ff", "#7d5fe0"],
  ["#8fe3d6", "#3aa1a8"],
  ["#ffd0a8", "#ff9a5b"],
  ["#b8e986", "#5aa84a"],
  ["#ff9eb5", "#c25b8e"],
  ["#86c5ff", "#3f74c4"]
];

export const KANJI = [
  "夏",
  "恋",
  "刃",
  "空",
  "星",
  "光",
  "緋",
  "創",
  "旅",
  "幻",
  "蒼",
  "奏",
  "焰",
  "音",
  "翼",
  "零",
  "夢",
  "絆"
] as const;

export const TITLES = [
  "夏日终幕的我们",
  "缔造神话的少女们",
  "刀锋上的舞者",
  "天空彼端的信",
  "星之追忆",
  "光与影的协奏",
  "绯色的契约",
  "创世笔记",
  "千里旅人",
  "幻夜咖啡馆",
  "蒼之纪元",
  "奏响的青春",
  "焰之魔导书",
  "无声的旋律",
  "逐风之翼",
  "归零的世界"
] as const;

export function artGradient(index: number): string {
  const pair = GRADIENTS[index % GRADIENTS.length];
  return `linear-gradient(135deg, ${pair[0]}, ${pair[1]})`;
}

export function artKanji(index: number): string {
  return KANJI[index % KANJI.length];
}

export function artTitle(index: number): string {
  return TITLES[index % TITLES.length];
}
