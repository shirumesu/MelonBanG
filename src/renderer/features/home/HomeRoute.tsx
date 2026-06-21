import { useState } from "react";
import { Bell, ChevronRight, PlayCircle, Sparkles } from "lucide-react";
import { Link } from "react-router-dom";
import { TODAY_ITEMS, TODAY_SUBTITLE } from "@/data/home";
import { HeroCarousel } from "./components/HeroCarousel";
import { ContinueRail } from "./components/ContinueRail";
import { Timeline } from "@/components/melon/Timeline";
import {
  IconButton,
  PageContent,
  SearchBox,
  Section,
  SectionHead,
  SyncPill,
  Topbar
} from "@/components/melon/layout";

export function HomeRoute() {
  const [search, setSearch] = useState("");

  return (
    <>
      <Topbar title="探索" subtitle="2026 夏季新番放送中 · 共 312 部">
        <SearchBox
          className="min-w-[280px]"
          placeholder="搜索番剧、角色、制作公司…"
          value={search}
          onChange={setSearch}
        />
        <SyncPill label="已同步 · 2 分钟前" />
        <IconButton badge={5}>
          <Bell />
        </IconButton>
      </Topbar>

      <PageContent>
        <HeroCarousel />

        <Section>
          <SectionHead
            title={
              <>
                <PlayCircle className="text-mint-500 size-[19px]" />
                继续播放
              </>
            }
            sub="接着上次看"
          />
          <ContinueRail />
        </Section>

        <Section>
          <SectionHead
            title={
              <>
                <Sparkles className="text-cherry-500 size-[19px]" />
                今日更新
              </>
            }
            sub={TODAY_SUBTITLE}
            action={
              <Link
                to="/schedule"
                className="text-ink-faint hover:text-mint-500 inline-flex items-center gap-1 text-[12.5px] font-bold"
              >
                新番时间表 <ChevronRight className="size-4" />
              </Link>
            }
          />
          <Timeline items={TODAY_ITEMS} />
        </Section>
      </PageContent>
    </>
  );
}
