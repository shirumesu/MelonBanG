import { ArrowRight } from "lucide-react";
import { Link } from "react-router-dom";
import { useMemo } from "react";
import { useAppState } from "@/app/AppStateProvider";
import { PageHeader, PageSection, SectionTitle } from "@/components/melon/page";
import { HomeHero } from "./components/HomeHero";
import { ContinueRail } from "./components/ContinueRail";
import { TodayTimeline } from "./components/TodayTimeline";

export function HomeRoute() {
  const { homeItems, syncState } = useAppState();
  const updates = useMemo(() => [...homeItems].slice(0, 6), [homeItems]);

  return (
    <div className="pb-8">
      <PageHeader
        title="探索"
        subtitle={`Goal 1 追番基础界面 · ${homeItems.length} 部作品已接入`}
        actions={
          <div className="rounded-full border border-[var(--mint-200)] bg-[var(--mint-50)] px-4 py-2 text-xs font-extrabold text-[var(--mint-600)]">
            {syncState?.lastSuccessfulSyncAt ? "已同步" : "待同步"}
          </div>
        }
      />

      <HomeHero items={homeItems} />

      <PageSection>
        <SectionTitle title="继续播放" subtitle="接着上次看到的地方" />
        <ContinueRail items={homeItems} />
      </PageSection>

      <PageSection>
        <SectionTitle
          title="今日更新"
          subtitle={`周五 · ${updates.length} 部有新集`}
          action={
            <Link
              to="/tracking"
              className="text-muted-foreground inline-flex items-center gap-1 text-xs font-extrabold transition hover:text-[var(--mint-600)]"
            >
              新番时间表
              <ArrowRight className="size-3.5" />
            </Link>
          }
        />
        <TodayTimeline items={updates} />
      </PageSection>
    </div>
  );
}
