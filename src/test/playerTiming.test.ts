import { describe, expect, it } from "vitest";
import {
  resolvePlaybackDuration,
  resolveSeekAction,
  toLocalTime,
  toSourceTime
} from "../shared/playerTiming";

describe("player timing", () => {
  it("keeps the probed source duration when a growing HLS manifest reports only cached segments", () => {
    expect(resolvePlaybackDuration(90.09, 4)).toBe(90.09);
  });

  it("falls back to media element duration when source probing did not return a duration", () => {
    expect(resolvePlaybackDuration(null, 1420.08)).toBe(1420.08);
  });

  it("restarts a prepared HLS stream when the absolute target is beyond generated media", () => {
    expect(
      resolveSeekAction({
        deliveryMode: "transcode",
        targetSeconds: 80,
        timelineOffsetSeconds: 0,
        seekableEndSeconds: 42
      })
    ).toEqual({ kind: "restart", sourceTimeSeconds: 80 });

    expect(
      resolveSeekAction({
        deliveryMode: "remux",
        targetSeconds: 80,
        timelineOffsetSeconds: 0,
        seekableEndSeconds: 42
      })
    ).toEqual({ kind: "restart", sourceTimeSeconds: 80 });

    expect(
      resolveSeekAction({
        deliveryMode: "transcode",
        targetSeconds: 85,
        timelineOffsetSeconds: 80,
        seekableEndSeconds: 10
      })
    ).toEqual({ kind: "local", localTimeSeconds: 5 });
  });

  it("maps local HLS time back to the absolute source timeline", () => {
    expect(toSourceTime(2.5, 80)).toBe(82.5);
    expect(toLocalTime(82.5, 80)).toBe(2.5);
  });
});
