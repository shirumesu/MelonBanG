export type SourceSubtitleLanguage = "chs" | "cht" | "jpn" | "eng" | "none" | "unknown";

export type SourceEpisodeRange = {
  start: number;
  end: number;
};

export type SourceCandidateMetadata = {
  releaseGroup: string | null;
  episodeRange: SourceEpisodeRange | null;
  resolution: string | null;
  subtitleLanguages: SourceSubtitleLanguage[];
  subtitleKind: "内嵌" | "内封" | "外挂" | null;
};

export type SourceCandidateFilters = {
  providerId: string | null;
  episode: number | null;
  releaseGroup: string | null;
  subtitleLanguage: SourceSubtitleLanguage | null;
  resolution: string | null;
};

export type FilterableSourceCandidate<T> = {
  value: T;
  providerId: string;
  providerName: string;
  metadata: SourceCandidateMetadata;
};

export type SourceFilterOptions = {
  providers: Array<{ value: string; label: string }>;
  episodes: number[];
  releaseGroups: string[];
  subtitleLanguages: SourceSubtitleLanguage[];
  resolutions: string[];
};

export const sourceSubtitleLanguageLabels: Record<SourceSubtitleLanguage, string> = {
  chs: "简体中文",
  cht: "繁体中文",
  jpn: "日文",
  eng: "英文",
  none: "无字幕",
  unknown: "字幕未知"
};

export const emptySourceCandidateFilters: SourceCandidateFilters = {
  providerId: null,
  episode: null,
  releaseGroup: null,
  subtitleLanguage: null,
  resolution: null
};

const bracketSegmentPattern = /\[(.*?)\]|【(.*?)】/g;
const releaseGroupMarkerPattern =
  /字幕|sub(?:s|title)?|studio|house|raws?|production|压制|壓制|发布|發佈|搬运|搬運|制作|製作|工作室|组|組|社/i;
const metadataSegmentPattern =
  /^(?:web-?dl|webrip|web-rip|bdrip|tvrip|hdtv|abema|baha|bilibili|crunchyroll|hevc|avc|x26[45]|h26[45]|aac|flac|mkv|mp4|10bit|8bit|简|簡|繁|chs|cht|jpn?|eng?|gb|big5|\d{3,4}p|4k|\d{3,4}\s*[x×]\s*\d{3,4})(?:\b|$)/i;
const subtitleLanguageOrder: SourceSubtitleLanguage[] = ["chs", "cht", "jpn", "eng", "none"];

export function parseSourceCandidateTitle(title: string): SourceCandidateMetadata {
  const bracketSegments = [...title.matchAll(bracketSegmentPattern)].map((match) =>
    (match[1] ?? match[2] ?? "").trim()
  );
  const subtitleLanguages = parseSubtitleLanguages(title);

  return {
    releaseGroup: parseReleaseGroup(bracketSegments[0] ?? ""),
    episodeRange: parseEpisodeRange(title, bracketSegments),
    resolution: parseResolution(title),
    subtitleLanguages:
      subtitleLanguages.length > 0
        ? subtitleLanguages
        : rawReleasePattern.test(title)
          ? ["none"]
          : ["unknown"],
    subtitleKind: parseSubtitleKind(title)
  };
}

export function resolveCandidateEpisodeId(
  metadata: SourceCandidateMetadata,
  episodes: ReadonlyArray<{ episodeId: number; sort: number }>,
  contextualEpisodeId: number | null
): number | null {
  if (contextualEpisodeId !== null) {
    return episodes.some((episode) => episode.episodeId === contextualEpisodeId)
      ? contextualEpisodeId
      : null;
  }

  const range = metadata.episodeRange;
  if (!range || range.start !== range.end) {
    return null;
  }
  return episodes.find((episode) => episode.sort === range.start)?.episodeId ?? null;
}

