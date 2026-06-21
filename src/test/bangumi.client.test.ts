import { afterEach, describe, expect, it, vi } from "vitest";
import { BangumiClient } from "../main/bangumi/BangumiClient";
import type { BangumiOAuthConfig } from "../main/config/bangumi";

const config: BangumiOAuthConfig = {
  clientId: "client-id",
  clientSecret: "client-secret",
  redirectUri: "http://127.0.0.1:14567/callback",
  userAgent: "83977/melonbang-test/0.1.0 (https://github.com/83977/melonbang)"
};

describe("BangumiClient", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("loads one official-size anime collection page and maps progress from ep_status", async () => {
    const fetchMock = mockJsonResponse({
      total: 80,
      limit: 50,
      offset: 0,
      data: [
        {
          subject_id: 123,
          subject_type: 2,
          type: 3,
          rate: 8,
          ep_status: 7,
          updated_at: "2026-06-22T10:00:00+08:00",
          private: false,
          tags: [],
          subject: {
            id: 123,
            type: 2,
            name: "Test Anime",
            name_cn: "测试动画",
            short_summary: "A slim subject summary.",
            date: "2026-04-01",
            images: { common: "https://example.com/cover.jpg" },
            eps: 12,
            collection_total: 1000,
            rank: 42,
            score: 8.2,
            tags: []
          }
        },
        {
          subject_id: 456,
          subject_type: 4,
          type: 3,
          rate: 0,
          ep_status: 0,
          updated_at: "2026-06-22T10:00:00+08:00",
          private: false,
          tags: []
        }
      ]
    });

    const client = new BangumiClient(config, "token");
    const page = await client.getUserCollections("demo-user");

    expect(requestUrl(fetchMock)).toContain(
      "/v0/users/demo-user/collections?subject_type=2&limit=50&offset=0"
    );
    expect(page.total).toBe(80);
    expect(page.items).toHaveLength(1);
    expect(page.items[0]).toMatchObject({
      subjectId: 123,
      status: "watching",
      score: 8,
      epStatus: 7,
      subject: {
        name: "Test Anime",
        nameCn: "测试动画",
        coverUrl: "https://example.com/cover.jpg",
        rank: 42,
        score: 8.2
      }
    });
  });

  it("loads only main episodes in one page for subject detail", async () => {
    const fetchMock = mockJsonResponse({
      total: 2,
      limit: 200,
      offset: 0,
      data: [
        {
          id: 1001,
          type: 0,
          sort: 1,
          ep: 1,
          name: "Episode 1",
          name_cn: "第一话"
        },
        {
          id: 1002,
          type: 2,
          sort: 1,
          name: "OP",
          name_cn: ""
        }
      ]
    });

    const client = new BangumiClient(config, "token");
    const episodes = await client.getEpisodes(123);

    expect(requestUrl(fetchMock)).toContain(
      "/v0/episodes?subject_id=123&type=0&limit=200&offset=0"
    );
    expect(episodes).toEqual([
      {
        id: 1001,
        subjectId: 123,
        sort: 1,
        ep: 1,
        name: "Episode 1",
        nameCn: "第一话"
      }
    ]);
  });

  it("maps episode collection states and uses the official episode update payload", async () => {
    const fetchMock = mockJsonResponse({
      total: 1,
      limit: 1000,
      offset: 0,
      data: [
        {
          type: 2,
          updated_at: 1782100000,
          episode: {
            id: 1001,
            sort: 1,
            ep: 1,
            name: "Episode 1",
            name_cn: "第一话"
          }
        }
      ]
    });

    const client = new BangumiClient(config, "token");
    const collections = await client.getUserSubjectEpisodeCollections(123);

    expect(requestUrl(fetchMock)).toContain(
      "/v0/users/-/collections/123/episodes?episode_type=0&limit=1000&offset=0"
    );
    expect(collections[0]).toMatchObject({
      episode: { id: 1001, subjectId: 123 },
      status: "watched"
    });

    fetchMock.mockResolvedValueOnce(new Response(null, { status: 204 }));
    await client.updateEpisodeCollection(1001, "queue");

    const episodeUpdate = requestInit(fetchMock, 1);
    expect(requestUrl(fetchMock, 1)).toContain("/v0/users/-/collections/-/episodes/1001");
    expect(episodeUpdate?.method).toBe("PUT");
    expect(requestBodyJson(episodeUpdate)).toEqual({
      type: 1
    });
  });

  it("uses Bangumi numeric collection types for subject updates", async () => {
    const fetchMock = mockVoidResponse();
    const client = new BangumiClient(config, "token");

    await client.updateSubjectCollection(123, { status: "completed", score: 9 });

    const subjectUpdate = requestInit(fetchMock);
    expect(requestUrl(fetchMock)).toContain("/v0/users/-/collections/123");
    expect(subjectUpdate?.method).toBe("POST");
    expect(requestBodyJson(subjectUpdate)).toEqual({
      type: 2,
      rate: 9
    });
  });
});

function mockJsonResponse(payload: unknown) {
  const fetchMock = vi.fn(
    (input: Parameters<typeof fetch>[0], init?: Parameters<typeof fetch>[1]) => {
      void input;
      void init;
      return Promise.resolve(jsonResponse(payload));
    }
  );
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function mockVoidResponse() {
  const fetchMock = vi.fn(
    (input: Parameters<typeof fetch>[0], init?: Parameters<typeof fetch>[1]) => {
      void input;
      void init;
      return Promise.resolve(new Response(null, { status: 204 }));
    }
  );
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function requestUrl(fetchMock: ReturnType<typeof mockJsonResponse>, index = 0): string {
  const input = fetchMock.mock.calls[index]?.[0];
  if (typeof input === "string") {
    return input;
  }
  if (input instanceof URL) {
    return input.toString();
  }
  if (input instanceof Request) {
    return input.url;
  }

  return "";
}

function requestInit(
  fetchMock: ReturnType<typeof mockJsonResponse>,
  index = 0
): RequestInit | undefined {
  return fetchMock.mock.calls[index]?.[1];
}

function requestBodyJson(init: RequestInit | undefined): unknown {
  if (typeof init?.body !== "string") {
    return undefined;
  }

  return JSON.parse(init.body) as unknown;
}

function jsonResponse(payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: { "Content-Type": "application/json" }
  });
}
