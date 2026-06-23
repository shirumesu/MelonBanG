import { useRef, useState } from "react";
import { Link } from "react-router-dom";
import type { SubjectSearchResult } from "@shared/contracts/bangumi";
import { useAppState } from "@/app/AppStateProvider";
import { PageHeader, PageSection } from "@/components/melon/page";
import { ArtworkCard } from "@/components/melon/artwork";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

export function SearchRoute() {
  const { searchSubjects, updateTracking } = useAppState();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SubjectSearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requestId = useRef(0);

  async function runSearch(value: string): Promise<void> {
    setQuery(value);
    const currentRequestId = requestId.current + 1;
    requestId.current = currentRequestId;
    if (!value.trim()) {
      setResults([]);
      setError(null);
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const nextResults = await searchSubjects(value);
      if (requestId.current === currentRequestId) {
        setResults(nextResults);
      }
    } catch (searchError) {
      if (requestId.current === currentRequestId) {
        setResults([]);
        setError(searchError instanceof Error ? searchError.message : "搜索失败，请稍后重试。");
      }
    } finally {
      if (requestId.current === currentRequestId) {
        setLoading(false);
      }
    }
  }

  return (
    <div className="pb-8">
      <PageHeader
        title="搜索"
        subtitle="搜索 Bangumi 条目并快速加入追番"
        searchValue={query}
        onSearchChange={(value) => void runSearch(value)}
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
