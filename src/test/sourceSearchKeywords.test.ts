import { describe, expect, it } from "vitest";
import { buildSubjectSourceKeywords } from "../renderer/features/sources/sourceSearchKeywords";

describe("buildSubjectSourceKeywords", () => {
  it("uses Bangumi aliases and a mixed-script core for episode resource recall", () => {
    expect(
      buildSubjectSourceKeywords(
        {
          name: "元祖！バンドリちゃん",
          nameCn: "元祖！BanG Dream Chan",
          infoBox: [
            { key: "中文名", value: "元祖！BanG Dream Chan" },
            { key: "别名", value: "元祖！邦多利酱" }
          ]
        },
        40,
        "元祖！BanG Dream Chan 40"
      )
    ).toEqual([
      "元祖！BanG Dream Chan 40",
      "元祖！邦多利酱 40",
      "BanG Dream Chan 40",
      "元祖！バンドリちゃん 40"
    ]);
  });

  it("keeps a manual query first while bounding and deduplicating variants", () => {
    expect(
      buildSubjectSourceKeywords(
        {
          name: "Original",
          nameCn: "中文名",
          infoBox: [
            { key: "别名", value: "别名一 / 别名二 / 别名三 / 别名四 / 别名五" },
            { key: "制作", value: "不应成为搜索词" }
          ]
        },
        2,
        "  自定义搜索 02  "
      )
    ).toEqual(["自定义搜索 02", "中文名 02", "别名一 02", "别名二 02", "别名三 02"]);
  });
});
