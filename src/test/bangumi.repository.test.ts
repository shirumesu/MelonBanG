import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { BangumiOAuthConfig } from "../main/config/bangumi";

const config: BangumiOAuthConfig = {
  clientId: "client-id",
  clientSecret: "client-secret",
  redirectUri: "http://127.0.0.1:14567/callback",
  userAgent: "melonbang-test/0.1.0"
};

describe("BangumiRepository", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.resetModules();
    delete process.env.MELONBANG_DATA_DIR;
  });

  it("clears queued tracking mutations on sign-out so another account cannot flush them", async () => {
    const { BangumiRepository, MutationQueueStore } = await loadRepositoryModules();
    const queue = new MutationQueueStore();
    queue.enqueue({
      kind: "subjectCollection",
      subjectId: 123,
      status: "watching"
    });

    expect(queue.getPendingCount()).toBe(1);

    const repository = new BangumiRepository(config);
    await repository.signOut();

    expect(queue.getPendingCount()).toBe(0);
  });

  it("keeps pending episode state visible after subject detail refresh", async () => {
    const { BangumiRepository, MutationQueueStore } = await loadRepositoryModules();
    const queue = new MutationQueueStore();
    queue.enqueue({
      kind: "episodeCollection",
      episodeId: 1001,
      status: "watched"
    });
    vi.stubGlobal("fetch", mockMelonSubjectFetch());

    const repository = new BangumiRepository(config);
    const subject = await repository.getSubject(123);

    expect(subject.episodes).toEqual([
      expect.objectContaining({
        episodeId: 1001,
        status: "watched"
      })
    ]);
  });

  it("maps pending subject and episode mutation keys onto collection list items", async () => {
    const { CollectionStore, MutationQueueStore } = await loadRepositoryModules();
    const collectionStore = new CollectionStore();
    const queue = new MutationQueueStore();

    collectionStore.upsertSubjectCache({
      subjectId: 123,
      name: "Test Anime",
      episodeTotal: 1
    });
    collectionStore.upsertStoredSubjectCollection({
      subjectId: 123,
      status: "watching",
      updatedAt: "2026-06-23T10:00:00.000Z"
    });
    collectionStore.updateEpisodeStatus({
      episodeId: 1001,
      subjectId: 123,
      sort: 1,
      name: "Episode 1",
      status: "queue"
    });

    const subjectMutation = queue.enqueue({
      kind: "subjectCollection",
      subjectId: 123,
      status: "completed"
    });
    const episodeMutation = queue.enqueue({
      kind: "episodeCollection",
      episodeId: 1001,
      status: "watched"
    });

    const [item] = collectionStore.listCollection();

    expect(item.pendingMutationKeys).toEqual([
      subjectMutation.mutationKey,
      episodeMutation.mutationKey
    ]);
  });
});

async function loadRepositoryModules(): Promise<{
  BangumiRepository: typeof import("../main/bangumi/BangumiRepository").BangumiRepository;
  MutationQueueStore: typeof import("../main/store/mutationQueueStore").MutationQueueStore;
  CollectionStore: typeof import("../main/store/collectionStore").CollectionStore;
}> {
  vi.resetModules();
  process.env.MELONBANG_DATA_DIR = mkdtempSync(join(tmpdir(), "melonbang-test-"));
  vi.doMock("electron", () => ({
    app: {
      isPackaged: false,
      getAppPath: () => process.env.MELONBANG_DATA_DIR,
      getPath: () => process.env.MELONBANG_DATA_DIR,
      getVersion: () => "0.1.0"
    },
    safeStorage: {
      isEncryptionAvailable: () => true,
      encryptString: (value: string) => Buffer.from(value, "utf8"),
      decryptString: (value: Buffer) => value.toString("utf8")
    },
    shell: {
      openExternal: () => Promise.resolve()
    }
  }));

  const [{ BangumiRepository }, { MutationQueueStore }, { CollectionStore }] = await Promise.all([
    import("../main/bangumi/BangumiRepository"),
    import("../main/store/mutationQueueStore"),
    import("../main/store/collectionStore")
  ]);

  return { BangumiRepository, MutationQueueStore, CollectionStore };
}

function mockMelonSubjectFetch() {
  return vi.fn((input: Parameters<typeof fetch>[0]) => {
    const url =
      typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;

    if (url.endsWith("/v1/subjects/123")) {
      return Promise.resolve(
        jsonResponse({
          data: {
            subjectId: 123,
            name: "Test Anime",
            displayName: "Test Anime",
            episodeTotal: 1,
            episodes: [
              {
                episodeId: 1001,
                subjectId: 123,
                type: "main",
                sort: 1,
                ep: 1,
                name: "Episode 1",
                nameCn: "第一话"
              }
            ]
          }
        })
      );
    }

    return Promise.resolve(jsonResponse({ data: [] }));
  });
}

function jsonResponse(payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: { "Content-Type": "application/json" }
  });
}
