import { ipcMain } from "electron";
import { z } from "zod";
import type { SourceEnqueueInput, SourceSearchInput } from "../../shared/contracts/source";
import { getSourceService } from "../sources/sourceService";

const searchInputSchema = z.object({
  subjectId: z.number().int().positive(),
  episodeId: z.number().int().positive().optional(),
  keyword: z.string().trim().min(1, "请输入搜索关键词。").max(120, "搜索关键词过长。"),
  keywords: z
    .array(z.string().trim().min(1, "搜索关键词不能为空。").max(120, "搜索关键词过长。"))
    .max(4, "搜索关键词过多。")
    .optional()
});
const enqueueInputSchema = z.object({ candidateId: z.string().uuid("资源编号无效。") });

export function registerSourceIpc(): void {
  const service = getSourceService();
  handle("source:search", (input: SourceSearchInput) =>
    service.search(searchInputSchema.parse(input))
  );
  handle("source:enqueue", (input: SourceEnqueueInput) =>
    service.enqueue(enqueueInputSchema.parse(input))
  );
}

function handle<Args extends unknown[], Result>(
  channel: `source:${string}`,
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
    return error.issues[0]?.message ?? "资源请求参数无效。";
  }
  return error instanceof Error ? error.message || "资源请求失败。" : "资源请求失败。";
}
