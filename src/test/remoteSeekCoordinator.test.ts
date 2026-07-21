import { describe, expect, it, vi } from "vitest";
import type { PlaybackSessionView, SeekPlaybackInput } from "../shared/contracts/playback";
import { createRemoteSeekCoordinator } from "../renderer/features/player/remoteSeekCoordinator";

describe("remote seek coordinator", () => {
  it("finishes the active restart and then applies only the latest queued target", async () => {
    const firstSeek = deferred<PlaybackSessionView>();
    const applied: number[] = [];
    const requestedPositions: number[] = [];
    const seek = (input: SeekPlaybackInput): Promise<PlaybackSessionView> => {
      requestedPositions.push(input.positionSeconds);
      return requestedPositions.length === 1
        ? firstSeek.promise
        : Promise.resolve(createSession(input.positionSeconds));
    };
    const coordinator = createRemoteSeekCoordinator({
      seek,
      onSession: (session: PlaybackSessionView) =>
        applied.push(session.source?.timelineOffsetSeconds ?? -1),
      onError: vi.fn(),
      onPlaybackIntent: vi.fn()
    });

    const idle = coordinator.request({
      sessionId: "session-1",
      positionSeconds: 700,
      shouldPlay: true
    });
    void coordinator.request({
      sessionId: "session-1",
      positionSeconds: 400,
      shouldPlay: true
    });

    expect(coordinator.shouldAcceptSession(createSession(700))).toBe(false);
    firstSeek.resolve(createSession(700));
    await idle;

    expect(requestedPositions).toEqual([700, 400]);
    expect(applied).toEqual([400]);
    expect(coordinator.isSeeking()).toBe(false);
  });

  it("coalesces repeated pending drags to the last requested position", async () => {
    const firstSeek = deferred<PlaybackSessionView>();
    const requestedPositions: number[] = [];
    const seek = (input: SeekPlaybackInput): Promise<PlaybackSessionView> => {
      requestedPositions.push(input.positionSeconds);
      return requestedPositions.length === 1
        ? firstSeek.promise
        : Promise.resolve(createSession(input.positionSeconds));
    };
    const applied: PlaybackSessionView[] = [];
    const coordinator = createRemoteSeekCoordinator({
      seek,
      onSession: (session: PlaybackSessionView) => applied.push(session),
      onError: vi.fn(),
      onPlaybackIntent: vi.fn()
    });

    const idle = coordinator.request({ sessionId: "session-1", positionSeconds: 700, shouldPlay: true });
    void coordinator.request({ sessionId: "session-1", positionSeconds: 500, shouldPlay: true });
    void coordinator.request({ sessionId: "session-1", positionSeconds: 400, shouldPlay: false });
    firstSeek.resolve(createSession(700));
    await idle;

    expect(requestedPositions).toEqual([700, 400]);
    expect(applied).toEqual([createSession(400)]);
  });

  it("accepts the session produced by a tail-clamped seek target", () => {
    const coordinator = createRemoteSeekCoordinator({
      seek: () => new Promise<PlaybackSessionView>(() => undefined),
      onSession: vi.fn(),
      onError: vi.fn(),
      onPlaybackIntent: vi.fn()
    });

    void coordinator.request({ sessionId: "session-1", positionSeconds: 999, shouldPlay: true });

    expect(coordinator.shouldAcceptSession(createSession(995))).toBe(true);
    expect(coordinator.shouldAcceptSession(createSession(700))).toBe(false);
  });
});

function createSession(timelineOffsetSeconds: number): PlaybackSessionView {
  return {
    id: "session-1",
    downloadId: "download-1",
    fileId: "file-1",
    subjectId: null,
    episodeId: null,
    title: "fixture",
    status: "ready",
    source: {
      kind: "hls",
      deliveryMode: "transcode",
      timelineOffsetSeconds,
      url: `http://127.0.0.1/${timelineOffsetSeconds}/index.m3u8`,
      mimeType: "application/vnd.apple.mpegurl",
      title: "fixture"
    },
    subtitles: [],
    danmaku: [],
    danmakuSources: [],
    positionSeconds: timelineOffsetSeconds,
    durationSeconds: 1_000,
    errorMessage: null,
    createdAt: "2026-07-21T00:00:00.000Z",
    updatedAt: "2026-07-21T00:00:00.000Z"
  };
}

function deferred<T>(): { promise: Promise<T>; resolve(value: T): void } {
  let resolvePromise!: (value: T) => void;
  const promise = new Promise<T>((resolve) => {
    resolvePromise = resolve;
  });
  return { promise, resolve: resolvePromise };
}
