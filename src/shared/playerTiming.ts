import type { PlaybackDeliveryMode } from "./contracts/playback";

export type SeekAction =
  | { kind: "local"; localTimeSeconds: number }
  | { kind: "restart"; sourceTimeSeconds: number };

/**
 * Prepared HLS streams restart FFmpeg at the seek target, so targets too close
 * to the end of the source would produce empty or near-empty tail streams.
 * Seek targets are pulled back to leave at least this much playable content.
 */
export const HLS_SEEK_TAIL_SECONDS = 5;

export function clampSeekTarget(
  positionSeconds: number,
  durationSeconds: number | null | undefined
): number {
  const target = Math.max(0, positionSeconds);
  if (!durationSeconds || durationSeconds <= 0) {
    return target;
  }

  return Math.min(target, Math.max(0, durationSeconds - HLS_SEEK_TAIL_SECONDS));
}

export function resolvePlaybackDuration(
  sourceDurationSeconds: number | null | undefined,
  mediaDurationSeconds: number | null | undefined
): number | null {
  if (
    typeof sourceDurationSeconds === "number" &&
    Number.isFinite(sourceDurationSeconds) &&
    sourceDurationSeconds > 0
  ) {
    return sourceDurationSeconds;
  }

  if (
    typeof mediaDurationSeconds === "number" &&
    Number.isFinite(mediaDurationSeconds) &&
    mediaDurationSeconds > 0
  ) {
    return mediaDurationSeconds;
  }

  return null;
}

export function resolveSeekAction(input: {
  deliveryMode: PlaybackDeliveryMode;
  targetSeconds: number;
  timelineOffsetSeconds: number;
  seekableEndSeconds: number | null;
}): SeekAction {
  const targetSeconds = Math.max(0, input.targetSeconds);
  const localTimeSeconds = targetSeconds - Math.max(0, input.timelineOffsetSeconds);

  if (input.deliveryMode === "direct") {
    return { kind: "local", localTimeSeconds: Math.max(0, localTimeSeconds) };
  }

  const seekableEndSeconds = input.seekableEndSeconds ?? 0;
  if (localTimeSeconds < 0 || localTimeSeconds > seekableEndSeconds + 0.25) {
    return { kind: "restart", sourceTimeSeconds: targetSeconds };
  }

  return { kind: "local", localTimeSeconds };
}

export function toSourceTime(localTimeSeconds: number, timelineOffsetSeconds: number): number {
  return Math.max(0, localTimeSeconds) + Math.max(0, timelineOffsetSeconds);
}

export function toLocalTime(sourceTimeSeconds: number, timelineOffsetSeconds: number): number {
  return Math.max(0, sourceTimeSeconds - Math.max(0, timelineOffsetSeconds));
}
