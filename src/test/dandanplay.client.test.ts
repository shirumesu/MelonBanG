import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DandanplayClient } from "../main/danmaku/dandanplayClient";

const temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("DandanplayClient", () => {
  it("matches the selected file and normalizes shifted comments", async () => {
    const filePath = createMediaFile("Sample Episode.mkv", "sample-video");
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse({
          success: true,
          errorCode: 0,
          isMatched: true,
          matches: [
            {
              episodeId: 120001,
              animeId: 9001,
              animeTitle: "Sample Anime",
              episodeTitle: "Episode 1",
              shift: 1.25
            }
          ]
        })
      )
      .mockResolvedValueOnce(
        jsonResponse({
          count: 6,
          comments: [
            { cid: 1, p: "12.5,1,16777215,100", m: "滚动" },
            { cid: 2, p: "20,4,0,101", m: "底部" },
            { cid: 3, p: "30,5,16711680,102", m: "顶部" },
            { cid: 4, p: "bad,1,16777215,103", m: "无效时间" },
            { cid: 5, p: "40,7,16777215,104", m: "不支持的模式" },
            { cid: 6, p: "50,1,16777215,105", m: "   " }
          ]
        })
      );
    const client = new DandanplayClient({
      appId: "test-app-id",
      appSecret: "test-app-secret",
      fetchImpl
    });

    const result = await client.loadForFile({ filePath, videoDurationSeconds: 1450.4 });

    expect(fetchImpl).toHaveBeenCalledTimes(2);
    const [matchUrl, matchOptions] = fetchImpl.mock.calls[0];
    expect(matchUrl).toBe("https://api.dandanplay.net/api/v2/match");
    expect(matchOptions).toMatchObject({ method: "POST", redirect: "follow" });
    expect(new Headers(matchOptions?.headers).get("X-AppId")).toBe("test-app-id");
    expect(new Headers(matchOptions?.headers).get("X-AppSecret")).toBe("test-app-secret");
    const matchBody = typeof matchOptions?.body === "string" ? matchOptions.body : "";
    expect(JSON.parse(matchBody)).toEqual({
      fileName: "Sample Episode",
      fileHash: "e91dc9d263af300f977446554f13ffee",
      fileSize: 12,
      videoDuration: 1450,
      matchMode: "hashAndFileName"
    });
    expect(fetchImpl.mock.calls[1]?.[0]).toBe(
      "https://api.dandanplay.net/api/v2/comment/120001?withRelated=true&chConvert=1"
    );
    expect(result).toEqual({
      provider: "dandanplay",
      episodeId: 120001,
      animeTitle: "Sample Anime",
      episodeTitle: "Episode 1",
      items: [
        { timeSeconds: 13.75, text: "滚动", mode: "scroll", color: "#ffffff" },
        { timeSeconds: 21.25, text: "底部", mode: "bottom", color: "#000000" },
        { timeSeconds: 31.25, text: "顶部", mode: "top", color: "#ff0000" }
      ]
    });
  });

  it("refuses to guess between ambiguous fuzzy matches", async () => {
    const filePath = createMediaFile("Ambiguous.mkv", "sample-video");
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValueOnce(
      jsonResponse({
        success: true,
        errorCode: 0,
        isMatched: false,
        matches: [
          { episodeId: 1, animeId: 1, animeTitle: "A", episodeTitle: "1", shift: 0 },
          { episodeId: 2, animeId: 2, animeTitle: "B", episodeTitle: "1", shift: 0 }
        ]
      })
    );
    const client = new DandanplayClient({
      appId: "test-app-id",
      appSecret: "test-app-secret",
      fetchImpl
    });

    await expect(client.loadForFile({ filePath, videoDurationSeconds: null })).rejects.toThrow(
      "弹弹play返回了多个候选，暂未自动选择弹幕库。"
    );
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("searches candidate episodes and loads the episode selected by the user", async () => {
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse({
          success: true,
          errorCode: 0,
          hasMore: false,
          animes: [
            {
              animeId: 19356,
              animeTitle: "元祖！BanG Dream Chan",
              type: "web",
              typeDescription: "网络放送",
              episodes: [
                {
                  episodeId: 193560037,
                  episodeTitle: "第37话 约在RiNG见"
                }
              ]
            }
          ]
        })
      )
      .mockResolvedValueOnce(
        jsonResponse({
          comments: [{ p: "8.5,1,16777215,100", m: "手动选择后的弹幕" }]
        })
      );
    const client = new DandanplayClient({
      appId: "test-app-id",
      appSecret: "test-app-secret",
      fetchImpl
    });

    const candidates = await client.searchEpisodes({ anime: "元祖！" });
    const selected = await client.loadForEpisode(193560037);

    expect(fetchImpl.mock.calls[0]?.[0]).toBe(
      "https://api.dandanplay.net/api/v2/search/episodes?anime=%E5%85%83%E7%A5%96%EF%BC%81"
    );
    expect(candidates).toEqual([
      {
        animeId: 19356,
        animeTitle: "元祖！BanG Dream Chan",
        type: "web",
        typeDescription: "网络放送",
        episodeId: 193560037,
        episodeTitle: "第37话 约在RiNG见"
      }
    ]);
    expect(fetchImpl.mock.calls[1]?.[0]).toBe(
      "https://api.dandanplay.net/api/v2/comment/193560037?withRelated=true&chConvert=1"
    );
    expect(selected).toEqual({
      provider: "dandanplay",
      episodeId: 193560037,
      animeTitle: null,
      episodeTitle: null,
      items: [
        {
          timeSeconds: 8.5,
          text: "手动选择后的弹幕",
          mode: "scroll",
          color: "#ffffff"
        }
      ]
    });
  });

  it("does not expose credentials or local paths through provider errors", async () => {
    const filePath = createMediaFile("Private Episode.mkv", "sample-video");
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(new Response("test-app-secret " + filePath, { status: 401 }));
    const client = new DandanplayClient({
      appId: "test-app-id",
      appSecret: "test-app-secret",
      fetchImpl
    });

    const error = await client
      .loadForFile({ filePath, videoDurationSeconds: null })
      .then(() => null)
      .catch((reason: unknown) => reason);

    expect(error).toBeInstanceOf(Error);
    expect((error as Error).message).toBe("弹弹play匹配请求失败（HTTP 401）。");
    expect((error as Error).message).not.toContain("test-app-secret");
    expect((error as Error).message).not.toContain(filePath);
  });
});

function createMediaFile(name: string, content: string): string {
  const directory = mkdtempSync(join(tmpdir(), "melonbang-dandanplay-"));
  temporaryDirectories.push(directory);
  const filePath = join(directory, name);
  writeFileSync(filePath, content);
  return filePath;
}

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "content-type": "application/json" }
  });
}
