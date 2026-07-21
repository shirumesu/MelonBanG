import type { PlaybackSourceView } from "@shared/contracts/playback";
import { resolveSeekAction } from "@shared/playerTiming";

type TimelineTextTarget = {
  textContent: string | null;
};

type TimelineQueryTarget = {
  querySelector(selector: string): TimelineTextTarget | null;
};

type TimelineProgressTarget = TimelineQueryTarget & {
  getBoundingClientRect(): { left: number; width: number };
  setPointerCapture?(pointerId: number): void;
  releasePointerCapture?(pointerId: number): void;
  addEventListener(
    type: string,
    listener: EventListenerOrEventListenerObject,
    options?: boolean | AddEventListenerOptions
  ): void;
  removeEventListener(
    type: string,
    listener: EventListenerOrEventListenerObject,
    options?: boolean | EventListenerOptions
  ): void;
};

export type ArtPlayerTimelineTarget = {
  template: {
    $player: TimelineQueryTarget;
    $progress: TimelineProgressTarget;
  };
  emit(event: "setBar", type: "played" | "loaded", ratio: number): unknown;
  on(event: string, listener: () => void): unknown;
  off(event: string, listener: () => void): unknown;
};

export type MediaTimelineSource = {
  currentTime: number;
  seekable: TimeRangesLike;
  buffered: TimeRangesLike;
};

type TimeRangesLike = {
  length: number;
  start(index: number): number;
  end(index: number): number;
};

const timelineEvents = [
  "video:loadedmetadata",
  "video:durationchange",
  "video:timeupdate",
  "video:progress",
  "video:seeking",
  "video:seeked",
  "video:ended"
];

export type SourceTimelineHandle = {
  dispose(): void;
  seekBy(deltaSeconds: number): boolean;
};

