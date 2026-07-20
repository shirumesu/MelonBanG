import { describe, expect, it } from "vitest";
import {
  filterDanmakuItems,
  toArtPlayerDanmuku
} from "../renderer/features/player/danmaku";

describe("ArtPlayer danmaku mapping", () => {
  it("maps source timestamps and modes onto the active playback timeline", () => {
    expect(
      toArtPlayerDanmuku(
        [
          { timeSeconds: 95, text: "滚动", mode: "scroll", color: null },
          {
            timeSeconds: 100,
            text: "顶部",
            mode: "top",
            color: "#ffd56b",
            sourceId: "bilibili"
          },
          {
            timeSeconds: 110,
            text: "底部",
            mode: "bottom",
            color: "#ffffff",
            sourceId: "bahamut"
          }
        ],
        100
      )
    ).toEqual([
      {
        id: "bilibili:100000:top:#ffd56b:顶部",
        time: 0,
        text: "顶部",
        mode: 1,
        color: "#ffd56b"
      },
      {
        id: "bahamut:110000:bottom:#ffffff:底部",
        time: 10,
        text: "底部",
        mode: 2,
        color: "#ffffff"
      }
    ]);
  });

  it("drops invalid or empty comments before they reach the plugin", () => {
    expect(
      toArtPlayerDanmuku(
        [
          { timeSeconds: Number.NaN, text: "无效时间", mode: "scroll", color: null },
          { timeSeconds: 3, text: "   ", mode: "scroll", color: null },
          { timeSeconds: 4, text: "  保留并清理空格  ", mode: "scroll", color: null }
        ],
        0
      )
    ).toEqual([
      {
        id: "unknown:4000:scroll:#ffffff:保留并清理空格",
        time: 4,
        text: "保留并清理空格",
        mode: 0,
        color: "#ffffff"
      }
    ]);
  });

  it("applies the right-panel type and color blocks before loading comments", () => {
    const items = [
      { timeSeconds: 1, text: "普通滚动", mode: "scroll" as const, color: "#ffffff" },
      { timeSeconds: 2, text: "彩色滚动", mode: "scroll" as const, color: "#ffd56b" },
      { timeSeconds: 3, text: "顶部", mode: "top" as const, color: "#ffffff" }
    ];

    expect(filterDanmakuItems(items, new Set(["top", "color"]), 10)).toEqual([items[0]]);
  });
});
