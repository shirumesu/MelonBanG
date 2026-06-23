import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import type { SubjectSearchResult } from "@shared/contracts/bangumi";
import { useAppState } from "@/app/AppStateProvider";
import { PageHeader, PageSection } from "@/components/melon/page";
import { ArtworkCard } from "@/components/melon/artwork";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

const SEARCH_DEBOUNCE_MS = 300;
const MIN_SEARCH_LENGTH = 2;

export function SearchRoute() {
  const { searchSubjects, updateTracking } = useAppState();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SubjectSearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requestId = useRef(0);

  useEffect(() => {
    const trimmedQuery = query.trim();
    if (!trimmedQuery || trimmedQuery.length < MIN_SEARCH_LENGTH) {
      return;
    }

    const currentRequestId = requestId.current + 1;
    requestId.current = currentRequestId;

    const timer = window.setTimeout(() => {
      setLoading(true);
      setError(null);
      void searchSubjects(trimmedQuery)
        .then((nextResults) => {
          if (requestId.current === currentRequestId) {
            setResults(nextResults);
          }
        })
        .catch((searchError: unknown) => {
          if (requestId.current === currentRequestId) {
            setResults([]);
            setError(searchError instanceof Error ? searchError.message : "搜索失败，请稍后重试。");
          }
        })
        .finally(() => {
          if (requestId.current === currentRequestId) {
            setLoading(false);
          }
        });
    }, SEARCH_DEBOUNCE_MS);

    return () => window.clearTimeout(timer);
  }, [query, searchSubjects]);

  function runSearch(value: string): void {
    setQuery(value);
    requestId.current += 1;
    const trimmedValue = value.trim();
    if (!trimmedValue) {
      setResults([]);
      setError(null);
      setLoading(false);
      return;
    }
    if (trimmedValue.length < MIN_SEARCH_LENGTH) {
      setResults([]);
      setError(`至少输入 ${MIN_SEARCH_LENGTH} 个字符开始搜索。`);
      setLoading(false);
      return;
    }

    setError(null);
    setLoading(false);
  }

  return (
    <div className="pb-8">
      <PageHeader
        title="搜索"
        subtitle="搜索 Bangumi 条目并快速加入追番"
        searchValue={query}
        onSearchChange={runSearch}
        searchPlaceholder="搜索番剧、角色、制作公司…"
      />

      <PageSection className="mt-2">
        <div className="grid gap-4">
          {results.map((result) => (
            <Card key={result.subjectId}>
              <CardContent className="flex items-center gap-4 p-4">
                <div className="w-[92px] flex-none">
                  <ArtworkCard
                    id={result.subjectId}
                    title={result.nameCn ?? result.name}
                    imageUrl={result.coverUrl}
                    className="aspect-[3/4]"
                  />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="text-lg font-black">{result.nameCn ?? result.name}</div>
                  <div className="text-muted-foreground mt-1 text-sm font-semibold">
                    {result.name}
                  </div>
                  <p className="text-muted-foreground mt-3 line-clamp-2 text-sm leading-7">
                    {result.summary}
                  </p>
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Badge variant="outline">全 {result.episodeTotal ?? "?"} 话</Badge>
                    <Badge variant="gold">Bangumi 条目</Badge>
                  </div>
                </div>
                <div className="flex flex-col gap-2">
                  <Button
                    onClick={() =>
                      void updateTracking({
                        kind: "subjectCollection",
                        subjectId: result.subjectId,
                        status: "watching"
                      })
                    }
                  >
                    设为在看
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() =>
                      void updateTracking({
                        kind: "subjectCollection",
                        subjectId: result.subjectId,
                        status: "wish"
                      })
                    }
                  >
                    加入想看
                  </Button>
                  <Button asChild variant="ghost">
                    <Link to={`/subject/${result.subjectId}`}>查看详情</Link>
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
          {!loading && results.length === 0 ? (
            <Card>
              <CardContent className="text-muted-foreground p-10 text-center text-sm font-semibold">
                {error ?? "输入关键词开始搜索 Bangumi 条目。"}
              </CardContent>
            </Card>
          ) : null}
          {loading ? (
            <Card>
              <CardContent className="text-muted-foreground p-10 text-center text-sm font-semibold">
                搜索中…
              </CardContent>
            </Card>
          ) : null}
        </div>
      </PageSection>
    </div>
  );
}
