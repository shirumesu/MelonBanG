import { describe, expect, it, vi } from "vitest";
import type { PlaybackSourceView } from "../shared/contracts/playback";
import {
  installSourceTimeline,
  type ArtPlayerTimelineTarget,
  type MediaTimelineSource
} from "../renderer/features/player/artPlayerTimeline";

const transcodedSource: PlaybackSourceView = {
  kind: "hls",
  deliveryMode: "transcode",
  timelineOffsetSeconds: 100,
  url: "http://127.0.0.1/transcode/session/token/index.m3u8",
  mimeType: "application/vnd.apple.mpegurl",
  title: "fixture.mkv"
};

describe("ArtPlayer source timeline", () => {
  it("renders source duration, played progress, and buffered progress without redefining ArtPlayer properties", () => {
    const art = createArtPlayer();
    const video = createVideo({ currentTime: 5, seekableEnd: 20, bufferedEnd: 15 });

    expect(() => installSourceTimeline(art, video, transcodedSource, 1_200, vi.fn())).not.toThrow();

    expect(art.duration).toBe(0);
    expect(art.timeControl.textContent).toBe("01:45 / 20:00");
    expect(art.bars).toEqual([
      ["played", 105 / 1_200],
      ["loaded", 115 / 1_200]
    ]);

    video.currentTime = 9;
    art.fire("video:timeupdate");
    expect(art.timeControl.textContent).toBe("01:49 / 20:00");
    expect(art.bars.slice(-2)).toEqual([
      ["played", 109 / 1_200],
      ["loaded", 115 / 1_200]
    ]);
  });

  it("seeks locally inside generated media and requests a restart beyond it", () => {
    const art = createArtPlayer();
    const video = createVideo({ currentTime: 5, seekableEnd: 20, bufferedEnd: 15 });
    const requestSeek = vi.fn();

    installSourceTimeline(art, video, transcodedSource, 1_200, requestSeek);
    art.clickProgress(112 / 1_200);
    expect(video.currentTime).toBe(12);
    expect(requestSeek).not.toHaveBeenCalled();

    art.clickProgress(800 / 1_200);
    expect(requestSeek).toHaveBeenCalledOnce();
    expect(requestSeek).toHaveBeenCalledWith(800);
  });

  it("requests a restart when the target lies before the current stream offset", () => {
    const art = createArtPlayer();
    const video = createVideo({ currentTime: 5, seekableEnd: 20, bufferedEnd: 15 });
    const requestSeek = vi.fn();

    installSourceTimeline(art, video, transcodedSource, 1_200, requestSeek);
    art.clickProgress(40 / 1_200);

    expect(requestSeek).toHaveBeenCalledOnce();
    expect(requestSeek).toHaveBeenCalledWith(40);
    expect(video.currentTime).toBe(5);
  });

  it("routes drags to the coordinator and pins the target while a restart is pending", () => {
    const art = createArtPlayer();
    const video = createVideo({ currentTime: 5, seekableEnd: 20, bufferedEnd: 15 });
    let pending = false;
    const requestSeek = vi.fn<(positionSeconds: number) => void>(() => {
      pending = true;
    });

    installSourceTimeline(art, video, transcodedSource, 1_200, requestSeek, () => pending);
    art.clickProgress(800 / 1_200);
    expect(requestSeek).toHaveBeenCalledWith(800);

    art.fire("video:timeupdate");
    expect(art.bars.at(-2)).toEqual(["played", 800 / 1_200]);

    art.clickProgress(110 / 1_200);
    expect(requestSeek).toHaveBeenCalledTimes(2);
    expect(requestSeek.mock.lastCall?.[0]).toBeCloseTo(110, 6);
    expect(video.currentTime).toBe(5);

    pending = false;
    art.fire("video:timeupdate");
    expect(art.bars.at(-2)).toEqual(["played", 105 / 1_200]);
  });

  it("steps along the source timeline for keyboard seeks", () => {
    const art = createArtPlayer();
    const video = createVideo({ currentTime: 5, seekableEnd: 20, bufferedEnd: 15 });
    const requestSeek = vi.fn();

    const timeline = installSourceTimeline(art, video, transcodedSource, 1_200, requestSeek);
    expect(timeline.seekBy(5)).toBe(true);
    expect(video.currentTime).toBe(10);
    expect(requestSeek).not.toHaveBeenCalled();

    expect(timeline.seekBy(-30)).toBe(true);
    expect(requestSeek).toHaveBeenCalledOnce();
    expect(requestSeek).toHaveBeenCalledWith(80);

    const detached = installSourceTimeline(art, video, transcodedSource, null, vi.fn());
    expect(detached.seekBy(5)).toBe(false);
  });

  it("previews a progress drag and seeks once when the pointer is released", () => {
    const art = createArtPlayer();
    const video = createVideo({ currentTime: 5, seekableEnd: 20, bufferedEnd: 15 });
    const requestSeek = vi.fn();

    installSourceTimeline(art, video, transcodedSource, 1_200, requestSeek);
    art.beginProgressDrag(105 / 1_200);
    art.moveProgressDrag(800 / 1_200);

    expect(art.bars.at(-1)).toEqual(["played", 800 / 1_200]);
    expect(art.progressTip.textContent).toBe("13:20");
    expect(requestSeek).not.toHaveBeenCalled();

    art.endProgressDrag(800 / 1_200);
    art.clickProgress(800 / 1_200);

    expect(requestSeek).toHaveBeenCalledOnce();
    expect(requestSeek).toHaveBeenCalledWith(800);
  });
});

