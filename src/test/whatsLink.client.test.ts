import { afterEach, describe, expect, it, vi } from "vitest";
import { parseWhatsLinkResponse, WhatsLinkClient } from "../main/download/whatsLinkClient";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("WhatsLinkClient", () => {
  it("maps whatslink link metadata into download preview metadata", () => {
    expect(
      parseWhatsLinkResponse({
        error: "",
        type: "FILE",
        file_type: "video",
        name: "[Haruhana] Kamiina Botan, Yoeru Sugata wa Yuri no Hana - 11.mkv",
        size: 253418173,
        count: 1,
        screenshots: [
          { time: 0, screenshot: "not-a-url" },
          {
            time: 0,
            screenshot: "https://whatslink.info/image/2dcbdefbac60dffb83af326e2f994a91"
          }
        ]
      })
    ).toEqual({
      title: "[Haruhana] Kamiina Botan, Yoeru Sugata wa Yuri no Hana - 11.mkv",
      totalBytes: 253418173,
      imageUrl: "https://whatslink.info/image/2dcbdefbac60dffb83af326e2f994a91",
      sourceName: "whatslink.info",
      sourceUrl: "https://whatslink.info/"
    });
  });

  it("ignores failed whatslink responses", () => {
    expect(parseWhatsLinkResponse({ error: "not found" })).toBeNull();
  });

  it("embeds the preview image so the cache page does not depend on a later remote image load", async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            error: "",
            name: "Sample Anime.mkv",
            screenshots: [{ screenshot: "https://whatslink.info/image/example" }]
          }),
          { status: 200, headers: { "content-type": "application/json" } }
        )
      )
      .mockResolvedValueOnce(
        new Response(new Uint8Array([1, 2, 3]), {
          status: 200,
          headers: { "content-type": "image/jpeg" }
        })
      );
    vi.stubGlobal("fetch", fetchMock);

    const preview = await new WhatsLinkClient().getPreview({
      kind: "magnet",
      uri: "magnet:?xt=urn:btih:C5PPDMBT7OKFBO4A4MGUK3LLHSDP4BKG"
    });

    expect(preview?.imageUrl).toBe("data:image/jpeg;base64,AQID");
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
