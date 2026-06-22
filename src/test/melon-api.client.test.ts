import { afterEach, describe, expect, it, vi } from "vitest";
import { MelonApiClient } from "../main/bangumi/MelonApiClient";

describe("MelonApiClient", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("loads current trending subjects from Melon API", async () => {
    const fetchMock = mockJsonResponses(
      {
        offset: 0,
        limit: 100,
        hasMore: true,
        data: [
          {
            subjectId: 543360,
            name: "Test Trending",
            nameCn: "测试热播",
            displayName: "测试热播",
            coverUrl: "https://example.com/cover.jpg",
            summary: "Trending summary.",
            airDate: "2026-04-10",
            season: {
              year: 2026,
              quarter: 2,
              code: "2026Q2",
              label: "2026 SPRING",
              name: "SPRING"
            },
            platform: "TV",
            episodeTotal: 12,
            score: 7.4,
            rank: 1100,
            tags: [{ name: "青春", count: 12 }],
            metaTags: ["TV"],
            nsfw: false,
            url: "https://bangumi.tv/subject/543360"
          }
        ]
      },
      {
        offset: 1,
        limit: 100,
        hasMore: false,
        data: [
          {
            subjectId: 547888,
            name: "Second Trending",
            displayName: "Second Trending",
            type: "anime",
            coverUrl: "https://example.com/second.jpg",
            tags: [],
            metaTags: []
          }
        ]
      }
    );

    const client = new MelonApiClient();
    const trending = await client.getTrendingCurrent();

    expect(requestUrl(fetchMock)).toBe(
      "https://melonapi.konataizumi.com/v1/trending/current?limit=100&offset=0"
    );
    expect(requestUrl(fetchMock, 1)).toBe(
      "https://melonapi.konataizumi.com/v1/trending/current?limit=100&offset=1"
    );
    expect(trending).toHaveLength(2);
    expect(trending[0]).toMatchObject({
      subjectId: 543360,
      nameCn: "测试热播",
      season: { label: "2026 SPRING", name: "SPRING" },
      episodeTotal: 12,
      score: 7.4,
      tags: [{ name: "青春", count: 12 }],
      metaTags: ["TV"],
      nsfw: false,
      url: "https://bangumi.tv/subject/543360"
    });
  });

  it("loads today's schedule and enriches missing covers from Melon subject briefs", async () => {
    const fetchMock = mockJsonResponses(
      {
        date: "2026-06-22",
        items: [
          {
            airingAt: "2026-06-22T14:00:00Z",
            airingAtShanghai: "2026-06-22 22:00",
            weekday: "周一",
            subjectId: 377130,
            name: "Native Name",
            nameCn: "中文名",
            displayName: "中文名",
            type: "tv",
            tags: [{ name: "日常" }],
            metaTags: ["TV"],
            nsfwStatus: "unknown",
            hasSubjectId: true,
            detailAvailable: true,
            needsFallback: { cover: true, episodeTotal: true, nsfw: true },
            url: "https://bangumi.tv/subject/377130",
            sites: []
          },
          {
            airingAt: "2026-06-22T15:00:00Z",
            airingAtShanghai: "2026-06-22 23:00",
            weekday: "周一",
            name: "No Bangumi ID",
            displayName: "No Bangumi ID",
            type: "tv",
            sites: []
          }
        ]
      },
      {
        data: {
          subjectId: 377130,
          name: "Native Name",
          nameCn: "中文名",
          displayName: "中文名",
          coverUrl: "http://lain.bgm.tv/pic/cover/c/27/ff/377130_wDU1x.jpg",
          episodeTotal: 13,
          tags: [{ name: "青春" }],
          metaTags: ["TV"],
          nsfw: false,
          url: "https://bangumi.tv/subject/377130"
        }
      }
    );

    const client = new MelonApiClient();
    const today = await client.getTodaySchedule();

    expect(requestUrl(fetchMock, 1)).toBe(
      "https://melonapi.konataizumi.com/v1/subjects/377130?full=false"
    );
    expect(today.weekday).toMatchObject({ id: 1, cn: "周一", en: "MON" });
    expect(today.items).toHaveLength(2);
    expect(today.items[0]).toMatchObject({
      subjectId: 377130,
      name: "Native Name",
      nameCn: "中文名",
      displayName: "中文名",
      airingAt: "2026-06-22T14:00:00Z",
      airingAtShanghai: "2026-06-22 22:00",
      weekday: "周一",
      coverUrl: "https://lain.bgm.tv/pic/cover/c/27/ff/377130_wDU1x.jpg",
      episodeTotal: 13,
      tags: [{ name: "日常" }],
      metaTags: ["TV"],
      nsfw: false,
      nsfwStatus: "unknown",
      hasSubjectId: true,
      detailAvailable: true,
      needsFallback: { cover: true, episodeTotal: true, nsfw: true },
      url: "https://bangumi.tv/subject/377130"
    });
    expect(today.items[1]).toMatchObject({
      subjectId: undefined,
      name: "No Bangumi ID",
      nameCn: undefined,
      displayName: "No Bangumi ID",
      airingAt: "2026-06-22T15:00:00Z",
      airingAtShanghai: "2026-06-22 23:00",
      weekday: "周一"
    });
  });

  it("extracts the current week from the schedule date window", async () => {
    mockJsonResponse({
      centerDate: "2026-06-22",
      byDate: {
        "2026-06-21": [
          {
            airingAt: "2026-06-21T14:00:00Z",
            airingAtShanghai: "2026-06-21 22:00",
            weekday: "周日",
            subjectId: 1,
            name: "Previous Sunday",
            displayName: "Previous Sunday",
            type: "tv",
            sites: []
          }
        ],
        "2026-06-22": [
          {
            airingAt: "2026-06-22T14:00:00Z",
            airingAtShanghai: "2026-06-22 22:00",
            weekday: "周一",
            subjectId: 2,
            name: "Monday Show",
            displayName: "Monday Show",
            coverUrl: "https://example.com/monday.jpg",
            episodeTotal: 12,
            type: "tv",
            sites: []
          }
        ],
        "2026-06-28": [
          {
            airingAt: "2026-06-28T14:00:00Z",
            airingAtShanghai: "2026-06-28 22:00",
            weekday: "周日",
            subjectId: 3,
            name: "Sunday Show",
            displayName: "Sunday Show",
            coverUrl: "https://example.com/sunday.jpg",
            episodeTotal: 12,
            type: "tv",
            sites: []
          }
        ]
      }
    });

    const client = new MelonApiClient();
    const week = await client.getScheduleWeek();

    expect(week.map((day) => day.weekday.id)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(week[0].items.map((item) => item.subjectId)).toEqual([2]);
    expect(week[6].items.map((item) => item.subjectId)).toEqual([3]);
  });

  it("loads aggregated subject detail fields from Melon API", async () => {
    const fetchMock = mockJsonResponses(
      {
        data: {
          subjectId: 123,
          name: "Test Anime",
          nameCn: "测试动画",
          displayName: "测试动画",
          type: "anime",
          coverUrl: "https://example.com/cover.jpg",
          summary: "Line one.",
          airDate: "2026-04-01",
          platform: "TV",
          episodeTotal: 12,
          rating: { score: 8.2, rank: 42, total: 1234 },
          collectionStats: {
            wish: 10,
            watching: 30,
            completed: 20,
            on_hold: 4,
            dropped: 2
          },
          infoBox: [{ key: "导演", value: "示例监督" }],
          tags: [{ name: "青春", count: 99 }],
          metaTags: ["TV"],
          episodes: [
            {
              episodeId: 1001,
              subjectId: 123,
              type: "main",
              sort: 1,
              ep: 1,
              name: "Episode 1",
              nameCn: "第一话",
              displayName: "第一话"
            },
            {
              episodeId: 1002,
              subjectId: 123,
              type: "op",
              sort: 1,
              name: "OP",
              displayName: "OP"
            }
          ],
          characters: [
            {
              characterId: 1,
              name: "Character",
              displayName: "Character",
              role: "主角",
              imageUrl: "https://example.com/character.jpg",
              actors: [
                {
                  personId: 2,
                  name: "Actor",
                  displayName: "Actor",
                  imageUrl: "https://example.com/actor.jpg",
                  url: "https://example.com"
                }
              ]
            }
          ],
          staff: [
            {
              personId: 3,
              name: "Staff",
              displayName: "Staff",
              role: "导演",
              imageUrl: "https://example.com/staff.jpg",
              url: "https://example.com"
            }
          ],
          relatedSubjects: [],
          comments: [{ user: { nickname: "Detail User" }, text: "Detail comment" }],
          topics: [
            { title: "Detail topic", replies: 3, url: "https://bangumi.tv/subject/topic/1" }
          ],
          schedule: { weekday: "周一", source: "bangumi-data" },
          source: { notes: ["comments unavailable"] }
        }
      },
      { data: [{ user: { nickname: "User" }, text: "Comment" }] },
      { data: [{ title: "Topic", replies: 3, url: "https://bangumi.tv/subject/topic/2" }] }
    );

    const client = new MelonApiClient();
    const subject = await client.getSubject(123);

    expect(requestUrl(fetchMock)).toBe("https://melonapi.konataizumi.com/v1/subjects/123");
    expect(requestUrl(fetchMock, 1)).toBe(
      "https://melonapi.konataizumi.com/v1/subjects/123/comments"
    );
    expect(requestUrl(fetchMock, 2)).toBe(
      "https://melonapi.konataizumi.com/v1/subjects/123/topics"
    );

    expect(subject).toMatchObject({
      id: 123,
      nameCn: "测试动画",
      ratingCount: 1234,
      rank: 42,
      score: 8.2,
      collectionStats: { watching: 30 },
      infoBox: [{ key: "导演", value: "示例监督" }],
      characters: [
        {
          characterId: 1,
          role: "主角",
          imageUrl: "https://example.com/character.jpg",
          actors: [{ name: "Actor", imageUrl: "https://example.com/actor.jpg" }]
        }
      ],
      staff: [{ role: "导演", name: "Staff", imageUrl: "https://example.com/staff.jpg" }],
      comments: [{ text: "Comment" }],
      topics: [{ title: "Topic", url: "https://bangumi.tv/subject/topic/2" }],
      schedule: { weekday: "周一" },
      sourceNotes: ["comments unavailable"]
    });
    expect(subject.episodes).toEqual([
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

  it("does not fall back to detail comments when independent comments are unavailable", async () => {
    const fetchMock = vi.fn(
      (input: Parameters<typeof fetch>[0], init?: Parameters<typeof fetch>[1]) => {
        void init;
        const url =
          typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
        if (url.endsWith("/comments")) {
          return Promise.resolve(new Response("{}", { status: 502 }));
        }
        if (url.endsWith("/topics")) {
          return Promise.resolve(
            jsonResponse({
              data: [{ title: "Fresh topic", url: "https://bangumi.tv/subject/topic/3" }]
            })
          );
        }

        return Promise.resolve(
          jsonResponse({
            data: {
              subjectId: 123,
              name: "Test Anime",
              displayName: "Test Anime",
              type: "anime",
              episodeTotal: 12,
              comments: [{ user: { nickname: "Detail User" }, text: "Detail comment" }],
              topics: [{ title: "Detail topic", url: "https://bangumi.tv/subject/topic/1" }],
              episodes: []
            }
          })
        );
      }
    );
    vi.stubGlobal("fetch", fetchMock);

    const client = new MelonApiClient();
    const subject = await client.getSubject(123);

    expect(requestUrl(fetchMock, 1)).toBe(
      "https://melonapi.konataizumi.com/v1/subjects/123/comments"
    );
    expect(subject.comments).toBeUndefined();
    expect(subject.topics).toEqual([
      { title: "Fresh topic", url: "https://bangumi.tv/subject/topic/3" }
    ]);
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

function mockJsonResponses(...payloads: unknown[]) {
  let responseIndex = 0;
  const fetchMock = vi.fn(
    (input: Parameters<typeof fetch>[0], init?: Parameters<typeof fetch>[1]) => {
      void input;
      void init;
      const payload = payloads[Math.min(responseIndex, payloads.length - 1)];
      responseIndex += 1;
      return Promise.resolve(jsonResponse(payload));
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

function jsonResponse(payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: { "Content-Type": "application/json" }
  });
}
