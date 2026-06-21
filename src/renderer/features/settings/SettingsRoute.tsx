import { Palette, Tv, UserRound, WandSparkles, Info } from "lucide-react";
import { useMemo, useState } from "react";
import type { ComponentType, ReactNode } from "react";
import { useAppState } from "@/app/AppStateProvider";
import { useTheme } from "@/app/ThemeProvider";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { Switch } from "@/components/ui/switch";

type SettingsTab = "account" | "appearance" | "playback" | "danmaku" | "cache" | "about";

const tabs: Array<{
  key: SettingsTab;
  label: string;
  icon: ComponentType<{ className?: string }>;
}> = [
  { key: "account", label: "账户与同步", icon: UserRound },
  { key: "appearance", label: "外观与主题", icon: Palette },
  { key: "playback", label: "播放", icon: Tv },
  { key: "danmaku", label: "弹幕", icon: WandSparkles },
  { key: "cache", label: "下载与缓存", icon: Tv },
  { key: "about", label: "关于", icon: Info }
];

export function SettingsRoute() {
  const { session, syncState, signOut, refreshCollection } = useAppState();
  const { accent, mode, resolvedTheme, setAccent, setMode } = useTheme();
  const [active, setActive] = useState<SettingsTab>("account");

  const accentOptions = useMemo(
    () =>
      [
        { key: "mint", value: "#43c99f" },
        { key: "cherry", value: "#ff6b81" },
        { key: "sky", value: "#6aa6f0" },
        { key: "grape", value: "#9c87e8" },
        { key: "gold", value: "#ffb83d" }
      ] as const,
    []
  );

  return (
    <div className="border-border bg-card grid min-h-[calc(100vh-120px)] grid-cols-[248px_1fr] overflow-hidden rounded-[24px] border shadow-[var(--shadow-sm)]">
      <aside className="border-border flex flex-col gap-1 border-r bg-white/60 p-4 backdrop-blur-sm dark:bg-white/4">
        <div className="text-muted-foreground mb-2 px-2 text-[10px] font-bold tracking-[0.2em] uppercase">
          设置
        </div>
        {tabs.map(({ key, label, icon: Icon }) => (
          <button
            key={key}
            type="button"
            onClick={() => setActive(key)}
            className={
              active === key
                ? "text-primary-foreground flex items-center gap-3 rounded-xl bg-linear-to-br from-[var(--mint-400)] to-[var(--mint-300)] px-3 py-2.5 text-sm font-extrabold shadow-[0_6px_14px_rgba(34,179,136,.25)]"
                : "text-muted-foreground hover:bg-secondary hover:text-foreground flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-bold transition"
            }
          >
            <Icon className="size-4.5" />
            <span>{label}</span>
          </button>
        ))}
      </aside>

      <main className="overflow-auto p-8">
        {active === "account" ? (
          <div className="grid gap-6">
            <SectionHeading
              title="账户与同步"
              description="管理 Bangumi 账户连接、同步状态和 Goal 1 诊断信息。"
            />
            <Card>
              <CardContent className="flex items-center gap-4 p-6">
                <Avatar className="size-14">
                  <AvatarImage src={session?.avatarUrl} alt={session?.nickname} />
                  <AvatarFallback>{session?.nickname?.slice(0, 1) ?? "M"}</AvatarFallback>
                </Avatar>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <div className="text-lg font-black">{session?.nickname}</div>
                    <Badge variant="mint">已连接</Badge>
                  </div>
                  <div className="text-muted-foreground mt-1 text-sm font-semibold">
                    @{session?.username} · Bangumi ID {session?.userId}
                  </div>
                </div>
                <Button variant="outline">主页</Button>
                <Button variant="ghost" onClick={() => void signOut()}>
                  断开连接
                </Button>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>同步</CardTitle>
                <CardDescription>
                  自动同步、缓存状态和播放完成后的追番更新都由 main process 负责。
                </CardDescription>
              </CardHeader>
              <CardContent className="grid gap-5">
                <SettingRow title="自动同步" description="在追番状态变化时自动推送到 Bangumi">
                  <Switch checked />
                </SettingRow>
                <SettingRow title="同步频率" description="后台刷新收藏与放送数据的间隔">
                  <Badge variant="outline">实时</Badge>
                </SettingRow>
                <SettingRow
                  title="播放完成自动标记看过"
                  description="达到阈值后自动更新章节状态，属于后续 Goal 与播放联动的入口"
                >
                  <Switch checked />
                </SettingRow>
                <Separator />
                <SettingRow
                  title="上次同步"
                  description={`${syncState?.lastSuccessfulSyncAt ?? "暂无"} · ${syncState?.pendingMutationCount ?? 0} 项待同步`}
                >
                  <Button size="sm" onClick={() => void refreshCollection(true)}>
                    立即同步
                  </Button>
                </SettingRow>
              </CardContent>
            </Card>
          </div>
        ) : null}

        {active === "appearance" ? (
          <div className="grid gap-6">
            <SectionHeading
              title="外观与主题"
              description="整体视觉保持 DESIGN/ 的 melon soda 语言，只把结构改成 Electron 可维护组件。"
            />
            <Card>
              <CardHeader>
                <CardTitle>主题模式</CardTitle>
              </CardHeader>
              <CardContent className="grid grid-cols-3 gap-4">
                {[
                  { key: "light", label: "浅色" },
                  { key: "dark", label: "深色" },
                  { key: "system", label: "跟随系统" }
                ].map((option) => (
                  <button
                    key={option.key}
                    type="button"
                    onClick={() => setMode(option.key as "light" | "dark" | "system")}
                    className={
                      mode === option.key
                        ? "rounded-[14px] border border-[var(--mint-400)] p-4 text-left shadow-[0_0_0_3px_rgba(67,201,159,.2)]"
                        : "rounded-[14px] border border-[var(--line-strong)] p-4 text-left"
                    }
                  >
                    <div
                      className={`mb-3 h-14 rounded-[10px] ${option.key === "light" ? "bg-linear-to-br from-[#eafaf3] to-white" : option.key === "dark" ? "bg-linear-to-br from-[#16202d] to-[#0f1722]" : "bg-linear-to-r from-white to-[#16202d]"}`}
                    />
                    <div className="text-sm font-black">{option.label}</div>
                  </button>
                ))}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>主题色</CardTitle>
                <CardDescription>当前解析主题：{resolvedTheme}</CardDescription>
              </CardHeader>
              <CardContent className="flex flex-wrap gap-4">
                {accentOptions.map((option) => (
                  <button
                    key={option.key}
                    type="button"
                    onClick={() => setAccent(option.key)}
                    className={
                      accent === option.key
                        ? "after:border-foreground relative size-9 rounded-full shadow-[var(--shadow-sm)] after:absolute after:inset-[-5px] after:rounded-full after:border-2"
                        : "size-9 rounded-full shadow-[var(--shadow-sm)]"
                    }
                    style={{ background: option.value }}
                  />
                ))}
              </CardContent>
            </Card>
          </div>
        ) : null}

        {active === "playback" || active === "danmaku" || active === "cache" ? (
          <div className="grid gap-6">
            <SectionHeading
              title={tabs.find((tab) => tab.key === active)?.label ?? ""}
              description="这个分组在 Goal 1 只保留界面位置和设计连续性，不引入播放器、下载器或弹幕运行时。"
            />
            <Card>
              <CardContent className="text-muted-foreground p-8 text-sm leading-7 font-semibold">
                Goal 1 只完成 Bangumi UI、追番缓存和章节进度。这里暂时作为后续 Goal
                的设置容器，避免现在就把播放、缓存和弹幕逻辑拉进来。
              </CardContent>
            </Card>
          </div>
        ) : null}

        {active === "about" ? (
          <div className="grid gap-6">
            <SectionHeading title="关于" description="当前版本是 Goal 1 · 追番基础版。" />
            <Card>
              <CardContent className="flex items-start gap-5 p-6">
                <div className="grid size-16 place-items-center rounded-[16px] bg-linear-to-br from-[var(--mint-400)] to-[var(--mint-300)] text-3xl shadow-[var(--shadow-md)]">
                  🍈
                </div>
                <div className="flex-1">
                  <div className="text-xl font-black">melonbang</div>
                  <div className="text-muted-foreground mt-1 text-sm font-semibold">
                    v0.1.0 · Goal 1 · 追番基础版
                  </div>
                  <div className="mt-4 flex flex-wrap gap-3">
                    <Button size="sm" disabled>
                      检查更新
                    </Button>
                    <Button size="sm" variant="outline" asChild>
                      <a href="https://github.com/83977/melonbang" target="_blank" rel="noreferrer">
                        GitHub
                      </a>
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>
        ) : null}
      </main>
    </div>
  );
}

function SectionHeading({ title, description }: { title: string; description: string }) {
  return (
    <div>
      <h2 className="text-[22px] font-black">{title}</h2>
      <p className="text-muted-foreground mt-1 text-sm font-semibold">{description}</p>
    </div>
  );
}

function SettingRow({
  title,
  description,
  children
}: {
  title: string;
  description?: string;
  children: ReactNode;
}) {
  return (
    <div className="flex items-center gap-4">
      <div className="flex-1">
        <div className="text-sm font-black">{title}</div>
        {description ? (
          <div className="text-muted-foreground mt-1 text-xs font-semibold">{description}</div>
        ) : null}
      </div>
      {children}
    </div>
  );
}
