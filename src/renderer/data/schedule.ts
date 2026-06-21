import { TITLES } from "./artwork";
import type { TimelineItem } from "./home";

const S_TITLES = [...TITLES, "梦境图书馆", "羁绊之环"];

export type WeekDay = {
  day: string;
  en: string;
  items: TimelineItem[];
};

function it(
  time: string,
  index: number,
  ep: number,
  total: number,
  done: boolean,
  title?: string
): TimelineItem {
  return { time, index, title: title ?? S_TITLES[index], ep, total, done };
}

export const TODAY_INDEX = 4; // Friday

export const WEEK: WeekDay[] = [
  {
    day: "周一",
    en: "MON",
    items: [
      it("01:00", 5, 8, 24, true),
      it("18:30", 10, 7, 13, true),
      it("21:00", 14, 9, 24, false)
    ]
  },
  {
    day: "周二",
    en: "TUE",
    items: [
      it("00:30", 1, 4, 12, true),
      it("02:00", 6, 10, 24, true),
      it("12:00", 15, 3, 11, true),
      it("19:00", 11, 12, 24, true),
      it("23:00", 16, 6, 13, false)
    ]
  },
  {
    day: "周三",
    en: "WED",
    items: [
      it("01:30", 9, 5, 12, true),
      it("18:00", 13, 8, 24, true),
      it("22:30", 17, 7, 12, false),
      it("24:00", 12, 11, 24, false)
    ]
  },
  {
    day: "周四",
    en: "THU",
    items: [it("12:30", 4, 6, 24, true), it("20:00", 7, 9, 13, false)]
  },
  {
    day: "周五",
    en: "FRI",
    items: [
      it("02:00", 7, 6, 12, true, "创世笔记"),
      it("12:30", 3, 5, 24, true, "天空彼端的信"),
      it("19:00", 8, 9, 13, true, "千里旅人"),
      it("22:00", 0, 8, 24, false, "夏日终幕的我们"),
      it("23:30", 2, 5, 11, false, "刀锋上的舞者"),
      it("24:00", 4, 7, 24, false, "星之追忆")
    ]
  },
  {
    day: "周六",
    en: "SAT",
    items: [
      it("00:00", 5, 9, 24, true),
      it("10:00", 11, 13, 24, true),
      it("17:30", 15, 4, 11, true),
      it("22:00", 1, 5, 12, false)
    ]
  },
  { day: "周日", en: "SUN", items: [] }
];