export function installSourceTimeline(
  player: ArtPlayerTimelineTarget,
  media: MediaTimelineSource,
  source: PlaybackSourceView,
  durationSeconds: number | null,
  onSeekRequest: (positionSeconds: number) => void,
  isRemoteSeekPending: () => boolean = () => false
): SourceTimelineHandle {
  const sourceDuration = positiveFinite(durationSeconds);
  if (!sourceDuration) {
    return { dispose: () => undefined, seekBy: () => false };
  }

  const offsetSeconds = Math.max(0, source.timelineOffsetSeconds);
  const progress = player.template.$progress;
  let activePointerId: number | null = null;
  let dragPositionSeconds: number | null = null;
  let remoteSeekTargetSeconds: number | null = null;
  let pointerCaptured = false;
  let ignoreClickUntil = 0;

  const pinnedRemoteSeconds = (): number | null => {
    if (remoteSeekTargetSeconds !== null && !isRemoteSeekPending()) {
      remoteSeekTargetSeconds = null;
    }
    return remoteSeekTargetSeconds;
  };

  const renderCurrentPosition = (positionSeconds: number) => {
    player.emit("setBar", "played", positionSeconds / sourceDuration);

    const timeControl = player.template.$player.querySelector(".art-control-time");
    if (timeControl) {
      timeControl.textContent = `${formatTimelineTime(positionSeconds)} / ${formatTimelineTime(sourceDuration)}`;
    }
  };

  const updateTimeline = () => {
    const currentSeconds = clamp(
      dragPositionSeconds ??
        pinnedRemoteSeconds() ??
        offsetSeconds + finiteOrZero(media.currentTime),
      0,
      sourceDuration
    );
    const bufferedSeconds = clamp(offsetSeconds + getBufferedEnd(media), 0, sourceDuration);
    renderCurrentPosition(currentSeconds);
    player.emit("setBar", "loaded", bufferedSeconds / sourceDuration);
  };

  const sourcePositionAt = (clientX: number) => {
    const bounds = progress.getBoundingClientRect();
    if (bounds.width <= 0) return null;
    const ratio = clamp((clientX - bounds.left) / bounds.width, 0, 1);
    return { ratio, positionSeconds: ratio * sourceDuration };
  };

  const updateProgressTip = (positionSeconds: number) => {
    const tip = progress.querySelector(".art-progress-tip");
    if (tip) {
      tip.textContent = formatTimelineTime(positionSeconds);
    }
  };

  const seekToSource = (positionSeconds: number) => {
    const sourcePosition = clamp(positionSeconds, 0, sourceDuration);
    if (source.deliveryMode !== "direct" && isRemoteSeekPending()) {
      remoteSeekTargetSeconds = sourcePosition;
      onSeekRequest(sourcePosition);
      updateTimeline();
      return;
    }

    const action = resolveSeekAction({
      deliveryMode: source.deliveryMode,
      targetSeconds: sourcePosition,
      timelineOffsetSeconds: offsetSeconds,
      seekableEndSeconds: getSeekableEndSeconds(media)
    });
    if (action.kind === "local") {
      remoteSeekTargetSeconds = null;
      media.currentTime = action.localTimeSeconds;
      updateTimeline();
      return;
    }
    remoteSeekTargetSeconds = action.sourceTimeSeconds;
    onSeekRequest(action.sourceTimeSeconds);
    updateTimeline();
  };

  const seekToClientX = (clientX: number) => {
    const target = sourcePositionAt(clientX);
    if (!target) return;
    seekToSource(target.positionSeconds);
  };

  const stopNativeProgressDrag = (event: Event) => {
    const mouseEvent = event as MouseEvent;
    if (typeof mouseEvent.button === "number" && mouseEvent.button !== 0) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  };

  const handleProgressClick = (event: Event) => {
    const mouseEvent = event as MouseEvent;
    if (typeof mouseEvent.button === "number" && mouseEvent.button !== 0) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (Date.now() <= ignoreClickUntil) {
      ignoreClickUntil = 0;
      return;
    }
    seekToClientX(mouseEvent.clientX);
  };

  const handleProgressHover = (event: Event) => {
    const mouseEvent = event as MouseEvent;
    const target = sourcePositionAt(mouseEvent.clientX);
    if (target) updateProgressTip(target.positionSeconds);
  };

  const handlePointerDown = (event: Event) => {
    const pointerEvent = event as PointerEvent;
    if (pointerEvent.button !== 0) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    activePointerId = pointerEvent.pointerId;
    const target = sourcePositionAt(pointerEvent.clientX);
    if (target) {
      dragPositionSeconds = target.positionSeconds;
      renderCurrentPosition(target.positionSeconds);
      updateProgressTip(target.positionSeconds);
    }
    try {
      progress.setPointerCapture?.(pointerEvent.pointerId);
      pointerCaptured = true;
    } catch {
      pointerCaptured = false;
    }
  };

  const handlePointerMove = (event: Event) => {
    const pointerEvent = event as PointerEvent;
    if (pointerEvent.pointerId !== activePointerId) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const target = sourcePositionAt(pointerEvent.clientX);
    if (!target) return;
    dragPositionSeconds = target.positionSeconds;
    renderCurrentPosition(target.positionSeconds);
    updateProgressTip(target.positionSeconds);
  };

  const finishPointerDrag = (event: Event, commit: boolean) => {
    const pointerEvent = event as PointerEvent;
    if (pointerEvent.pointerId !== activePointerId) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const target = sourcePositionAt(pointerEvent.clientX);
    if (pointerCaptured) {
      try {
        progress.releasePointerCapture?.(pointerEvent.pointerId);
      } catch {
        pointerCaptured = false;
      }
    }
    activePointerId = null;
    dragPositionSeconds = null;
    pointerCaptured = false;
    if (commit && target) {
      ignoreClickUntil = Date.now() + 250;
      seekToSource(target.positionSeconds);
    } else {
      updateTimeline();
    }
  };

  const handlePointerUp = (event: Event) => finishPointerDrag(event, true);
  const handlePointerCancel = (event: Event) => finishPointerDrag(event, false);

  timelineEvents.forEach((event) => player.on(event, updateTimeline));
  progress.addEventListener("pointerdown", handlePointerDown, true);
  progress.addEventListener("pointermove", handlePointerMove, true);
  progress.addEventListener("pointerup", handlePointerUp, true);
  progress.addEventListener("pointercancel", handlePointerCancel, true);
  progress.addEventListener("mousedown", stopNativeProgressDrag, true);
  progress.addEventListener("click", handleProgressClick, true);
  progress.addEventListener("mousemove", handleProgressHover);
  updateTimeline();

  return {
    dispose() {
      timelineEvents.forEach((event) => player.off(event, updateTimeline));
      progress.removeEventListener("pointerdown", handlePointerDown, true);
      progress.removeEventListener("pointermove", handlePointerMove, true);
      progress.removeEventListener("pointerup", handlePointerUp, true);
      progress.removeEventListener("pointercancel", handlePointerCancel, true);
      progress.removeEventListener("mousedown", stopNativeProgressDrag, true);
      progress.removeEventListener("click", handleProgressClick, true);
      progress.removeEventListener("mousemove", handleProgressHover);
    },
    seekBy(deltaSeconds) {
      const baseSeconds =
        dragPositionSeconds ??
        pinnedRemoteSeconds() ??
        offsetSeconds + finiteOrZero(media.currentTime);
      seekToSource(baseSeconds + deltaSeconds);
      return true;
    }
  };
}

function getSeekableEndSeconds(media: MediaTimelineSource): number | null {
  let endSeconds: number | null = null;
  for (let index = 0; index < media.seekable.length; index += 1) {
    const candidate = media.seekable.end(index);
    if (Number.isFinite(candidate)) {
      endSeconds = endSeconds === null ? candidate : Math.max(endSeconds, candidate);
    }
  }
  return endSeconds;
}

function getBufferedEnd(media: MediaTimelineSource): number {
  let endSeconds = 0;
  for (let index = 0; index < media.buffered.length; index += 1) {
    endSeconds = Math.max(endSeconds, finiteOrZero(media.buffered.end(index)));
  }
  return endSeconds;
}

function formatTimelineTime(value: number): string {
  const seconds = Math.max(0, Math.floor(finiteOrZero(value)));
  const hours = Math.floor(seconds / 3_600);
  const minutes = Math.floor((seconds % 3_600) / 60);
  const remainder = seconds % 60;
  if (hours > 0) {
    return [hours, minutes, remainder].map((part) => String(part).padStart(2, "0")).join(":");
  }
  return [minutes, remainder].map((part) => String(part).padStart(2, "0")).join(":");
}

function positiveFinite(value: number | null): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null;
}

function finiteOrZero(value: number): number {
  return Number.isFinite(value) ? value : 0;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, Number.isFinite(value) ? value : minimum));
}
