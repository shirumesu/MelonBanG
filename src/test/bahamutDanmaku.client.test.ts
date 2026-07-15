import { describe, expect, it, vi } from "vitest";
import { BahamutDanmakuClient } from "../main/danmaku/bahamutDanmakuClient";

describe("BahamutDanmakuClient", () => {
  it("accepts one unambiguous cross-script title and still requires the exact episode", async () => {
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        htmlResponse(`
          <div class="theme-list-block">
            <img alt="葬送的芙莉蓮" />
            <a href="animeRef.php?sn=113366" class="theme-list-main">葬送的芙莉蓮</a>
          </div>
        `)
      )
      .mockResolvedValueOnce(
        htmlResponse(`
          <a href="animeVideo.php?sn=35241">[1] 冒險的結束</a>
          <a href="animeVideo.php?sn=35242">[2] 不一定非得是魔法</a>
        `)
      )
      .mockResolvedValueOnce(
        jsonResponse([
          { text: "滚动", color: "#FFFFFF", position: 0, time: 125 },
          { text: "顶部", color: "#FF0026", position: 1, time: 200 },
          { text: "底部", color: "#00C3FC", position: 2, time: 300 }
        ])
      );
    const client = new BahamutDanmakuClient({ fetchImpl });

    const result = await client.loadAutomatic({
      animeTitles: ["葬送的芙莉莲", "葬送のフリーレン"],
      episodeNumber: 2
    });

    const searchRequest = fetchImpl.mock.calls[0];
    expect(searchRequest?.[0]).toBe("https://ani.gamer.com.tw/search.php");
    expect(searchRequest?.[1]).toMatchObject({ method: "POST" });
    expect(typeof searchRequest?.[1]?.body === "string" ? searchRequest[1].body : "").toBe(
      "keyword=%E8%91%AC%E9%80%81%E7%9A%84%E8%8A%99%E8%8E%89%E8%8E%B2"
    );
    expect(fetchImpl.mock.calls[1]?.[0]).toBe("https://ani.gamer.com.tw/animeRef.php?sn=113366");
    expect(fetchImpl.mock.calls[2]?.[0]).toBe("https://ani.gamer.com.tw/ajax/danmuGet.php");
    expect(result).toEqual({
      provider: "bahamut",
      locator: "sn=35242",
      matchLabel: "葬送的芙莉蓮 · 第2话 不一定非得是魔法",
      items: [
        { timeSeconds: 12.5, text: "滚动", mode: "scroll", color: "#ffffff" },
        { timeSeconds: 20, text: "顶部", mode: "top", color: "#ff0026" },
        { timeSeconds: 30, text: "底部", mode: "bottom", color: "#00c3fc" }
      ]
    });
  });

  it("loads a manually supplied Anime Video sn or URL", async () => {
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse([{ text: "手动弹幕", color: "#FFFFFF", position: 0, time: 80 }])
      );
    const client = new BahamutDanmakuClient({ fetchImpl });

    const result = await client.loadByLocator("https://ani.gamer.com.tw/animeVideo.php?sn=35241");

    expect(fetchImpl.mock.calls[0]?.[1]?.body).toBe("sn=35241");
    expect(result.locator).toBe("sn=35241");
    expect(result.items[0]).toEqual({
      timeSeconds: 8,
      text: "手动弹幕",
      mode: "scroll",
      color: "#ffffff"
    });
  });
});

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "content-type": "application/json" }
  });
}

function htmlResponse(value: string): Response {
  return new Response(value, {
    status: 200,
    headers: { "content-type": "text/html; charset=utf-8" }
  });
}
