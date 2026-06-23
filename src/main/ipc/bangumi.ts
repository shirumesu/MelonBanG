import { ipcMain } from "electron";
import { z } from "zod";
import type { CollectionFilter, TrackingMutation } from "../../shared/contracts/bangumi";
import { getBangumiService } from "../services/serviceFactory";

const filterSchema = z
  .object({
    status: z.enum(["wish", "watching", "completed", "on_hold", "dropped"]).optional(),
    search: z.string().trim().min(1).optional()
  })
  .optional();

const trackingMutationSchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("subjectCollection"),
    subjectId: z.number().int().positive(),
    status: z.enum(["wish", "watching", "completed", "on_hold", "dropped"]).optional(),
    score: z.number().int().min(0).max(10).optional()
  }),
  z.object({
    kind: z.literal("episodeCollection"),
    episodeId: z.number().int().positive(),
    status: z.enum(["unwatched", "queue", "watched", "dropped"])
  })
]);

export function registerBangumiIpc(): void {
  handle("bangumi:getSession", () => getBangumiService().getSession());
  handle("bangumi:signIn", () => getBangumiService().signIn());
  handle("bangumi:cancelSignIn", () => getBangumiService().cancelSignIn());
  handle("bangumi:signOut", () => getBangumiService().signOut());
  handle("bangumi:listCollection", (filter?: CollectionFilter) =>
    getBangumiService().listCollection(filterSchema.parse(filter))
  );
  handle("bangumi:getCachedSubject", (subjectId: number) =>
    getBangumiService().getCachedSubject(z.number().int().positive().parse(subjectId))
  );
  handle("bangumi:getSubject", (subjectId: number) =>
    getBangumiService().getSubject(z.number().int().positive().parse(subjectId))
  );
  handle("bangumi:searchSubjects", (keyword: string) =>
    getBangumiService().searchSubjects(z.string().trim().min(1).parse(keyword))
  );
  handle("bangumi:getTrendingCurrent", () => getBangumiService().getTrendingCurrent());
  handle("bangumi:getTodaySchedule", () => getBangumiService().getTodaySchedule());
  handle("bangumi:getCalendar", () => getBangumiService().getCalendar());
  handle("bangumi:updateTracking", (input: TrackingMutation) =>
    getBangumiService().updateTracking(trackingMutationSchema.parse(input))
  );
  handle("bangumi:refreshCollection", (force?: boolean) =>
    getBangumiService().refreshCollection(z.boolean().optional().parse(force))
  );
  handle("bangumi:getSyncState", () => getBangumiService().getSyncState());
}

function handle<Args extends unknown[], Result>(
  channel: `bangumi:${string}`,
  fn: (...args: Args) => Result | Promise<Result>
): void {
  ipcMain.handle(channel, (_event, ...args) => fn(...(args as Args)));
}
