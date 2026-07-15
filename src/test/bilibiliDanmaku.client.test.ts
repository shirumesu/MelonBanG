import { describe, expect, it, vi } from "vitest";
import { BilibiliDanmakuClient } from "../main/danmaku/bilibiliDanmakuClient";

describe("BilibiliDanmakuClient", () => {
  it("matches an exact Bangumi title and episode before combining segmented danmaku", async () => {
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse({
          code: 0,
          data: {
            result: [
              {
                title: '<em class="keyword">元祖！BanG Dream Chan</em>',
                org_title: "Ganso! Bandori-chan",
                season_id: 55001,
                eps: [
                  { id: 900039, title: "39", index_title: "39", long_title: "上一话" },
                  { id: 900040, title: "40", index_title: "40", long_title: "约在RiNG见" }
                ]
              }
            ]
          }
        })
      )
      .mockResolvedValueOnce(
        jsonResponse({
          code: 0,
          result: {
            title: "元祖！BanG Dream Chan",
            episodes: [
              {
                id: 900040,
                aid: 800040,
                bvid: "BV1TestAuto40",
                cid: 700040,
                duration: 720_000,
                title: "40",
                long_title: "约在RiNG见"
              }
            ]
          }
        })
      )
      .mockResolvedValueOnce(new Response("not available", { status: 404 }))
      .mockResolvedValueOnce(
        binaryResponse(
          encodeSegment([
            { progress: 12_500, mode: 1, color: 0xffffff, content: "第一段" },
            { progress: 20_000, mode: 5, color: 0xff0000, content: "顶部" }
          ])
        )
      )
      .mockResolvedValueOnce(
        binaryResponse(encodeSegment([{ progress: 365_000, mode: 4, color: 0, content: "第二段" }]))
      );
    const client = new BilibiliDanmakuClient({ fetchImpl });

    const result = await client.loadAutomatic({
      animeTitles: ["元祖！BanG Dream Chan", "Ganso! Bandori-chan"],
      episodeNumber: 40
    });

    expect(fetchImpl).toHaveBeenCalledTimes(5);
    expect(requestUrl(fetchImpl.mock.calls[0]?.[0])).toContain("search_type=media_bangumi");
    expect(requestUrl(fetchImpl.mock.calls[0]?.[0])).toContain(
      "keyword=%E5%85%83%E7%A5%96%EF%BC%81BanG+Dream+Chan"
    );
    expect(fetchImpl.mock.calls.slice(2).map(([url]) => requestUrl(url))).toEqual([
      "https://comment.bilibili.com/700040.xml",
      "https://api.bilibili.com/x/v2/dm/web/seg.so?type=1&oid=700040&segment_index=1",
      "https://api.bilibili.com/x/v2/dm/web/seg.so?type=1&oid=700040&segment_index=2"
    ]);
    expect(result).toEqual({
      provider: "bilibili",
      locator: "ep900040",
      matchLabel: "元祖！BanG Dream Chan · 第40话 约在RiNG见",
      items: [
        { timeSeconds: 12.5, text: "第一段", mode: "scroll", color: "#ffffff" },
        { timeSeconds: 20, text: "顶部", mode: "top", color: "#ff0000" },
        { timeSeconds: 365, text: "第二段", mode: "bottom", color: "#000000" }
      ]
    });
  });

  it("loads the requested page from a BV locator", async () => {
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse({
          code: 0,
          data: {
            bvid: "BV1ManualTest",
            title: "手动视频",
            pages: [
              { page: 1, cid: 1001, part: "第一话", duration: 300 },
              { page: 2, cid: 1002, part: "第二话", duration: 300 }
            ]
          }
        })
      )
      .mockResolvedValueOnce(xmlResponse(createXmlComments(299)));
    const client = new BilibiliDanmakuClient({ fetchImpl });

    const result = await client.loadByLocator("https://www.bilibili.com/video/BV1ManualTest?p=2");

    expect(requestUrl(fetchImpl.mock.calls[0]?.[0])).toBe(
      "https://api.bilibili.com/x/web-interface/view?bvid=BV1ManualTest"
    );
    expect(result.matchLabel).toBe("手动视频 · P2 第二话");
    expect(requestUrl(fetchImpl.mock.calls[1]?.[0])).toBe("https://comment.bilibili.com/1002.xml");
    expect(result.items).toHaveLength(299);
    expect(result.items[0]).toEqual({
      timeSeconds: 0,
      text: "弹幕 1 & 测试",
      mode: "scroll",
      color: "#ffffff"
    });
  });

  it("finds an EP stored in a season section instead of the main episode list", async () => {
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        jsonResponse({
          code: 0,
          result: {
            title: "BanG Dream! 梦想协奏曲 第三季",
            episodes: [
              {
                id: 308426,
                aid: 1,
                bvid: "BV1Main",
                cid: 100,
                duration: 1_440_000,
                title: "1",
                long_title: "主剧集"
              }
            ],
            section: [
              {
                id: 226990,
                title: "元祖迷你动画",
                episodes: [
                  {
                    id: 4390855,
                    aid: 116764004391516,
                    bvid: "BV1Section",
                    cid: 39181157884,
                    duration: 91_000,
                    title: "元祖迷你37",
                    long_title: "约在RiNG见"
                  }
                ]
              },
              {
                id: 49014,
                title: "次元发电机专访",
                episodes: [
                  {
                    id: 147826,
                    aid: 0,
                    bvid: null,
                    cid: 0,
                    duration: null,
                    title: "次元发电机 小山百代",
                    long_title: null
                  }
                ]
              }
            ]
          }
        })
      )
      .mockResolvedValueOnce(
        xmlResponse('<i><d p="8.5,1,25,16777215,0,0,hash,1">附加章节弹幕</d></i>')
      );
    const client = new BilibiliDanmakuClient({ fetchImpl });

    const result = await client.loadByLocator("ep4390855");

    expect(result.locator).toBe("ep4390855");
    expect(result.matchLabel).toBe("BanG Dream! 梦想协奏曲 第三季 · 元祖迷你37 约在RiNG见");
    expect(result.items).toEqual([
      {
        timeSeconds: 8.5,
        text: "附加章节弹幕",
        mode: "scroll",
        color: "#ffffff"
      }
    ]);
  });
});

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "content-type": "application/json" }
  });
}

