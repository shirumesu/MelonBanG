import { describe, expect, it, vi } from "vitest";
import type {
  DownloadEpisodeContext,
  DownloadTaskView,
  TorrentInput
} from "../shared/contracts/download";
import {
  SourceService,
  type BuiltInSourcePack,
  type SourceDownloadService
} from "../main/sources/sourceService";

const mikanPack: BuiltInSourcePack = {
  id: "mikan",
  name: "蜜柑计划",
  origin: "https://mikanani.me",
  searchUrlTemplate: "https://mikanani.me/RSS/Search?searchstr={keyword}",
  resultKind: "torrent-enclosure",
  capabilities: ["http.get", "parse.rss"]
};

const dmhyPack: BuiltInSourcePack = {
  id: "dmhy",
  name: "动漫花园",
  origin: "https://share.dmhy.org",
  searchUrlTemplate: "https://share.dmhy.org/topics/rss/rss.xml?keyword={keyword}",
  resultKind: "magnet-enclosure",
  capabilities: ["http.get", "parse.rss"]
};

const mikanRss = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:torrent="https://mikanani.me/0.1/">
  <channel>
    <item>
      <title><![CDATA[[Lilith-Raws] 葬送的芙莉莲 - 01 [Baha][WEB-DL][1080p][AVC AAC][CHT][MP4]]]></title>
      <link>https://mikanani.me/Home/Episode/0123456789abcdef0123456789abcdef01234567</link>
      <pubDate>2026-07-10T20:30:00</pubDate>
      <enclosure url="https://mikanani.me/Download/20260710/0123456789abcdef0123456789abcdef01234567.torrent" length="734003200" type="application/x-bittorrent" />
    </item>
  </channel>
</rss>`;

const dmhyMagnet = "magnet:?xt=urn:btih:ABCDEFGHIJKLMNOPQRSTUVWXYZ234567&amp;dn=%E8%91%AC%E9%80%81";
const dmhyRss = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <item>
      <title><![CDATA[[桜都字幕组] 葬送的芙莉莲 [01][1080P]]]></title>
      <link>http://share.dmhy.org/topics/view/123456_test.html</link>
      <pubDate>Fri, 10 Jul 2026 20:30:00 +0800</pubDate>
      <enclosure url="${dmhyMagnet}" length="1" type="application/x-bittorrent" />
    </item>
  </channel>
</rss>`;

