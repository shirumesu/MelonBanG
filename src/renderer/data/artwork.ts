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

export function artGradient(index: number): string {
  const pair = GRADIENTS[index % GRADIENTS.length];
  return `linear-gradient(135deg, ${pair[0]}, ${pair[1]})`;
}

export function artKanji(index: number): string {
  return KANJI[index % KANJI.length];
}
