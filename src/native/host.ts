import { createInterface } from "node:readline";
import { existsSync, statSync } from "node:fs";
import { basename, isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";
import { z } from "zod";
import { getBangumiService } from "../main/services/serviceFactory";
import { getDownloadService } from "../main/download/downloadService";
import { getSourceService } from "../main/sources/sourceService";
import { PlaybackService } from "../main/playback/playbackService";
import { platformEvents } from "./platform";

const send = (value: unknown) => process.stdout.write(`${JSON.stringify(value)}\n`);
// Stdout is a framed protocol; dependency diagnostics belong on stderr.
console.log = (...args: unknown[]) => console.error(...args);
const nativeSource = (input: { filePath: string; title: string }) =>
  Promise.resolve({
    kind: "file" as const,
    deliveryMode: "direct" as const,
    timelineOffsetSeconds: 0,
    url: pathToFileURL(input.filePath).href,
    mimeType: null,
    title: input.title
  });
const unsupported = (): Promise<never> => Promise.reject(new Error("原生播放器直接处理跳转。"));
const playback = new PlaybackService(
  undefined,
  {
    registerMediaFile: nativeSource,
    registerRemuxedMediaFile: unsupported,
    registerTranscodedMediaFile: unsupported,
    restartRemuxedMediaFile: unsupported,
    restartTranscodedMediaFile: unsupported,
    revokeSession: () => {}
  },
  {
    probe() {
      return Promise.resolve({
        durationSeconds: null,
        videoCodec: "native",
        audioCodec: null,
        deliveryMode: "direct" as const
      });
    }
  },
  {
    prepareSubtitles() {
      return Promise.resolve([]);
    }
  }
);

platformEvents.on("openExternal", (url: string) => send({ event: "openExternal", data: url }));
let reportingProgress = false;
playback.onSession((data) => {
  if (!reportingProgress) send({ event: "playback", data });
});
let downloadsSubscribed = false;
function downloads() {
  const service = getDownloadService();
  if (!downloadsSubscribed) {
    downloadsSubscribed = true;
    service.onSnapshot((data) => send({ event: "downloads", data }));
  }
  return service;
}

const id = z.number().int().positive();
const sessionId = z.string().min(1);
const tracking = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("subjectCollection"),
    subjectId: id,
    status: z.enum(["wish", "watching", "completed", "on_hold", "dropped"]).optional(),
    score: z.number().int().min(0).max(10).optional()
  }),
  z.object({
    kind: z.literal("episodeCollection"),
    episodeId: id,
    status: z.enum(["unwatched", "queue", "watched", "dropped"])
  })
]);

