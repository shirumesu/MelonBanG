import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  ChevronLeft,
  Download,
  ExternalLink,
  HardDriveDownload,
  LoaderCircle,
  Search,
  ShieldCheck,
  TriangleAlert
} from "lucide-react";
import type { SubjectDetail } from "@shared/contracts/bangumi";
import type { SourceCandidateView, SourceSearchResult } from "@shared/contracts/source";
import { useAppState } from "@/app/AppStateProvider";
import { IconButton, PageContent, Topbar } from "@/components/melon/layout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { SourceResultFilterBar } from "./SourceResultFilterBar";
import {
  buildSourceFilterOptions,
  emptySourceCandidateFilters,
  formatSourceEpisode,
  matchesSourceCandidateFilters,
  parseSourceCandidateTitle,
  resolveCandidateEpisodeId,
  sourceSubtitleLanguageLabels,
  type FilterableSourceCandidate,
  type SourceCandidateFilters,
  type SourceCandidateMetadata
} from "./sourceCandidateMetadata";
import { buildSubjectSourceKeywords } from "./sourceSearchKeywords";

const resultPageSize = 60;

export function SubjectCacheRoute() {
  const navigate = useNavigate();
  const { subjectId } = useParams();
  const [searchParams] = useSearchParams();
  const { getCachedSubject, getSubject } = useAppState();
  const parsedSubjectId = Number(subjectId);
  const invalidSubjectId = !Number.isSafeInteger(parsedSubjectId) || parsedSubjectId <= 0;
  const requestedEpisodeId = Number(searchParams.get("episodeId"));
  const [subject, setSubject] = useState<SubjectDetail | null>(null);
  const [keyword, setKeyword] = useState("");
  const [result, setResult] = useState<SourceSearchResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [enqueuingIds, setEnqueuingIds] = useState<Set<string>>(() => new Set());
  const [enqueuedIds, setEnqueuedIds] = useState<Set<string>>(() => new Set());
  const [visibleResultCount, setVisibleResultCount] = useState(resultPageSize);
  const [filters, setFilters] = useState<SourceCandidateFilters>(() => ({
    ...emptySourceCandidateFilters
  }));
  const [includeUnknown, setIncludeUnknown] = useState(false);

  useEffect(() => {
    if (invalidSubjectId) {
      return;
    }

    let active = true;
    void (async () => {
      let hasCachedSubject = false;
      try {
        const cached = await getCachedSubject(parsedSubjectId);
        if (active && cached) {
          hasCachedSubject = true;
          setSubject(cached);
          setKeyword(buildEpisodeSearchKeyword(cached, requestedEpisodeId));
        }
        const fresh = await getSubject(parsedSubjectId);
        if (active) {
          setSubject(fresh);
          setKeyword((current) => current || buildEpisodeSearchKeyword(fresh, requestedEpisodeId));
          setLoadError(null);
        }
      } catch (error) {
        if (active && !hasCachedSubject) {
          setLoadError(toMessage(error, "条目信息加载失败。"));
        }
      }
    })();

    return () => {
      active = false;
    };
  }, [getCachedSubject, getSubject, invalidSubjectId, parsedSubjectId, requestedEpisodeId]);

  const title = subject?.nameCn ?? subject?.name ?? "资源缓存";
  const visibleLoadError = invalidSubjectId ? "条目编号无效。" : loadError;
  const contextualEpisode = subject?.episodes.find(
    (episode) => episode.episodeId === requestedEpisodeId
  );
  const resultCount = result?.candidates.length ?? 0;
  const hasProviderError =
    result?.providers.some((provider) => provider.status === "error") ?? false;
  const sortedCandidates = useMemo(
    () =>
      result
        ? [...result.candidates].sort((left, right) =>
            (right.publishedAt ?? "").localeCompare(left.publishedAt ?? "")
          )
        : [],
    [result]
  );
  const parsedCandidates = useMemo<Array<FilterableSourceCandidate<SourceCandidateView>>>(
    () =>
      sortedCandidates.map((candidate) => ({
        value: candidate,
        providerId: candidate.providerId,
        providerName: candidate.providerName,
        metadata: parseSourceCandidateTitle(candidate.title)
      })),
    [sortedCandidates]
  );
  const filterOptions = useMemo(
    () => buildSourceFilterOptions(parsedCandidates),
    [parsedCandidates]
  );
  const filteredCandidates = useMemo(
    () =>
      parsedCandidates.filter((candidate) =>
        matchesSourceCandidateFilters(candidate, filters, includeUnknown)
      ),
    [filters, includeUnknown, parsedCandidates]
  );
  const filteredResultCount = filteredCandidates.length;

  async function runSearch(): Promise<void> {
    const value = keyword.trim();
    if (!value || !Number.isSafeInteger(parsedSubjectId) || parsedSubjectId <= 0) {
      setSearchError(value ? "条目编号无效。" : "请输入搜索关键词。");
      return;
    }
    setLoading(true);
    setSearchError(null);
    try {
      const searchKeywords = subject
        ? buildSubjectSourceKeywords(subject, contextualEpisode?.sort, value)
        : [value];
      const nextResult = await window.melonbang.source.search({
        subjectId: parsedSubjectId,
        episodeId: contextualEpisode?.episodeId,
        keyword: searchKeywords[0] ?? value,
        keywords: searchKeywords.slice(1)
      });
      setResult(nextResult);
      const requestedEpisode = contextualEpisode?.sort ?? null;
      const hasRequestedEpisode =
        requestedEpisode !== null &&
        nextResult.candidates.some((candidate) => {
          const range = parseSourceCandidateTitle(candidate.title).episodeRange;
          return range && requestedEpisode >= range.start && requestedEpisode <= range.end;
        });
      setFilters({
        ...emptySourceCandidateFilters,
        episode: hasRequestedEpisode ? requestedEpisode : null
      });
      setIncludeUnknown(false);
      setEnqueuedIds(new Set());
      setVisibleResultCount(resultPageSize);
    } catch (error) {
      setSearchError(toMessage(error, "资源搜索失败。"));
    } finally {
      setLoading(false);
    }
  }

  async function enqueue(candidate: SourceCandidateView): Promise<void> {
    setEnqueuingIds((current) => new Set(current).add(candidate.candidateId));
    setSearchError(null);
    try {
      const episodeId = subject
        ? resolveCandidateEpisodeId(
            parseSourceCandidateTitle(candidate.title),
            subject.episodes,
            contextualEpisode?.episodeId ?? null
          )
        : null;
      await window.melonbang.source.enqueue({
        candidateId: candidate.candidateId,
        ...(episodeId === null ? {} : { episodeId })
      });
      setEnqueuedIds((current) => new Set(current).add(candidate.candidateId));
    } catch (error) {
      setSearchError(toMessage(error, "加入缓存失败。"));
    } finally {
      setEnqueuingIds((current) => {
        const next = new Set(current);
        next.delete(candidate.candidateId);
        return next;
      });
    }
  }

  return (
    <>
      <Topbar
        title="资源缓存"
        subtitle={
          subject
            ? `为「${title}」${contextualEpisode ? `EP${contextualEpisode.sort} ` : ""}查找可下载资源`
            : "加载条目信息中…"
        }
        leading={
          <IconButton
            onClick={() => void navigate(`/subject/${parsedSubjectId || ""}`)}
            title="返回条目"
          >
            <ChevronLeft />
          </IconButton>
        }
      >
        <Button variant="outline" asChild>
          <Link to="/cache">
            <HardDriveDownload className="size-4" />
            下载任务
          </Link>
        </Button>
      </Topbar>

      <PageContent narrow>
        <section className="border-line bg-surface relative overflow-hidden rounded-[20px] border p-6 shadow-[var(--shadow-sm)]">
          <div className="from-mint-100/70 pointer-events-none absolute inset-x-0 top-0 h-28 bg-linear-to-b to-transparent" />
          <div className="relative">
            <div className="mb-5 flex items-start gap-3">
              <div className="bg-mint-100 text-mint-600 grid size-11 shrink-0 place-items-center rounded-[14px]">
                <Download className="size-5" />
              </div>
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <h1 className="text-lg font-extrabold">搜索发布资源</h1>
                  {contextualEpisode ? (
                    <Badge variant="mint">EP{contextualEpisode.sort}</Badge>
                  ) : null}
                </div>
                <p className="text-ink-faint mt-1 text-[12.5px] leading-relaxed font-semibold">
                  仅在你点击搜索时访问蜜柑计划与动漫花园 RSS，不会后台抓取或自动下载。
                </p>
              </div>
            </div>

            <form
              className="flex gap-2.5 max-sm:flex-col"
              onSubmit={(event) => {
                event.preventDefault();
                void runSearch();
              }}
            >
              <Input
                value={keyword}
                onChange={(event) => setKeyword(event.target.value)}
                placeholder="番剧名称，也可以加集数或字幕组"
                disabled={Boolean(visibleLoadError) || !subject}
              />
              <Button
                type="submit"
                disabled={loading || Boolean(visibleLoadError) || !subject}
                className="min-w-28"
              >
                {loading ? (
                  <LoaderCircle className="size-4 animate-spin" />
                ) : (
                  <Search className="size-4" />
                )}
                {loading ? "搜索中" : "搜索"}
              </Button>
            </form>

            {visibleLoadError || searchError ? (
              <div className="border-cherry-200 bg-cherry-50 text-cherry-600 mt-4 flex items-start gap-2 rounded-[14px] border px-4 py-3 text-sm font-semibold">
                <TriangleAlert className="mt-0.5 size-4 shrink-0" />
                {visibleLoadError ?? searchError}
              </div>
            ) : null}
          </div>
        </section>

        {result ? (
          <SourceResultFilterBar
            filters={filters}
            options={filterOptions}
            includeUnknown={includeUnknown}
            filteredCount={filteredResultCount}
            totalCount={resultCount}
            onFiltersChange={(nextFilters) => {
              setFilters(nextFilters);
              setVisibleResultCount(resultPageSize);
            }}
            onIncludeUnknownChange={(nextIncludeUnknown) => {
              setIncludeUnknown(nextIncludeUnknown);
              setVisibleResultCount(resultPageSize);
            }}
          />
        ) : null}

        {result ? (
          <section className="mt-4">
            <div className="mb-3 flex flex-wrap items-center gap-2">
              <h2 className="text-[17px] font-extrabold">搜索结果</h2>
              <Badge variant="mint">{filteredResultCount} 个资源</Badge>
              {result.providers.map((provider) => (
                <Badge
                  key={provider.providerId}
                  variant={provider.status === "ok" ? "outline" : "cherry"}
                  title={provider.message}
                >
                  {provider.providerName} ·{" "}
                  {provider.status === "ok" ? provider.resultCount : "异常"}
                </Badge>
              ))}
            </div>

            {hasProviderError ? (
              <div className="border-gold-200 bg-gold-50 text-ink-soft mb-3 rounded-[14px] border px-4 py-3 text-[12.5px] font-semibold">
                部分来源暂时不可用，已保留其它来源的可用结果。
              </div>
            ) : null}

            {filteredCandidates.length > 0 ? (
              <div className="grid gap-2.5">
                {filteredCandidates
                  .slice(0, visibleResultCount)
                  .map(({ value: candidate, metadata }) => {
                    const enqueuing = enqueuingIds.has(candidate.candidateId);
                    const enqueued = enqueuedIds.has(candidate.candidateId);
                    return (
                      <article
                        key={candidate.candidateId}
                        className="border-line bg-surface hover:border-mint-200 flex items-center gap-4 rounded-[16px] border px-4 py-3.5 shadow-[var(--shadow-xs)] transition max-sm:items-start"
                      >
                        <div className="min-w-0 flex-1">
                          <div className="mb-1.5 flex flex-wrap items-center gap-1.5">
                            <Badge variant={candidate.providerId === "mikan" ? "mint" : "sky"}>
                              {candidate.providerName}
                            </Badge>
                            {metadata.releaseGroup ? (
                              <Badge
                                variant="grape"
                                className="max-w-48 truncate"
                                title={metadata.releaseGroup}
                              >
                                {metadata.releaseGroup}
                              </Badge>
                            ) : null}
                            {metadata.episodeRange ? (
                              <Badge variant="gold">
                                {formatSourceEpisode(metadata.episodeRange)}
                              </Badge>
                            ) : null}
                            {metadata.resolution ? (
                              <Badge variant="outline">{metadata.resolution}</Badge>
                            ) : null}
                            <Badge
                              variant={
                                metadata.subtitleLanguages.includes("unknown") ? "outline" : "sky"
                              }
                            >
                              {formatSourceSubtitle(metadata)}
                            </Badge>
                            <span className="text-ink-faint text-[11.5px] font-semibold">
                              {formatDate(candidate.publishedAt)}
                              {candidate.sizeBytes ? ` · ${formatBytes(candidate.sizeBytes)}` : ""}
                            </span>
                          </div>
                          <a
                            href={candidate.detailUrl}
                            target="_blank"
                            rel="noreferrer"
                            className="text-ink hover:text-mint-600 line-clamp-2 text-sm leading-relaxed font-bold transition"
                          >
                            {candidate.title}
                            <ExternalLink className="ml-1 inline size-3.5" />
                          </a>
                        </div>
                        <Button
                          size="sm"
                          variant={enqueued ? "soft" : "default"}
                          disabled={enqueuing || enqueued}
                          onClick={() => void enqueue(candidate)}
                        >
                          {enqueuing ? (
                            <LoaderCircle className="size-4 animate-spin" />
                          ) : enqueued ? (
                            <ShieldCheck className="size-4" />
                          ) : (
                            <Download className="size-4" />
                          )}
                          {enqueuing ? "加入中" : enqueued ? "已加入" : "缓存"}
                        </Button>
                      </article>
                    );
                  })}
                {visibleResultCount < filteredCandidates.length ? (
                  <Button
                    variant="outline"
                    className="mx-auto mt-1"
                    onClick={() => setVisibleResultCount((count) => count + resultPageSize)}
                  >
                    再显示{" "}
                    {Math.min(resultPageSize, filteredCandidates.length - visibleResultCount)} 条
                  </Button>
                ) : null}
              </div>
            ) : (
              <div className="border-line bg-surface text-ink-faint rounded-[16px] border px-5 py-10 text-center text-sm font-semibold">
                {resultCount > 0
                  ? "没有符合当前筛选的资源，可以调整条件或勾选「包含未知」。"
                  : "没有找到匹配资源，可以尝试日文原名、集数或字幕组关键词。"}
              </div>
            )}
          </section>
        ) : null}

        <div className="text-ink-faint mt-5 flex items-start gap-2 rounded-[14px] px-1 text-[12px] leading-relaxed font-semibold">
          <ShieldCheck className="text-mint-500 mt-0.5 size-4 shrink-0" />
          搜索结果仅是第三方索引，不代表内容已获授权；请只下载你有权使用的内容。
        </div>
      </PageContent>
    </>
  );
}

function buildEpisodeSearchKeyword(subject: SubjectDetail, requestedEpisodeId: number): string {
  const title = subject.nameCn ?? subject.name;
  const episode = subject.episodes.find((candidate) => candidate.episodeId === requestedEpisodeId);
  if (!episode) {
    return title;
  }
  return `${title} ${String(episode.sort).padStart(2, "0")}`;
}

function formatSourceSubtitle(metadata: SourceCandidateMetadata): string {
  const languages = metadata.subtitleLanguages.map(
    (language) => sourceSubtitleLanguageLabels[language]
  );
  return metadata.subtitleKind
    ? `${languages.join(" / ")} · ${metadata.subtitleKind}`
    : languages.join(" / ");
}

function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(2)} GB`;
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${Math.round(bytes / 1024)} KB`;
}

function formatDate(value: string | null): string {
  if (!value) return "发布时间未知";
  return new Intl.DateTimeFormat("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

function toMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}