function createArtPlayer(): ArtPlayerTimelineTarget & {
  duration: number;
  bars: Array<["played" | "loaded", number]>;
  timeControl: { textContent: string };
  progressTip: { textContent: string };
  fire(event: string): void;
  clickProgress(ratio: number): void;
  beginProgressDrag(ratio: number): void;
  moveProgressDrag(ratio: number): void;
  endProgressDrag(ratio: number): void;
} {
  type TestPointerEvent = {
    button: number;
    clientX: number;
    pointerId: number;
    preventDefault(): void;
    stopImmediatePropagation(): void;
  };
  const playerListeners = new Map<string, Set<() => void>>();
  const progressListeners = new Map<string, Set<(event: TestPointerEvent) => void>>();
  const timeControl = { textContent: "00:00 / 00:00" };
  const progressTip = { textContent: "00:00" };
  const bars: Array<["played" | "loaded", number]> = [];
  const art = {
    template: {
      $player: {
        querySelector: (selector: string) => (selector === ".art-control-time" ? timeControl : null)
      },
      $progress: {
        querySelector: (selector: string) =>
          selector === ".art-progress-tip" ? progressTip : null,
        getBoundingClientRect: () => ({ left: 0, width: 1_000 }),
        addEventListener: (event: string, listener: (event: TestPointerEvent) => void) => {
          const listeners = progressListeners.get(event) ?? new Set();
          listeners.add(listener);
          progressListeners.set(event, listeners);
        },
        removeEventListener: (event: string, listener: (event: TestPointerEvent) => void) => {
          progressListeners.get(event)?.delete(listener);
        },
        setPointerCapture: () => undefined,
        releasePointerCapture: () => undefined
      }
    },
    emit: (_event: "setBar", type: "played" | "loaded", ratio: number) => {
      bars.push([type, ratio]);
    },
    on: (event: string, listener: () => void) => {
      const listeners = playerListeners.get(event) ?? new Set();
      listeners.add(listener);
      playerListeners.set(event, listeners);
    },
    off: (event: string, listener: () => void) => {
      playerListeners.get(event)?.delete(listener);
    },
    bars,
    timeControl,
    progressTip,
    fire(event: string) {
      playerListeners.get(event)?.forEach((listener) => listener());
    },
    clickProgress(ratio: number) {
      const event = {
        button: 0,
        clientX: ratio * 1_000,
        pointerId: 1,
        preventDefault: () => undefined,
        stopImmediatePropagation: () => undefined
      };
      progressListeners.get("click")?.forEach((listener) => listener(event));
    },
    beginProgressDrag(ratio: number) {
      dispatchProgress("pointerdown", ratio);
    },
    moveProgressDrag(ratio: number) {
      dispatchProgress("pointermove", ratio);
    },
    endProgressDrag(ratio: number) {
      dispatchProgress("pointerup", ratio);
    }
  };

  function dispatchProgress(eventName: string, ratio: number): void {
    const event = {
      button: 0,
      clientX: ratio * 1_000,
      pointerId: 1,
      preventDefault: () => undefined,
      stopImmediatePropagation: () => undefined
    };
    progressListeners.get(eventName)?.forEach((listener) => listener(event));
  }

  Object.defineProperties(art, {
    duration: {
      configurable: false,
      get: () => 0
    },
    currentTime: {
      configurable: false,
      get: () => 0,
      set: () => undefined
    },
    loadedTime: {
      configurable: false,
      get: () => 0
    },
    loaded: {
      configurable: false,
      get: () => 0
    }
  });

  return art as unknown as ReturnType<typeof createArtPlayer>;
}

function createVideo(input: {
  currentTime: number;
  seekableEnd: number;
  bufferedEnd: number;
}): MediaTimelineSource {
  return {
    currentTime: input.currentTime,
    seekable: createTimeRanges(input.seekableEnd),
    buffered: createTimeRanges(input.bufferedEnd)
  };
}

function createTimeRanges(endSeconds: number) {
  return {
    length: 1,
    start: () => 0,
    end: () => endSeconds
  };
}
