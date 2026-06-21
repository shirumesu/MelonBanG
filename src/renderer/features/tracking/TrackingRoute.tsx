import { useEffect, useMemo, useState } from "react";
import type { CollectionListItem, CollectionStatus } from "@shared/contracts/bangumi";
import { useAppState } from "@/app/AppStateProvider";
import { PageHeader, PageSection } from "@/components/melon/page";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent } from "@/components/ui/tabs";
import { TrackingStatusTabs } from "./components/TrackingStatusTabs";
import { CollectionSection } from "./components/CollectionSection";

const statusOrder: CollectionStatus[] = ["watching", "wish", "on_hold", "completed", "dropped"];

export function TrackingRoute() {
  const { listCollection } = useAppState();
  const [status, setStatus] = useState<CollectionStatus>("watching");
  const [search, setSearch] = useState("");
  const [items, setItems] = useState<CollectionListItem[]>([]);
  const [allItems, setAllItems] = useState<CollectionListItem[]>([]);

  useEffect(() => {
    void listCollection().then((nextItems) => {
      setAllItems(nextItems);
    });
  }, [listCollection]);

  useEffect(() => {
    void listCollection({ status, search: search.trim() || undefined }).then((nextItems) => {
      setItems(nextItems);
    });
  }, [listCollection, search, status]);

  const counts = useMemo(
    () =>
      Object.fromEntries(
        statusOrder.map((entry) => [
          entry,
          allItems.filter((item) => item.collection.status === entry).length
        ])
      ) as Record<CollectionStatus, number>,
    [allItems]
  );

  return (
    <div className="pb-8">
      <PageHeader
        title="追番"
        subtitle={`我的 Bangumi 收藏 · 共 ${allItems.length} 部`}
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="在追番列表中搜索…"
      />

      <PageSection className="mt-2">
        <Tabs value={status} onValueChange={(value) => setStatus(value as CollectionStatus)}>
          <TrackingStatusTabs counts={counts} value={status} />
          {statusOrder.map((entry) => (
            <TabsContent key={entry} value={entry} className="mt-6">
              <div className="mb-4 flex flex-wrap items-center gap-2">
                <span className="text-muted-foreground mr-1 text-xs font-bold">筛选</span>
                <Badge variant="mint">全部</Badge>
                <Badge variant="outline">2026 夏</Badge>
                <Badge variant="outline">2026 春</Badge>
                <Badge variant="outline">2025 秋</Badge>
                <Badge variant="outline">TV</Badge>
                <Badge variant="outline">剧场版</Badge>
                <div className="text-muted-foreground ml-auto text-xs font-bold">
                  {counts[entry]} 部
                </div>
              </div>
              <CollectionSection items={items} />
            </TabsContent>
          ))}
        </Tabs>
      </PageSection>
    </div>
  );
}
