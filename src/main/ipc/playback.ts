import { BrowserWindow, ipcMain } from "electron";
import { z } from "zod";
import type {
  PlaybackProgressInput,
  StartPlaybackFromDownloadInput
} from "../../shared/contracts/playback";
import { getPlaybackService } from "../playback/playbackService";

const downloadIdSchema = z.string().uuid();
const sessionIdSchema = z.string().uuid();
const startFromDownloadSchema = z.object({
  downloadId: downloadIdSchema,
  fileId: z.string().optional()
});
const progressSchema = z.object({
  sessionId: sessionIdSchema,
  positionSeconds: z.number().finite().nonnegative(),
  durationSeconds: z.number().finite().nonnegative().nullable(),
  paused: z.boolean(),
  ended: z.boolean()
});

export function registerPlaybackIpc(getMainWindow: () => BrowserWindow | null): void {
  const service = getPlaybackService();

  service.onSession((session) => {
    const mainWindow = getMainWindow();
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send("playback:update", session);
    }
  });

  handle("playback:startFromDownload", (input: StartPlaybackFromDownloadInput) =>
    service.startFromDownload(startFromDownloadSchema.parse(input))
  );
  handle("playback:getSession", () => service.getSession());
  handle("playback:updateProgress", (input: PlaybackProgressInput) =>
    service.updateProgress(progressSchema.parse(input))
  );
  handle("playback:stop", (sessionId: string) => service.stop(sessionIdSchema.parse(sessionId)));
}

function handle<Args extends unknown[], Result>(
  channel: `playback:${string}`,
  fn: (...args: Args) => Result | Promise<Result>
): void {
  ipcMain.handle(channel, async (_event, ...args) => {
    try {
      return await fn(...(args as Args));
    } catch (error) {
      throw new Error(toRendererSafeError(error), { cause: error });
    }
  });
}

function toRendererSafeError(error: unknown): string {
  if (error instanceof z.ZodError) {
    return error.issues[0]?.message ?? "播放请求参数无效。";
  }

  if (error instanceof Error) {
    return error.message || "播放请求失败。";
  }

  return "播放请求失败。";
}