export function matchesSourceCandidateFilters<T>(
  candidate: FilterableSourceCandidate<T>,
  filters: SourceCandidateFilters,
  includeUnknown: boolean
): boolean {
  if (filters.providerId && candidate.providerId !== filters.providerId) {
    return false;
  }

  const { metadata } = candidate;
  if (
    filters.episode !== null &&
    !matchesOrIncludesUnknown(
      metadata.episodeRange !== null &&
        filters.episode >= metadata.episodeRange.start &&
        filters.episode <= metadata.episodeRange.end,
      metadata.episodeRange === null,
      includeUnknown
    )
  ) {
    return false;
  }
  if (
    filters.releaseGroup &&
    !matchesOrIncludesUnknown(
      metadata.releaseGroup === filters.releaseGroup,
      metadata.releaseGroup === null,
      includeUnknown
    )
  ) {
    return false;
  }
  if (
    filters.subtitleLanguage &&
    !matchesOrIncludesUnknown(
      metadata.subtitleLanguages.includes(filters.subtitleLanguage),
      metadata.subtitleLanguages.includes("unknown"),
      includeUnknown
    )
  ) {
    return false;
  }
  if (
    filters.resolution &&
    !matchesOrIncludesUnknown(
      metadata.resolution === filters.resolution,
      metadata.resolution === null,
      includeUnknown
    )
  ) {
    return false;
  }
  return true;
}

export function buildSourceFilterOptions<T>(
  candidates: Array<FilterableSourceCandidate<T>>
): SourceFilterOptions {
  const providers = new Map<string, string>();
  const episodes = new Set<number>();
  const releaseGroups = new Set<string>();
  const subtitleLanguages = new Set<SourceSubtitleLanguage>();
  const resolutions = new Set<string>();

  for (const candidate of candidates) {
    providers.set(candidate.providerId, candidate.providerName);
    const { metadata } = candidate;
    if (metadata.episodeRange) {
      const span = metadata.episodeRange.end - metadata.episodeRange.start;
      if (span <= 200) {
        for (
          let episode = metadata.episodeRange.start;
          episode <= metadata.episodeRange.end;
          episode += 1
        ) {
          episodes.add(episode);
        }
      }
    }
    if (metadata.releaseGroup) releaseGroups.add(metadata.releaseGroup);
    metadata.subtitleLanguages.forEach((language) => {
      if (language !== "unknown") subtitleLanguages.add(language);
    });
    if (metadata.resolution) resolutions.add(metadata.resolution);
  }

  return {
    providers: [...providers]
      .map(([value, label]) => ({ value, label }))
      .sort((left, right) => left.label.localeCompare(right.label, "zh-CN")),
    episodes: [...episodes].sort((left, right) => left - right),
    releaseGroups: [...releaseGroups].sort((left, right) => left.localeCompare(right, "zh-CN")),
    subtitleLanguages: subtitleLanguageOrder.filter((language) => subtitleLanguages.has(language)),
    resolutions: [...resolutions].sort(
      (left, right) => resolutionSortValue(right) - resolutionSortValue(left)
    )
  };
}

export function countActiveSourceFilters(filters: SourceCandidateFilters): number {
  return Object.values(filters).filter((value) => value !== null).length;
}

export function formatSourceEpisode(range: SourceEpisodeRange): string {
  return range.start === range.end ? `EP${range.start}` : `EP${range.start}–${range.end}`;
}

function parseReleaseGroup(segment: string): string | null {
  const value = segment.trim();
  if (
    !value ||
    value.length > 64 ||
    value.includes("/") ||
    metadataSegmentPattern.test(value) ||
    parseEpisodeSegment(value)
  ) {
    return null;
  }
  return releaseGroupMarkerPattern.test(value) || !/\s/.test(value) ? value : null;
}

