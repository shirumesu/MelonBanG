import { describe, expect, it } from "vitest";
import {
  buildSourceFilterOptions,
  matchesSourceCandidateFilters,
  parseSourceCandidateTitle,
  resolveCandidateEpisodeId,
  type FilterableSourceCandidate,
  type SourceCandidateFilters
} from "../renderer/features/sources/sourceCandidateMetadata";

describe("parseSourceCandidateTitle", () => {
  it("extracts release group, episode, resolution and embedded simplified subtitles", () => {
    expect(
      parseSourceCandidateTitle(
        "[Prejudice-Studio] 元祖！BanG Dream Chan Ganso! Bandori-chan - 40 [Bilibili WEB-DL 1080p AVC 8bit AAC MP4][简体内嵌]"
      )
    ).toEqual({
      releaseGroup: "Prejudice-Studio",
      episodeRange: { start: 40, end: 40 },
      resolution: "1080P",
      subtitleLanguages: ["chs"],
      subtitleKind: "内嵌"
    });
  });

  it("recognizes ranges and multi-language external subtitles without confusing codec numbers", () => {
    expect(
      parseSourceCandidateTitle(
        "[DBD-Raws&四魂字幕组][未来日记/Mirai Nikki][01-26全集+OVA+特典][1080P][BDRip][HEVC-10bit][简繁外挂字幕][FLAC][MKV]"
      )
    ).toEqual({
      releaseGroup: "DBD-Raws&四魂字幕组",
      episodeRange: { start: 1, end: 26 },
      resolution: "1080P",
      subtitleLanguages: ["chs", "cht"],
      subtitleKind: "外挂"
    });
  });

  it("marks raw releases as having no subtitles and leaves missing fields unknown", () => {
    expect(
      parseSourceCandidateTitle(
        "[Lilith-Raws] Example Anime S01E17 [Baha][WEB-DL][1920x1080][AVC AAC][MP4]"
      )
    ).toEqual({
      releaseGroup: "Lilith-Raws",
      episodeRange: { start: 17, end: 17 },
      resolution: "1080P",
      subtitleLanguages: ["none"],
      subtitleKind: null
    });

    expect(parseSourceCandidateTitle("Example Anime download")).toEqual({
      releaseGroup: null,
      episodeRange: null,
      resolution: null,
      subtitleLanguages: ["unknown"],
      subtitleKind: null
    });
  });
});

describe("resolveCandidateEpisodeId", () => {
  const episodes = [
    { episodeId: 501, sort: 1 },
    { episodeId: 502, sort: 2 }
  ];

  it("uses explicit episode context and otherwise resolves a single-episode release", () => {
    expect(
      resolveCandidateEpisodeId(
        parseSourceCandidateTitle("[Lilith-Raws] Example Anime - 02 [1080p]"),
        episodes,
        501
      )
    ).toBe(501);
    expect(
      resolveCandidateEpisodeId(
        parseSourceCandidateTitle("[Lilith-Raws] Example Anime - 02 [1080p]"),
        episodes,
        null
      )
    ).toBe(502);
  });

  it("does not guess when a release spans multiple episodes or has no exact episode", () => {
    expect(
      resolveCandidateEpisodeId(
        parseSourceCandidateTitle("Example Anime [01-02]"),
        episodes,
        null
      )
    ).toBeNull();
    expect(
      resolveCandidateEpisodeId(
        parseSourceCandidateTitle("Example Anime - 03"),
        episodes,
        null
      )
    ).toBeNull();
  });
});

describe("source candidate filters", () => {
  const known: FilterableSourceCandidate<string> = {
    value: "known",
    providerId: "mikan",
    providerName: "蜜柑计划",
    metadata: parseSourceCandidateTitle(
      "[百冬练习组&LoliHouse] 元祖！邦多利酱 - 40 [WebRip 1080p HEVC-10bit AAC][简繁内封字幕]"
    )
  };
  const unknown: FilterableSourceCandidate<string> = {
    value: "unknown",
    providerId: "dmhy",
    providerName: "动漫花园",
    metadata: parseSourceCandidateTitle("元祖！BanG Dream Chan resource")
  };
  const filters: SourceCandidateFilters = {
    providerId: null,
    episode: 40,
    releaseGroup: "百冬练习组&LoliHouse",
    subtitleLanguage: "chs",
    resolution: "1080P"
  };

  it("updates matches across provider and parsed attributes while optionally retaining unknown metadata", () => {
    expect(matchesSourceCandidateFilters(known, filters, false)).toBe(true);
    expect(matchesSourceCandidateFilters(unknown, filters, false)).toBe(false);
    expect(matchesSourceCandidateFilters(unknown, filters, true)).toBe(true);
    expect(matchesSourceCandidateFilters(known, { ...filters, providerId: "dmhy" }, true)).toBe(
      false
    );
  });

  it("derives stable filter choices from the current result set", () => {
    expect(buildSourceFilterOptions([known, unknown])).toEqual({
      providers: [
        { value: "dmhy", label: "动漫花园" },
        { value: "mikan", label: "蜜柑计划" }
      ],
      episodes: [40],
      releaseGroups: ["百冬练习组&LoliHouse"],
      subtitleLanguages: ["chs", "cht"],
      resolutions: ["1080P"]
    });
  });
});