describe("SourceService", () => {
  it("normalizes Mikan torrent and DMHY magnet RSS items without trusting DMHY length", async () => {
    const service = createService((url) => {
      if (url.startsWith(mikanPack.origin)) {
        return Promise.resolve(xmlResponse(mikanRss));
      }
      return Promise.resolve(xmlResponse(dmhyRss));
    });

    const result = await service.search({
      subjectId: 13,
      episodeId: 501,
      keyword: "葬送的芙莉莲 01"
    });

    expect(result.providers).toEqual([
      { providerId: "mikan", providerName: "蜜柑计划", status: "ok", resultCount: 1 },
      { providerId: "dmhy", providerName: "动漫花园", status: "ok", resultCount: 1 }
    ]);
    expect(
      result.candidates.map((candidate) => ({
        providerId: candidate.providerId,
        providerName: candidate.providerName,
        providerItemId: candidate.providerItemId,
        title: candidate.title,
        detailUrl: candidate.detailUrl,
        publishedAt: candidate.publishedAt,
        sizeBytes: candidate.sizeBytes,
        downloadKind: candidate.downloadKind
      }))
    ).toEqual([
      {
        providerId: "mikan",
        providerName: "蜜柑计划",
        providerItemId: "0123456789abcdef0123456789abcdef01234567",
        title: "[Lilith-Raws] 葬送的芙莉莲 - 01 [Baha][WEB-DL][1080p][AVC AAC][CHT][MP4]",
        detailUrl: "https://mikanani.me/Home/Episode/0123456789abcdef0123456789abcdef01234567",
        publishedAt: "2026-07-10T20:30:00.000Z",
        sizeBytes: 734003200,
        downloadKind: "torrentFile"
      },
      {
        providerId: "dmhy",
        providerName: "动漫花园",
        providerItemId: "123456",
        title: "[桜都字幕组] 葬送的芙莉莲 [01][1080P]",
        detailUrl: "https://share.dmhy.org/topics/view/123456_test.html",
        publishedAt: "2026-07-10T12:30:00.000Z",
        sizeBytes: null,
        downloadKind: "magnet"
      }
    ]);
  });

  it("keeps working provider candidates when another provider fails", async () => {
    const service = createService((url) => {
      if (url.startsWith(mikanPack.origin)) {
        return Promise.resolve(new Response("upstream unavailable", { status: 503 }));
      }
      return Promise.resolve(xmlResponse(dmhyRss));
    });

    const result = await service.search({ subjectId: 13, keyword: "葬送的芙莉莲" });

    expect(result.candidates).toHaveLength(1);
    expect(result.candidates[0]?.providerId).toBe("dmhy");
    expect(result.providers).toEqual([
      {
        providerId: "mikan",
        providerName: "蜜柑计划",
        status: "error",
        resultCount: 0,
        message: "蜜柑计划暂时不可用（HTTP 503）。"
      },
      { providerId: "dmhy", providerName: "动漫花园", status: "ok", resultCount: 1 }
    ]);
  });

  it("searches title variants concurrently and merges their distinct releases", async () => {
    const alternateHash = "89abcdef0123456789abcdef0123456789abcdef";
    const alternateRss = mikanRss
      .replaceAll("0123456789abcdef0123456789abcdef01234567", alternateHash)
      .replace("葬送的芙莉莲", "元祖！邦多利酱");
    let inFlight = 0;
    let peakInFlight = 0;
    const urls: string[] = [];
    const service = new SourceService({
      packs: [mikanPack],
      fetchImpl: async (url) => {
        urls.push(url);
        inFlight += 1;
        peakInFlight = Math.max(peakInFlight, inFlight);
        await new Promise((resolve) => setTimeout(resolve, 5));
        inFlight -= 1;
        return xmlResponse(
          url.includes(encodeURIComponent("元祖！邦多利酱 40")) ? alternateRss : mikanRss
        );
      },
      downloadService: { create: () => downloadTask() },
      now: () => new Date("2026-07-11T00:00:00.000Z")
    });

    const result = await service.search({
      subjectId: 540449,
      episodeId: 40,
      keyword: "元祖！BanG Dream Chan 40",
      keywords: ["元祖！邦多利酱 40"]
    });

    expect(urls).toHaveLength(2);
    expect(peakInFlight).toBe(2);
    expect(result.candidates.map((candidate) => candidate.providerItemId)).toEqual([
      "0123456789abcdef0123456789abcdef01234567",
      alternateHash
    ]);
    expect(result.providers[0]).toMatchObject({ status: "ok", resultCount: 2 });
  });

  it("keeps successful title variants when another variant fails", async () => {
    const service = new SourceService({
      packs: [mikanPack],
      fetchImpl: (url) =>
        Promise.resolve(
          url.includes(encodeURIComponent("元祖！邦多利酱 40"))
            ? xmlResponse(mikanRss)
            : new Response("upstream unavailable", { status: 503 })
        ),
      downloadService: { create: () => downloadTask() },
      now: () => new Date("2026-07-11T00:00:00.000Z")
    });

    const result = await service.search({
      subjectId: 540449,
      episodeId: 40,
      keyword: "元祖！BanG Dream Chan 40",
      keywords: ["元祖！邦多利酱 40"]
    });

    expect(result.candidates).toHaveLength(1);
    expect(result.providers).toEqual([
      { providerId: "mikan", providerName: "蜜柑计划", status: "ok", resultCount: 1 }
    ]);
  });

  it("deduplicates the same release returned by multiple title variants", async () => {
    const service = new SourceService({
      packs: [mikanPack],
      fetchImpl: () => Promise.resolve(xmlResponse(mikanRss)),
      downloadService: { create: () => downloadTask() },
      now: () => new Date("2026-07-11T00:00:00.000Z")
    });

    const result = await service.search({
      subjectId: 540449,
      episodeId: 40,
      keyword: "元祖！BanG Dream Chan 40",
      keywords: ["BanG Dream Chan 40", "元祖！邦多利酱 40"]
    });

    expect(result.candidates).toHaveLength(1);
    expect(result.providers[0]).toMatchObject({ status: "ok", resultCount: 1 });
  });

  it("reuses a recent provider query without reusing opaque candidate ids", async () => {
    const fetchImpl = vi.fn(() => Promise.resolve(xmlResponse(mikanRss)));
    const service = new SourceService({
      packs: [mikanPack],
      fetchImpl,
      downloadService: { create: () => downloadTask() },
      now: () => new Date("2026-07-11T00:00:00.000Z")
    });

    const first = await service.search({ subjectId: 13, keyword: "葬送的芙莉莲 01" });
    const second = await service.search({ subjectId: 13, keyword: "葬送的芙莉莲 01" });

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(second.candidates[0]?.providerItemId).toBe(first.candidates[0]?.providerItemId);
    expect(second.candidates[0]?.candidateId).not.toBe(first.candidates[0]?.candidateId);
  });

  it("enqueues only an opaque stored candidate and hands bounded torrent bytes to downloads", async () => {
    const create = vi.fn<
      (input: TorrentInput, context?: DownloadEpisodeContext) => DownloadTaskView
    >(() => downloadTask());
    const service = createService(
      (url) => {
        if (url.includes("/RSS/Search")) {
          return Promise.resolve(xmlResponse(mikanRss));
        }
        if (url.endsWith(".torrent")) {
          return Promise.resolve(
            new Response(Uint8Array.from([100, 56, 58, 97, 110, 110, 111, 117, 110, 99, 101]))
          );
        }
        return Promise.resolve(xmlResponse(dmhyRss));
      },
      { create }
    );
    const result = await service.search({
      subjectId: 13,
      episodeId: 501,
      keyword: "葬送的芙莉莲 01"
    });
    const mikan = result.candidates.find((candidate) => candidate.providerId === "mikan");

    await expect(
      service.enqueue({ candidateId: "https://evil.example/file.torrent" })
    ).rejects.toThrow("资源已过期，请重新搜索。");
    await service.enqueue({ candidateId: mikan!.candidateId });

    expect(create).toHaveBeenCalledTimes(1);
    expect(create).toHaveBeenCalledWith(
      {
        kind: "torrentFile",
        name: "[Lilith-Raws] 葬送的芙莉莲 - 01 [Baha][WEB-DL][1080p][AVC AAC][CHT][MP4].torrent",
        bytes: Uint8Array.from([100, 56, 58, 97, 110, 110, 111, 117, 110, 99, 101])
      },
      {
        subjectId: 13,
        episodeId: 501
      }
    );
  });
});

function createService(
  fetchImpl: (url: string) => Promise<Response>,
  downloadService: SourceDownloadService = { create: () => downloadTask() }
): SourceService {
  return new SourceService({
    packs: [mikanPack, dmhyPack],
    fetchImpl,
    downloadService,
    now: () => new Date("2026-07-11T00:00:00.000Z")
  });
}

function xmlResponse(xml: string): Response {
  return new Response(xml, {
    status: 200,
    headers: { "content-type": "application/xml; charset=utf-8" }
  });
}

function downloadTask(): DownloadTaskView {
  return {
    id: "8c75b705-2c81-4f5f-b48a-75b5b8f81e71",
    subjectId: null,
    episodeId: null,
    title: "test",
    status: "metadata",
    progress: 0,
    downloadedBytes: 0,
    totalBytes: null,
    downloadSpeedBytesPerSecond: 0,
    uploadSpeedBytesPerSecond: 0,
    peerCount: 0,
    etaSeconds: null,
    selectedFileId: null,
    errorMessage: null,
    previewImageUrl: null,
    previewSourceName: null,
    previewSourceUrl: null,
    createdAt: "2026-07-11T00:00:00.000Z",
    updatedAt: "2026-07-11T00:00:00.000Z"
  };
}
