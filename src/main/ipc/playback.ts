import { BrowserWindow, ipcMain } from "electron";
import { z } from "zod";
import type {
  BindEpisodeMediaInput,
  BindSessionEpisodeInput,
  ClearEpisodeMediaBindingInput,
  DanmakuEpisodeSearchInput,
  EpisodeMediaBindingInput,
  LoadDanmakuSourceInput,
  PlaybackProgressInput,
  SeekPlaybackInput,
  SetDanmakuSourceEnabledInput,
  SelectDanmakuEpisodeInput,
  StartEpisodePlaybackInput,
  StartPlaybackFromDownloadInput
} from "../../shared/contracts/playback";
import { getPlaybackService } from "../playback/playbackService";

const downloadIdSchema = z.string().uuid();
const sessionIdSchema = z.string().uuid();
const startFromDownloadSchema = z.object({
  downloadId: downloadIdSchema,
  fileId: z.string().optional()
});
const episodeBindingSchema = z.object({
  subjectId: z.number().int().positive(),
  episodeId: z.number().int().positive()
});
const bindEpisodeMediaSchema = episodeBindingSchema.extend({
  downloadId: downloadIdSchema,
  fileId: z.string().optional()
});
const bindSessionEpisodeSchema = episodeBindingSchema.extend({
  sessionId: sessionIdSchema
});
const clearEpisodeMediaBindingSchema = z.object({
  bindingId: z.string().uuid()
});
const progressSchema = z.object({
  sessionId: sessionIdSchema,
  positionSeconds: z.number().finite().nonnegative(),
  durationSeconds: z.number().finite().nonnegative().nullable(),
  timelineOffsetSeconds: z.number().finite().nonnegative(),
  paused: z.boolean(),
  ended: z.boolean()
});
const seekSchema = z.object({
  sessionId: sessionIdSchema,
  positionSeconds: z.number().finite().nonnegative()
});
const searchDanmakuEpisodesSchema = z.object({
  sessionId: sessionIdSchema,
  anime: z.string().trim().min(1).max(120)
});
const selectDanmakuEpisodeSchema = z.object({
  sessionId: sessionIdSchema,
  episodeId: z.number().int().positive()
});
const loadDanmakuSourceSchema = z.object({
  sessionId: sessionIdSchema,
  providerId: z.enum(["bilibili", "bahamut"]),
  locator: z.string().trim().min(1).max(240)
});
const setDanmakuSourceEnabledSchema = z.object({
  sessionId: sessionIdSchema,
  providerId: z.enum(["dandanplay", "bilibili", "bahamut"]),
  enabled: z.boolean()
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
  handle("playback:bindEpisodeMedia", (input: BindEpisodeMediaInput) =>
    service.bindEpisodeMedia(bindEpisodeMediaSchema.parse(input))
  );
  handle("playback:bindSessionEpisode", (input: BindSessionEpisodeInput) =>
    service.bindSessionEpisode(bindSessionEpisodeSchema.parse(input))
  );
  handle("playback:getEpisodeMediaBinding", (input: EpisodeMediaBindingInput) =>
    service.getEpisodeMediaBinding(episodeBindingSchema.parse(input))
  );
  handle("playback:listEpisodeMediaBindings", (subjectId: number) =>
    service.listEpisodeMediaBindings(z.number().int().positive().parse(subjectId))
  );
  handle("playback:clearEpisodeMediaBinding", (input: ClearEpisodeMediaBindingInput) =>
    service.clearEpisodeMediaBinding(clearEpisodeMediaBindingSchema.parse(input))
  );
  handle("playback:startEpisode", (input: StartEpisodePlaybackInput) =>
    service.startEpisode(episodeBindingSchema.parse(input))
  );
  handle("playback:getEpisodeProgress", (input: EpisodeMediaBindingInput) =>
    service.getEpisodeProgress(episodeBindingSchema.parse(input))
  );
  handle("playback:getSession", () => service.getSession());
  handle("playback:loadDanmaku", (sessionId: string) =>
    service.loadDanmaku(sessionIdSchema.parse(sessionId))
  );
  handle("playback:searchDanmakuEpisodes", (input: DanmakuEpisodeSearchInput) =>
    service.searchDanmakuEpisodes(searchDanmakuEpisodesSchema.parse(input))
  );
  handle("playback:selectDanmakuEpisode", (input: SelectDanmakuEpisodeInput) =>
    service.selectDanmakuEpisode(selectDanmakuEpisodeSchema.parse(input))
  );
  handle("playback:loadDanmakuSource", (input: LoadDanmakuSourceInput) =>
    service.loadDanmakuSource(loadDanmakuSourceSchema.parse(input))
  );
  handle("playback:setDanmakuSourceEnabled", (input: SetDanmakuSourceEnabledInput) =>
    service.setDanmakuSourceEnabled(setDanmakuSourceEnabledSchema.parse(input))
  );
  handle("playback:seek", (input: SeekPlaybackInput) => service.seek(seekSchema.parse(input)));
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
