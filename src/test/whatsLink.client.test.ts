import { describe, expect, it } from "vitest";
import { parseWhatsLinkResponse } from "../main/download/whatsLinkClient";

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
});
