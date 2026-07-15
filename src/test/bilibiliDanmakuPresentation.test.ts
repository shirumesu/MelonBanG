import { describe, expect, it } from "vitest";
import {
  bilibiliDanmakuDefaults,
  resolveBilibiliDanmakuPresentation
} from "../renderer/features/player/bilibiliDanmakuPresentation";

describe("Bilibili-style danmaku presentation", () => {
  it("translates the Bilibili desktop defaults into renderer behavior", () => {
    expect(resolveBilibiliDanmakuPresentation(bilibiliDanmakuDefaults)).toEqual({
      opacity: 0.8,
      fontFamily: 'SimHei, "Microsoft JhengHei", Arial, Helvetica, sans-serif',
      fontWeight: 700,
      fontSizeCss: "clamp(12px, 2.6205cqw, 64px)",
      textShadow:
        "rgb(0, 0, 0) 1px 0 1px, rgb(0, 0, 0) 0 1px 1px, rgb(0, 0, 0) 0 -1px 1px, rgb(0, 0, 0) -1px 0 1px",
      speedSeconds: 8.8,
      margin: [10, "50%"],
      densityThreshold: 10,
      antiOverlap: true,
      synchronousPlayback: false
    });
  });

  it("maps the extended area and density choices without discarding overlap-mode comments", () => {
    const presentation = resolveBilibiliDanmakuPresentation({
      ...bilibiliDanmakuDefaults,
      area: "threeQuarter",
      density: "overlap",
      speed: "fastest"
    });

    expect(presentation.margin).toEqual([10, "25%"]);
    expect(presentation.densityThreshold).toBe(10);
    expect(presentation.antiOverlap).toBe(false);
    expect(presentation.speedSeconds).toBe(5.5);
  });

  it("supports fixed-size text and the other Bilibili border styles", () => {
    const presentation = resolveBilibiliDanmakuPresentation({
      ...bilibiliDanmakuDefaults,
      fontScalePercent: 120,
      scaleWithPlayer: false,
      bold: false,
      border: "shadow45"
    });

    expect(presentation.fontSizeCss).toBe("30px");
    expect(presentation.fontWeight).toBe(400);
    expect(presentation.textShadow).toBe("rgb(0, 0, 0) 2px 2px 1px");
  });
});