function requestUrl(input: string | URL | Request | undefined): string {
  if (typeof input === "string") return input;
  if (input instanceof URL) return input.toString();
  return input?.url ?? "";
}

function binaryResponse(value: Uint8Array): Response {
  return new Response(value, {
    status: 200,
    headers: { "content-type": "application/octet-stream" }
  });
}

function xmlResponse(value: string): Response {
  return new Response(value, {
    status: 200,
    headers: { "content-type": "text/xml; charset=utf-8" }
  });
}

function createXmlComments(count: number): string {
  const comments = Array.from({ length: count }, (_, index) => {
    const time = index / 10;
    return `<d p="${time},1,25,16777215,0,0,hash,${index + 1}">弹幕 ${index + 1} &amp; 测试</d>`;
  });
  return `<i>${comments.join("")}</i>`;
}

function encodeSegment(
  items: Array<{ progress: number; mode: number; color: number; content: string }>
): Uint8Array {
  return concatBytes(
    items.map((item) => {
      const message = concatBytes([
        fieldVarint(2, item.progress),
        fieldVarint(3, item.mode),
        fieldVarint(5, item.color),
        fieldString(7, item.content)
      ]);
      return concatBytes([encodeVarint((1 << 3) | 2), encodeVarint(message.length), message]);
    })
  );
}

function fieldVarint(field: number, value: number): Uint8Array {
  return concatBytes([encodeVarint(field << 3), encodeVarint(value)]);
}

function fieldString(field: number, value: string): Uint8Array {
  const bytes = new TextEncoder().encode(value);
  return concatBytes([encodeVarint((field << 3) | 2), encodeVarint(bytes.length), bytes]);
}

function encodeVarint(value: number): Uint8Array {
  const bytes: number[] = [];
  let remaining = value;
  while (remaining >= 0x80) {
    bytes.push((remaining & 0x7f) | 0x80);
    remaining = Math.floor(remaining / 0x80);
  }
  bytes.push(remaining);
  return Uint8Array.from(bytes);
}

function concatBytes(parts: Uint8Array[] | Uint8Array[][]): Uint8Array {
  const flat = parts.flat();
  const output = new Uint8Array(flat.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of flat) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}
