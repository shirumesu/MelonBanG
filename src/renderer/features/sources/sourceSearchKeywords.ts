import type { SubjectDetail } from "@shared/contracts/bangumi";

const maxSearchKeywords = 5;
const aliasKeyPattern = /别名|别称|英文名|日文名/i;
const aliasSeparatorPattern = /[/／\n;；|｜]+/;
const latinPhrasePattern = /[A-Za-z][A-Za-z0-9]*(?:[ .'’_-]+[A-Za-z0-9]+)+/g;

type SearchableSubject = Pick<SubjectDetail, "name" | "nameCn" | "infoBox">;

export function buildSubjectSourceKeywords(
  subject: SearchableSubject,
  episodeSort: number | null | undefined,
  manualKeyword: string
): string[] {
  const keywords: string[] = [];
  const seen = new Set<string>();
  const episodeToken = formatEpisodeToken(episodeSort);
  const add = (value: string): void => {
    if (keywords.length >= maxSearchKeywords) return;
    const keyword = value.trim().replace(/\s+/g, " ");
    if (!keyword) return;
    const key = keyword.normalize("NFKC").toLowerCase();
    if (seen.has(key)) return;
    seen.add(key);
    keywords.push(keyword);
  };
  const addTitle = (title: string): void => {
    const value = title.trim();
    if (value) add(episodeToken ? `${value} ${episodeToken}` : value);
  };

  add(manualKeyword);
  addTitle(subject.nameCn ?? "");

  const aliases = collectAliases(subject);
  aliases.forEach(addTitle);

  for (const title of [subject.nameCn ?? "", ...aliases]) {
    for (const phrase of title.match(latinPhrasePattern) ?? []) {
      addTitle(phrase);
    }
  }

  addTitle(subject.name);
  return keywords;
}

function collectAliases(subject: SearchableSubject): string[] {
  return (subject.infoBox ?? []).flatMap((item) =>
    aliasKeyPattern.test(item.key)
      ? item.value
          .split(aliasSeparatorPattern)
          .map((value) => value.trim())
          .filter(Boolean)
      : []
  );
}

function formatEpisodeToken(episodeSort: number | null | undefined): string | null {
  if (!Number.isFinite(episodeSort) || !episodeSort || episodeSort <= 0) {
    return null;
  }
  const value = String(episodeSort);
  return Number.isInteger(episodeSort) ? value.padStart(2, "0") : value;
}
