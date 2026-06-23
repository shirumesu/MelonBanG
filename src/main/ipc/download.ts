import { BrowserWindow, ipcMain } from "electron";
import { z } from "zod";
import type { TorrentInput } from "../../shared/contracts/download";
import { getDownloadService } from "../download/downloadService";

const torrentInputSchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("magnet"),
    uri: z.string()
  }),
  z.object({
    kind: z.literal("torrentFile"),
    name: z.string(),
    bytes: z.custom<Uint8Array>((value) => value instanceof Uint8Array, {
      message: "种子文件内容无效。"
    })
  })
]);

const downloadIdSchema = z.string().uuid();

export function registerDownloadIpc(): void {
  const service = getDownloadService();

  service.onSnapshot((snapshot) => {
    for (const window of BrowserWindow.getAllWindows()) {
      window.webContents.send("download:update", snapshot);
    }
  });

  handle("download:create", (input: TorrentInput) =>
    service.create(torrentInputSchema.parse(input))
  );
  handle("download:list", () => service.list());
  handle("download:pause", (downloadId: string) => service.pause(downloadIdSchema.parse(downloadId)));
  handle("download:resume", (downloadId: string) =>
    service.resume(downloadIdSchema.parse(downloadId))
  );
  handle("download:remove", (downloadId: string) =>
    service.remove(downloadIdSchema.parse(downloadId))
  );
}

function handle<Args extends unknown[], Result>(
  channel: `download:${string}`,
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
    return error.issues[0]?.message ?? "下载请求参数无效。";
  }

  if (error instanceof Error) {
    return error.message || "下载请求失败。";
  }

  return "下载请求失败。";
}
