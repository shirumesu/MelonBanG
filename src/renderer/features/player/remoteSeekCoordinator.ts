import type {
  PlaybackSessionView,
  SeekPlaybackInput
} from "@shared/contracts/playback";
import { clampSeekTarget } from "@shared/playerTiming";

export type RemoteSeekRequest = SeekPlaybackInput & {
  shouldPlay: boolean;
};

type RemoteSeekCoordinatorOptions = {
  seek(input: SeekPlaybackInput): Promise<PlaybackSessionView>;
  onSession(session: PlaybackSessionView): void;
  onError(error: unknown): void;
  onPlaybackIntent(shouldPlay: boolean): void;
};

export type RemoteSeekCoordinator = {
  request(input: RemoteSeekRequest): Promise<void>;
  isSeeking(): boolean;
  shouldAcceptSession(session: PlaybackSessionView): boolean;
  dispose(): void;
};

export function createRemoteSeekCoordinator(
  options: RemoteSeekCoordinatorOptions
): RemoteSeekCoordinator {
  let active: RemoteSeekRequest | null = null;
  let pending: RemoteSeekRequest | null = null;
  let drainTask: Promise<void> | null = null;
  let disposed = false;

  const drain = async (): Promise<void> => {
    while (!disposed && pending) {
      const request = pending;
      pending = null;
      active = request;
      options.onPlaybackIntent(request.shouldPlay);

      try {
        const session = await options.seek({
          sessionId: request.sessionId,
          positionSeconds: request.positionSeconds
        });
        if (!disposed && !pending) {
          options.onSession(session);
        }
      } catch (error) {
        if (!disposed && !pending) {
          options.onError(error);
        }
      }
    }

    active = null;
  };

  return {
    request(input) {
      if (disposed) return Promise.resolve();
      pending = input;
      drainTask ??= drain().finally(() => {
        drainTask = null;
      });
      return drainTask;
    },
    isSeeking() {
      return active !== null || pending !== null;
    },
    shouldAcceptSession(session) {
      const latest = pending ?? active;
      if (!latest) return true;
      if (session.id !== latest.sessionId || !session.source) return false;
      return matchesSeekTarget(session, latest.positionSeconds);
    },
    dispose() {
      disposed = true;
      pending = null;
    }
  };
}

function matchesSeekTarget(session: PlaybackSessionView, requestedPositionSeconds: number): boolean {
  const actualPosition = session.source?.timelineOffsetSeconds ?? session.positionSeconds;
  const expectedPosition = clampSeekTarget(requestedPositionSeconds, session.durationSeconds);
  return Math.abs(actualPosition - expectedPosition) <= 0.25;
}