async function dispatch(method: string, args: unknown[]): Promise<unknown> {
  const value = args[0];
  const bgm = getBangumiService;
  switch (method) {
    case "health":
      return { version: "0.2.0", player: "media_kit", pid: process.pid };
    case "bangumi.getSession":
      return bgm().getSession();
    case "bangumi.signIn":
      return bgm().signIn();
    case "bangumi.cancelSignIn":
      return bgm().cancelSignIn();
    case "bangumi.signOut":
      return bgm().signOut();
    case "bangumi.listCollection":
      return bgm().listCollection();
    case "bangumi.getSubject":
      return bgm().getSubject(id.parse(value));
    case "bangumi.searchSubjects":
      return bgm().searchSubjects(z.string().trim().min(1).parse(value));
    case "bangumi.getTrendingCurrent":
      return bgm().getTrendingCurrent();
    case "bangumi.getTodaySchedule":
      return bgm().getTodaySchedule();
    case "bangumi.getCalendar":
      return bgm().getCalendar();
    case "bangumi.updateTracking":
      return bgm().updateTracking(tracking.parse(value));
    case "bangumi.refreshCollection":
      return bgm().refreshCollection(true);
    case "bangumi.getSyncState":
      return bgm().getSyncState();
    case "download.list":
      return downloads().list();
    case "download.create": {
      const input = z
        .object({
          kind: z.enum(["magnet", "torrentFile"]),
          uri: z.string().optional(),
          name: z.string().optional(),
          bytes: z.array(z.number().int().min(0).max(255)).optional()
        })
        .parse(value);
      return downloads().create(
        input.kind === "magnet"
          ? { kind: "magnet", uri: input.uri ?? "" }
          : {
              kind: "torrentFile",
              name: input.name ?? "download.torrent",
              bytes: Uint8Array.from(input.bytes ?? [])
            }
      );
    }
    case "download.pause":
      return downloads().pause(z.string().uuid().parse(value));
    case "download.resume":
      return downloads().resume(z.string().uuid().parse(value));
    case "download.remove":
      return downloads().remove(z.string().uuid().parse(value));
    case "source.search":
      return getSourceService().search(
        z
          .object({
            subjectId: id,
            episodeId: id.optional(),
            keyword: z.string().trim().min(1).max(120)
          })
          .parse(value)
      );
    case "source.enqueue":
      return getSourceService().enqueue(
        z.object({ candidateId: z.string().uuid(), episodeId: id.optional() }).parse(value)
      );
    case "playback.startLocal": {
      const input = z
        .object({ path: z.string(), subjectId: id.optional(), episodeId: id.optional() })
        .parse(value);
      if (!isAbsolute(input.path) || !existsSync(input.path) || !statSync(input.path).isFile())
        throw new Error("视频文件不存在。");
      return playback.startLocal(
        input.path,
        basename(input.path),
        input.subjectId,
        input.episodeId
      );
    }
    case "playback.startFromDownload":
      return playback.startFromDownload(
        z.object({ downloadId: z.string().uuid(), fileId: z.string().optional() }).parse(value)
      );
    case "playback.startEpisode":
      return playback.startEpisode(z.object({ subjectId: id, episodeId: id }).parse(value));
    case "playback.getEpisodeProgress":
      return playback.getEpisodeProgress(z.object({ subjectId: id, episodeId: id }).parse(value));
    case "playback.loadDanmaku":
      return playback.loadDanmaku(sessionId.parse(value));
    case "playback.searchDanmakuEpisodes":
      return playback.searchDanmakuEpisodes(
        z.object({ sessionId, anime: z.string().min(1) }).parse(value)
      );
    case "playback.selectDanmakuEpisode":
      return playback.selectDanmakuEpisode(z.object({ sessionId, episodeId: id }).parse(value));
    case "playback.loadDanmakuSource":
      return playback.loadDanmakuSource(
        z
          .object({
            sessionId,
            providerId: z.enum(["bilibili", "bahamut"]),
            locator: z.string().min(1)
          })
          .parse(value)
      );
    case "playback.setDanmakuSourceEnabled":
      return playback.setDanmakuSourceEnabled(
        z
          .object({
            sessionId,
            providerId: z.enum(["dandanplay", "bilibili", "bahamut"]),
            enabled: z.boolean()
          })
          .parse(value)
      );
    case "playback.updateProgress": {
      reportingProgress = true;
      try {
        playback.updateProgress(
          z
            .object({
              sessionId,
              positionSeconds: z.number().finite().nonnegative(),
              durationSeconds: z.number().finite().positive().nullable(),
              timelineOffsetSeconds: z.literal(0),
              paused: z.boolean(),
              ended: z.boolean()
            })
            .parse(value)
        );
        return { saved: true };
      } finally {
        reportingProgress = false;
      }
    }
    case "playback.stop":
      return playback.stop(sessionId.parse(value));
    default:
      throw new Error(`未知操作：${method}`);
  }
}

createInterface({ input: process.stdin })
  .on("line", (line) => {
    void (async () => {
      let requestId: unknown = null;
      try {
        const request = z
          .object({
            id: z.number().int(),
            method: z.string(),
            args: z.array(z.unknown()).default([])
          })
          .parse(JSON.parse(line));
        requestId = request.id;
        send({ id: request.id, result: (await dispatch(request.method, request.args)) ?? null });
      } catch (error) {
        send({ id: requestId, error: error instanceof Error ? error.message : "操作失败。" });
      }
    })();
  })
  .on("close", () => process.exit(0));
send({ event: "ready", data: { version: "0.2.0" } });
