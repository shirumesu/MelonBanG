import { describe, expect, it } from "vitest";
import type {
  CollectionStatus,
  EpisodeStatus,
  TrackingMutation
} from "../../src/shared/contracts/bangumi";

describe("bangumi shared contracts", () => {
  it("accepts subject collection mutations with Bangumi statuses", () => {
    const statuses: CollectionStatus[] = ["wish", "watching", "completed", "on_hold", "dropped"];

    const mutations: TrackingMutation[] = statuses.map((status, index) => ({
      kind: "subjectCollection",
      subjectId: index + 1,
      status
    }));

    expect(mutations).toHaveLength(statuses.length);
    expect(mutations[0]).toMatchObject({ kind: "subjectCollection", status: "wish" });
  });

  it("accepts episode collection mutations with episode statuses", () => {
    const statuses: EpisodeStatus[] = ["unwatched", "queue", "watched", "dropped"];

    const mutations: TrackingMutation[] = statuses.map((status, index) => ({
      kind: "episodeCollection",
      episodeId: index + 100,
      status
    }));

    expect(mutations).toHaveLength(statuses.length);
    expect(mutations[2]).toMatchObject({ kind: "episodeCollection", status: "watched" });
  });
});