function parseEpisodeRange(title: string, bracketSegments: string[]): SourceEpisodeRange | null {
  const seasonEpisode = /\bS\d{1,2}E0*(\d{1,3})(?:\s*[-~]\s*(?:E)?0*(\d{1,3}))?\b/i.exec(title);
  if (seasonEpisode) return toEpisodeRange(seasonEpisode[1], seasonEpisode[2]);

  const labelledEpisode =
    /(?:^|[^\p{L}\p{N}])(?:EP|E|第)\s*#?0*(\d{1,3})(?:\s*[-~—]\s*0*(\d{1,3}))?\s*(?:话|話|集)?(?:$|[^\p{L}\p{N}])/iu.exec(
      title
    );
  if (labelledEpisode) return toEpisodeRange(labelledEpisode[1], labelledEpisode[2]);

  const dashedEpisode =
    /(?:^|\s)[-–—]\s*0*(\d{1,3})(?:v\d+)?(?:\s*[-~]\s*0*(\d{1,3}))?(?=\s|[([【]|$)/i.exec(title);
  if (dashedEpisode) return toEpisodeRange(dashedEpisode[1], dashedEpisode[2]);

  for (const segment of bracketSegments) {
    const range = parseEpisodeSegment(segment);
    if (range) return range;
  }
  return null;
}

function parseEpisodeSegment(segment: string): SourceEpisodeRange | null {
  const match =
    /^0*(\d{1,3})(?:\s*[-~—]\s*0*(\d{1,3}))?(?:v\d+)?(?:\s*(?:END|完|全集))?(?:\+.*)?$/i.exec(
      segment.trim()
    );
  return match ? toEpisodeRange(match[1], match[2]) : null;
}

function toEpisodeRange(
  startValue: string | undefined,
  endValue: string | undefined
): SourceEpisodeRange | null {
  const start = Number(startValue);
  const end = Number(endValue ?? startValue);
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start <= 0 || end < start) {
    return null;
  }
  return { start, end };
}

function parseResolution(title: string): string | null {
  if (/(?:3840\s*[x×]\s*2160|2160p|\b4k\b|\buhd\b)/i.test(title)) return "4K";
  if (/(?:2560\s*[x×]\s*1440|1440p)/i.test(title)) return "1440P";
  if (/(?:1920\s*[x×]\s*1080|1080p|\bfhd\b)/i.test(title)) return "1080P";
  if (/(?:1280\s*[x×]\s*720|720p)/i.test(title)) return "720P";
  if (/(?:1024\s*[x×]\s*576|576p)/i.test(title)) return "576P";
  if (/(?:848\s*[x×]\s*480|720\s*[x×]\s*480|480p)/i.test(title)) return "480P";
  return null;
}

function parseSubtitleLanguages(title: string): SourceSubtitleLanguage[] {
  const languages: SourceSubtitleLanguage[] = [];
  if (
    hasLanguageToken(title, ["CHS", "GB", "SC"]) ||
    /简(?:体|中|繁|日|英|字|内|外|双)/.test(title)
  ) {
    languages.push("chs");
  }
  if (
    hasLanguageToken(title, ["CHT", "BIG5", "TC"]) ||
    /繁(?:体|中|简|日|英|字|内|外|双)/.test(title)
  ) {
    languages.push("cht");
  }
  if (hasLanguageToken(title, ["JPN", "JP"]) || /日(?:语|文|字|简|繁|英|内|外|双)/.test(title)) {
    languages.push("jpn");
  }
  if (hasLanguageToken(title, ["ENG", "EN"]) || /英(?:语|文|字|简|繁|日|内|外|双)/.test(title)) {
    languages.push("eng");
  }
  return languages;
}

function hasLanguageToken(title: string, tokens: string[]): boolean {
  const upper = title.toUpperCase();
  return tokens.some((token) => new RegExp(`(?:^|[^A-Z0-9])${token}(?=$|[^A-Z0-9])`).test(upper));
}

function parseSubtitleKind(title: string): SourceCandidateMetadata["subtitleKind"] {
  if (/内嵌|硬字幕|hard\s*sub/i.test(title)) return "内嵌";
  if (/内封|内掛|内挂|软字幕|軟字幕|soft\s*sub/i.test(title)) return "内封";
  if (/外挂|外掛|外置|external\s*sub/i.test(title)) return "外挂";
  return null;
}

const rawReleasePattern = /(?:^|(?:\[|【|[\s&_/-]))RAWS?(?=$|(?:\]|】|[\s&_/-]))/i;

function matchesOrIncludesUnknown(
  matches: boolean,
  isUnknown: boolean,
  includeUnknown: boolean
): boolean {
  return matches || (includeUnknown && isUnknown);
}

function resolutionSortValue(value: string): number {
  if (value === "4K") return 2160;
  return Number.parseInt(value, 10) || 0;
}
