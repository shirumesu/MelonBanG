import { useEffect, useMemo, useRef, useState } from "react";
import type { ComponentType, KeyboardEvent, ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import {
  Bell,
  Check,
  ChevronLeft,
  ChevronRight,
  Download,
  ExternalLink,
  FileText,
  FolderOpen,
  Info,
  Keyboard,
  Palette,
  Play,
  Plus,
  RefreshCw,
  ServerCog,
  Trash2,
  UserRound
} from "lucide-react";
import { useAppState } from "@/app/AppStateProvider";
import { useTheme } from "@/app/ThemeProvider";
import { WindowFrame } from "@/app/shell/WindowFrame";
import { GradientAvatar } from "@/components/melon/GradientAvatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogHeader,
  DialogTitle
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";

type SettingsCategory =
  | "account"
  | "appearance"
  | "playback"
  | "sources"
  | "cache"
  | "notify"
  | "keys"
  | "logs"
  | "about";

type CategorySection = {
  key: string;
  label: string;
};

type CategoryConfig = {
  key: SettingsCategory;
  label: string;
  icon: ComponentType<{ className?: string }>;
  sections: CategorySection[];
};

type ChoiceOption<T extends string> = {
  value: T;
  label: string;
  description?: string;
};

type ToastState = {
  title: string;
  description?: string;
};

const categories: CategoryConfig[] = [
  {
    key: "account",
    label: "账户与同步",
    icon: UserRound,
    sections: [
      { key: "connection", label: "账户" },
      { key: "sync", label: "同步" }
    ]
  },
  {
    key: "appearance",
    label: "界面与外观",
    icon: Palette,
    sections: [
      { key: "theme", label: "主题模式" },
      { key: "accent", label: "主题色" },
      { key: "interface", label: "界面" },
      { key: "startup", label: "启动与窗口" }
    ]
  },
  {
    key: "playback",
    label: "播放",
    icon: Play,
    sections: [
      { key: "player", label: "播放" },
      { key: "danmaku", label: "弹幕显示" },
      { key: "filter", label: "弹幕过滤" },
      { key: "automation", label: "播放自动化" }
    ]
  },
  {
    key: "sources",
    label: "数据源管理",
    icon: ServerCog,
    sections: [{ key: "sources", label: "数据源" }]
  },
  {
    key: "cache",
    label: "下载与缓存",
    icon: Download,
    sections: [
      { key: "cache", label: "缓存" },
      { key: "network", label: "网络" },
      { key: "bt", label: "BitTorrent" }
    ]
  },
  {
    key: "notify",
    label: "通知",
    icon: Bell,
    sections: [{ key: "desktop", label: "桌面通知" }]
  },
  {
    key: "keys",
    label: "快捷键",
    icon: Keyboard,
    sections: [
      { key: "playback", label: "播放控制" },
      { key: "app", label: "应用操作" }
    ]
  },
  {
    key: "logs",
    label: "日志",
    icon: FileText,
    sections: [{ key: "logs", label: "日志" }]
  },
  {
    key: "about",
    label: "关于",
    icon: Info,
    sections: [
      { key: "version", label: "版本" },
      { key: "notes", label: "更新说明" },
      { key: "links", label: "链接" },
      { key: "thanks", label: "鸣谢" }
    ]
  }
];

const choiceOptions = {
  syncFrequency: [
    { value: "realtime", label: "实时", description: "状态变化后立即尝试同步" },
    { value: "tenMinutes", label: "每 10 分钟", description: "适合低频使用" },
    { value: "manual", label: "仅手动", description: "只在点击立即同步时刷新" }
  ],
  language: [
    { value: "zhCN", label: "简体中文" },
    { value: "zhTW", label: "繁体中文" },
    { value: "jaJP", label: "日本語" },
    { value: "enUS", label: "English" }
  ],
  initialPage: [
    { value: "home", label: "首页" },
    { value: "tracking", label: "追番" },
    { value: "schedule", label: "新番时间表" },
    { value: "search", label: "搜索" },
    { value: "settings", label: "设置" }
  ],
  closeBehavior: [
    { value: "tray", label: "最小化到托盘" },
    { value: "exit", label: "直接退出应用" },
    { value: "ask", label: "每次询问" }
  ],
  quality: [
    { value: "source", label: "原画" },
    { value: "1080p", label: "1080P" },
    { value: "720p", label: "720P" },
    { value: "auto", label: "自动" }
  ],
  speed: [
    { value: "0.75", label: "0.75x" },
    { value: "1", label: "1.0x" },
    { value: "1.25", label: "1.25x" },
    { value: "1.5", label: "1.5x" },
    { value: "2", label: "2.0x" }
  ],
  longPressRate: [
    { value: "1.5", label: "1.5x" },
    { value: "2", label: "2.0x" },
    { value: "3", label: "3.0x" },
    { value: "4", label: "4.0x" }
  ],
  danmakuArea: [
    { value: "quarter", label: "1/4" },
    { value: "half", label: "半屏" },
    { value: "full", label: "全屏" }
  ],
  proxy: [
    { value: "system", label: "跟随系统代理" },
    { value: "none", label: "不使用代理" },
    { value: "http", label: "HTTP 代理" },
    { value: "socks", label: "SOCKS5 代理" }
  ]
} as const;

const directoryOptions = [
  "应用数据目录 / cache",
  "下载目录 / melonbang",
  "外置磁盘 / melonbang-cache"
];

const shortcutLabels = {
  playPause: "播放 / 暂停",
  seek: "快进 / 快退 5 秒",
  nextEpisode: "下一集",
  danmaku: "弹幕开关",
  fullscreen: "全屏",
  search: "全局搜索"
} as const;

type ShortcutKey = keyof typeof shortcutLabels;

const defaultShortcuts: Record<ShortcutKey, string> = {
  playPause: "Space",
  seek: "← / →",
  nextEpisode: "N",
  danmaku: "D",
  fullscreen: "F",
  search: "Ctrl K"
};

function sectionDomId(category: SettingsCategory, section: string): string {
  return `settings-${category}-${section}`;
}

function formatSyncTime(value: string | undefined): string {
  if (!value) {
    return "尚未同步";
  }

  const timestamp = Date.parse(value);
  if (Number.isNaN(timestamp)) {
    return value;
  }

  return new Date(timestamp).toLocaleString("zh-CN", { hour12: false });
}

export function SettingsRoute() {
  const navigate = useNavigate();
  const { session, syncState, signOut, refreshCollection } = useAppState();
  const { accent, mode, resolvedTheme, setAccent, setMode } = useTheme();
  const mainRef = useRef<HTMLElement>(null);
  const [active, setActive] = useState<SettingsCategory>("account");
  const [activeSection, setActiveSection] = useState(categories[0].sections[0].key);
  const [toast, setToast] = useState<ToastState | null>(null);
  const [directoryOpen, setDirectoryOpen] = useState(false);
  const [notesOpen, setNotesOpen] = useState(false);
  const [cacheDirectory, setCacheDirectory] = useState(directoryOptions[0]);
  const [customDirectory, setCustomDirectory] = useState("");
  const [lastSyncLabel, setLastSyncLabel] = useState<string | null>(null);
  const [syncing, setSyncing] = useState(false);
  const [disconnecting, setDisconnecting] = useState(false);

  const [syncFrequency, setSyncFrequency] =
    useState<(typeof choiceOptions.syncFrequency)[number]["value"]>("realtime");
  const [language, setLanguage] =
    useState<(typeof choiceOptions.language)[number]["value"]>("zhCN");
  const [initialPage, setInitialPage] =
    useState<(typeof choiceOptions.initialPage)[number]["value"]>("home");
  const [closeBehavior, setCloseBehavior] =
    useState<(typeof choiceOptions.closeBehavior)[number]["value"]>("tray");
  const [quality, setQuality] = useState<(typeof choiceOptions.quality)[number]["value"]>("1080p");
  const [speed, setSpeed] = useState<(typeof choiceOptions.speed)[number]["value"]>("1");
  const [longPressRate, setLongPressRate] =
    useState<(typeof choiceOptions.longPressRate)[number]["value"]>("2");
  const [danmakuArea, setDanmakuArea] =
    useState<(typeof choiceOptions.danmakuArea)[number]["value"]>("half");
  const [proxy, setProxy] = useState<(typeof choiceOptions.proxy)[number]["value"]>("system");

  const [fontSize, setFontSize] = useState(14);
  const [volume, setVolume] = useState(70);
  const [danmakuOpacity, setDanmakuOpacity] = useState(85);
  const [danmakuFontSize, setDanmakuFontSize] = useState(20);
  const [downloadSpeed, setDownloadSpeed] = useState("0");
  const [seedSpeed, setSeedSpeed] = useState("1.5");
  const [shareRatio, setShareRatio] = useState("1.5");
  const [seedHours, setSeedHours] = useState("12");
  const [recordingShortcut, setRecordingShortcut] = useState<ShortcutKey | null>(null);
  const [shortcuts, setShortcuts] = useState<Record<ShortcutKey, string>>(defaultShortcuts);
  const [toggles, setToggles] = useState({
    autoSync: true,
    blur: true,
    listScrollAnimation: true,
    autoPlay: true,
    resumeProgress: true,
    enableDanmaku: true,
    regexDanmakuFilter: false,
    pauseOnDanmakuEdit: true,
    autoMarkWatched: true,
    skipOpEd: false,
    deleteCacheAfterWatch: false,
    notifyUpdates: true,
    notifyDownloadDone: true,
    notifySyncFailure: true
  });

  const accentOptions = useMemo(
    () =>
      [
        { key: "mint", value: "#43c99f", label: "薄荷" },
        { key: "cherry", value: "#ff6b81", label: "樱桃" },
        { key: "sky", value: "#6aa6f0", label: "天空" },
        { key: "grape", value: "#9c87e8", label: "葡萄" },
        { key: "gold", value: "#ffb83d", label: "蜜瓜" }
      ] as const,
    []
  );

  const isAccountConnected = Boolean(session);
  const accountName = session ? session.nickname || session.username : "未连接 Bangumi";
  const accountInitial = accountName.slice(0, 1);
  const accountSubtitle = session
    ? `@${session.username} · Bangumi ID ${session.userId}`
    : "本机没有已保存的 Bangumi 登录凭证";
  const accountProfileUrl = session
    ? `https://bgm.tv/user/${encodeURIComponent(session.username)}`
    : null;
  const syncDescription = `${lastSyncLabel ?? formatSyncTime(syncState?.lastSuccessfulSyncAt)} · ${
    syncState?.pendingMutationCount ?? 0
  } 项待同步变更`;

  useEffect(() => {
    const timer = window.setTimeout(() => setToast(null), 2400);
    return () => window.clearTimeout(timer);
  }, [toast]);

  useEffect(() => {
    const node = document.getElementById(sectionDomId(active, activeSection));
    if (!node) {
      mainRef.current?.scrollTo({ top: 0, behavior: "smooth" });
      return;
    }
    node.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [active, activeSection]);

  function showToast(title: string, description?: string): void {
    setToast({ title, description });
  }

  function selectCategory(nextCategory: SettingsCategory): void {
    const category = categories.find((item) => item.key === nextCategory) ?? categories[0];
    setActive(category.key);
    setActiveSection(category.sections[0]?.key ?? "");
  }

  function selectSection(category: SettingsCategory, section: string): void {
    setActive(category);
    setActiveSection(section);
  }

  function setToggle(key: keyof typeof toggles, checked: boolean): void {
    setToggles((current) => ({ ...current, [key]: checked }));
  }

  async function handleSync(): Promise<void> {
    setSyncing(true);
    try {
      await refreshCollection(true);
      setLastSyncLabel(new Date().toLocaleString("zh-CN", { hour12: false }));
      showToast("同步完成", "收藏、进度与待同步状态已刷新。");
    } catch (error) {
      showToast("同步失败", error instanceof Error ? error.message : "请稍后重试。");
    } finally {
      setSyncing(false);
    }
  }

  async function handleDisconnect(): Promise<void> {
    setDisconnecting(true);
    try {
      await signOut();
      void navigate("/signin", { replace: true, state: { reason: "signed-out" } });
    } catch (error) {
      setDisconnecting(false);
      showToast("解绑失败", error instanceof Error ? error.message : "请稍后重试。");
    }
  }

  function handleDirectoryConfirm(): void {
    const nextDirectory = customDirectory.trim() || cacheDirectory;
    setCacheDirectory(nextDirectory);
    setDirectoryOpen(false);
    showToast("缓存目录已更新", nextDirectory);
  }

  function handleShortcutKey(key: ShortcutKey, event: KeyboardEvent<HTMLButtonElement>): void {
    event.preventDefault();
    const nextShortcut = formatShortcut(event);
    if (!nextShortcut) return;
    setShortcuts((current) => ({ ...current, [key]: nextShortcut }));
    setRecordingShortcut(null);
    showToast("快捷键已更新", `${shortcutLabels[key]}：${nextShortcut}`);
  }

  return (
    <WindowFrame crumb="设置">
      <div className="grid h-full min-h-0 grid-cols-[248px_1fr]">
        <aside className="border-line flex min-h-0 flex-col gap-1 overflow-auto border-r bg-[linear-gradient(180deg,rgba(255,255,255,.6),rgba(255,255,255,.3))] p-3.5 dark:bg-[linear-gradient(180deg,rgba(255,255,255,.04),rgba(255,255,255,.01))]">
          <button
            type="button"
            onClick={() => void navigate("/home")}
            className="text-ink-soft hover:bg-surface-2 hover:text-ink mb-1.5 flex items-center gap-2 rounded-xl px-3 py-2.5 text-sm font-bold transition"
          >
            <ChevronLeft className="size-4" />
            返回
          </button>

          <div className="text-ink-faint px-2.5 pt-2.5 pb-1 text-[10px] font-bold tracking-[0.14em] uppercase">
            设置
          </div>

          {categories.map(({ key, label, icon: Icon, sections }) => (
            <div key={key} className="flex flex-col gap-1">
              <button
                type="button"
                onClick={() => selectCategory(key)}
                className={cn(
                  "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition",
                  active === key
                    ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_6px_14px_rgba(34,179,136,.25)]"
                    : "text-ink-soft hover:bg-surface-2 hover:text-ink"
                )}
              >
                <Icon className="size-[18px] flex-none" />
                <span className="min-w-0 flex-1 text-left">{label}</span>
              </button>

              {active === key ? (
                <div className="border-line-strong ml-[30px] flex flex-col gap-1 border-l-[1.5px] pl-2.5">
                  {sections.map((section) => (
                    <button
                      key={section.key}
                      type="button"
                      onClick={() => selectSection(key, section.key)}
                      className={cn(
                        "rounded-lg px-2.5 py-1.5 text-left text-[11px] font-bold transition",
                        activeSection === section.key
                          ? "bg-mint-100 text-mint-600 dark:bg-mint-400/20 dark:text-mint-300"
                          : "text-ink-faint hover:bg-surface-2 hover:text-ink"
                      )}
                    >
                      {section.label}
                    </button>
                  ))}
                </div>
              ) : null}
            </div>
          ))}
        </aside>

        <main ref={mainRef} className="min-h-0 overflow-auto px-[34px] py-[26px] pb-[50px]">
          {active === "account" ? (
            <section>
              <PanelHeading
                title="账户与同步"
                description="管理你的 Bangumi 账户连接与数据同步方式。"
              />

              <SettingsGroup category="account" section="connection" title="账户">
                <div className="border-line bg-surface mt-4 flex items-center gap-4 rounded-[20px] border p-[18px] shadow-[var(--shadow-sm)]">
                  <GradientAvatar initial={accountInitial} size="lg" />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <b className="truncate text-base">{accountName}</b>
                      <Badge
                        variant={isAccountConnected ? "mint" : "outline"}
                        className="text-[10px]"
                      >
                        {isAccountConnected ? "已连接" : "未连接"}
                      </Badge>
                    </div>
                    <div className="text-ink-faint mt-0.5 truncate text-[12.5px]">
                      {accountSubtitle}
                    </div>
                  </div>
                  {accountProfileUrl ? (
                    <Button variant="soft" size="sm" asChild>
                      <a href={accountProfileUrl} target="_blank" rel="noreferrer">
                        <ExternalLink className="size-4" />
                        主页
                      </a>
                    </Button>
                  ) : (
                    <Button variant="soft" size="sm" onClick={() => void navigate("/signin")}>
                      去登录
                    </Button>
                  )}
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={!isAccountConnected || disconnecting}
                    onClick={() => void handleDisconnect()}
                  >
                    {disconnecting ? "解绑中…" : "解绑"}
                  </Button>
                </div>
              </SettingsGroup>

              <SettingsGroup category="account" section="sync" title="同步">
                <SettingsRow title="自动同步" description="在追番状态变化时自动推送到 Bangumi">
                  <Switch
                    checked={toggles.autoSync}
                    onCheckedChange={(checked) => setToggle("autoSync", checked)}
                  />
                </SettingsRow>
                <SettingsRow title="同步频率" description="后台刷新收藏与放送数据的间隔">
                  <ChoicePill
                    title="同步频率"
                    value={syncFrequency}
                    options={choiceOptions.syncFrequency}
                    onChange={setSyncFrequency}
                  />
                </SettingsRow>
                <SettingsRow title="上次同步" description={syncDescription}>
                  <Button size="sm" onClick={() => void handleSync()} disabled={syncing}>
                    <RefreshCw className={cn("size-4", syncing && "animate-spin")} />
                    {syncing ? "同步中…" : "立即同步"}
                  </Button>
                </SettingsRow>
              </SettingsGroup>
            </section>
          ) : null}

          {active === "appearance" ? (
            <section>
              <PanelHeading title="界面与外观" description="调整界面外观，立即生效。" />

              <SettingsGroup category="appearance" section="theme" title="主题模式">
                <div className="mt-3 flex flex-wrap gap-3">
                  <ThemeCard
                    label="浅色"
                    active={mode === "light"}
                    preview="border border-line bg-[linear-gradient(135deg,#eafaf3,#fff)]"
                    onClick={() => setMode("light")}
                  />
                  <ThemeCard
                    label="深色"
                    active={mode === "dark"}
                    preview="bg-[linear-gradient(135deg,#16202d,#0f1722)]"
                    onClick={() => setMode("dark")}
                  />
                  <ThemeCard
                    label="跟随系统"
                    active={mode === "system"}
                    preview="bg-[linear-gradient(135deg,#fff_0_50%,#16202d_50%_100%)]"
                    onClick={() => setMode("system")}
                  />
                </div>
              </SettingsGroup>

              <SettingsGroup category="appearance" section="accent" title="主题色">
                <SettingsRow title="强调色" description={`当前解析主题：${resolvedTheme}`}>
                  <div className="flex gap-3">
                    {accentOptions.map((option) => (
                      <button
                        key={option.key}
                        type="button"
                        onClick={() => setAccent(option.key)}
                        aria-label={`主题色 ${option.label}`}
                        className={cn(
                          "size-[34px] rounded-full shadow-[var(--shadow-sm)] transition",
                          accent === option.key && "outline-ink outline-2 outline-offset-4"
                        )}
                        style={{ background: option.value }}
                      />
                    ))}
                  </div>
                </SettingsRow>
              </SettingsGroup>

              <SettingsGroup category="appearance" section="interface" title="界面">
                <SettingsRow title="语言" description="界面显示语言">
                  <ChoicePill
                    title="语言"
                    value={language}
                    options={choiceOptions.language}
                    onChange={setLanguage}
                  />
                </SettingsRow>
                <SettingsRow title="界面字体大小">
                  <RangeControl
                    value={fontSize}
                    min={12}
                    max={18}
                    suffix="px"
                    onChange={setFontSize}
                  />
                </SettingsRow>
                <SettingsRow title="毛玻璃效果" description="侧栏与标题栏半透明模糊">
                  <Switch
                    checked={toggles.blur}
                    onCheckedChange={(checked) => setToggle("blur", checked)}
                  />
                </SettingsRow>
                <SettingsRow title="列表滚动动画" description="列表切换和滚动时使用柔和过渡">
                  <Switch
                    checked={toggles.listScrollAnimation}
                    onCheckedChange={(checked) => setToggle("listScrollAnimation", checked)}
                  />
                </SettingsRow>
              </SettingsGroup>

              <SettingsGroup category="appearance" section="startup" title="启动与窗口">
                <SettingsRow title="初始页面" description="启动应用时默认打开的首页">
                  <ChoicePill
                    title="初始页面"
                    value={initialPage}
                    options={choiceOptions.initialPage}
                    onChange={setInitialPage}
                  />
                </SettingsRow>
                <SettingsRow title="关闭行为" description="点击窗口关闭按钮时执行的操作">
                  <ChoicePill
                    title="关闭行为"
                    value={closeBehavior}
                    options={choiceOptions.closeBehavior}
                    onChange={setCloseBehavior}
                  />
                </SettingsRow>
              </SettingsGroup>
            </section>
          ) : null}

          {active === "playback" ? (
            <section>
              <PanelHeading title="播放" description="默认播放器与弹幕行为。" />

              <SettingsGroup category="playback" section="player" title="播放">
                <SettingsRow title="默认清晰度">
                  <ChoicePill
                    title="默认清晰度"
                    value={quality}
                    options={choiceOptions.quality}
                    onChange={setQuality}
                  />
                </SettingsRow>
                <SettingsRow title="自动连播" description="当前集结束后自动播放下一集">
                  <Switch
                    checked={toggles.autoPlay}
                    onCheckedChange={(checked) => setToggle("autoPlay", checked)}
                  />
                </SettingsRow>
                <SettingsRow title="记忆播放进度">
                  <Switch
                    checked={toggles.resumeProgress}
                    onCheckedChange={(checked) => setToggle("resumeProgress", checked)}
                  />
                </SettingsRow>
                <SettingsRow title="默认音量">
                  <RangeControl value={volume} min={0} max={100} suffix="%" onChange={setVolume} />
                </SettingsRow>
                <SettingsRow title="默认播放速度">
                  <ChoicePill
                    title="默认播放速度"
                    value={speed}
                    options={choiceOptions.speed}
                    onChange={setSpeed}
                  />
                </SettingsRow>
                <SettingsRow title="长按快进时倍率">
                  <ChoicePill
                    title="长按快进时倍率"
                    value={longPressRate}
                    options={choiceOptions.longPressRate}
                    onChange={setLongPressRate}
                  />
                </SettingsRow>
              </SettingsGroup>

              <SettingsGroup category="playback" section="danmaku" title="弹幕显示">
                <SettingsRow title="启用弹幕">
                  <Switch
                    checked={toggles.enableDanmaku}
                    onCheckedChange={(checked) => setToggle("enableDanmaku", checked)}
                  />
                </SettingsRow>
                <SettingsRow title="弹幕透明度">
                  <RangeControl
                    value={danmakuOpacity}
                    min={10}
                    max={100}
                    suffix="%"
                    onChange={setDanmakuOpacity}
                  />
                </SettingsRow>
                <SettingsRow title="显示区域">
                  <ChoicePill
                    title="显示区域"
                    value={danmakuArea}
                    options={choiceOptions.danmakuArea}
                    onChange={setDanmakuArea}
                  />
                </SettingsRow>
                <SettingsRow title="字号">
                  <RangeControl
                    value={danmakuFontSize}
                    min={12}
                    max={36}
                    suffix="px"
                    onChange={setDanmakuFontSize}
                  />
                </SettingsRow>
                <SettingsRow title="编辑弹幕时自动暂停">
                  <Switch
                    checked={toggles.pauseOnDanmakuEdit}
                    onCheckedChange={(checked) => setToggle("pauseOnDanmakuEdit", checked)}
                  />
                </SettingsRow>
              </SettingsGroup>

              <SettingsGroup category="playback" section="filter" title="弹幕过滤">
                <SettingsRow title="启用弹幕正则过滤">
                  <Switch
                    checked={toggles.regexDanmakuFilter}
                    onCheckedChange={(checked) => setToggle("regexDanmakuFilter", checked)}
                  />
                </SettingsRow>
                <SettingsRow
                  title="弹幕正则过滤管理"
                  description="管理用于隐藏弹幕内容的正则表达式规则"
                >
                  <button
                    type="button"
                    aria-label="添加弹幕正则过滤"
                    className="border-line-strong bg-surface text-ink-soft grid size-8 place-items-center rounded-full border"
                  >
                    <Plus className="size-4" />
                  </button>
                </SettingsRow>
              </SettingsGroup>

              <SettingsGroup category="playback" section="automation" title="播放自动化">
                <SettingsRow
                  title="播放完成自动标记看过"
                  description="播放进度达到 90% 时自动标记本集为看过"
                >
                  <Switch
                    checked={toggles.autoMarkWatched}
                    onCheckedChange={(checked) => setToggle("autoMarkWatched", checked)}
                  />
                </SettingsRow>
                <SettingsRow title="自动跳过 OP / ED">
                  <Switch
                    checked={toggles.skipOpEd}
                    onCheckedChange={(checked) => setToggle("skipOpEd", checked)}
                  />
                </SettingsRow>
              </SettingsGroup>
            </section>
          ) : null}

          {active === "sources" ? (
            <section>
              <PanelHeading title="数据源管理" />
              <SettingsGroup category="sources" section="sources" title="数据源">
                <PlaceholderCard title="暂无数据源配置" />
              </SettingsGroup>
            </section>
          ) : null}

          {active === "cache" ? (
            <section>
              <PanelHeading title="下载与缓存" description="管理下载、缓存目录与 BT 做种策略。" />

              <SettingsGroup category="cache" section="cache" title="缓存">
                <SettingsRow title="缓存目录" description={cacheDirectory}>
                  <Button variant="outline" size="sm" onClick={() => setDirectoryOpen(true)}>
                    <FolderOpen className="size-4" />
                    更改
                  </Button>
                </SettingsRow>
                <SettingsRow title="看完后自动删除缓存">
                  <Switch
                    checked={toggles.deleteCacheAfterWatch}
                    onCheckedChange={(checked) => setToggle("deleteCacheAfterWatch", checked)}
                  />
                </SettingsRow>
                <SettingsRow title="清理缓存" description="真实文件删除尚未接入">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => showToast("缓存清理尚未接入", "未删除任何本地文件。")}
                  >
                    <Trash2 className="size-4" />
                    清理
                  </Button>
                </SettingsRow>
              </SettingsGroup>

              <SettingsGroup category="cache" section="network" title="网络">
                <SettingsRow title="代理设置">
                  <ChoicePill
                    title="代理设置"
                    value={proxy}
                    options={choiceOptions.proxy}
                    onChange={setProxy}
                  />
                </SettingsRow>
                <SettingsRow
                  title="最大下载速度"
                  description="多任务下载时，所有任务的合计速度不会超过此上限；0 表示不限速"
                >
                  <UnitInput value={downloadSpeed} onChange={setDownloadSpeed} unit="MB/s" />
                </SettingsRow>
              </SettingsGroup>

              <SettingsGroup category="cache" section="bt" title="BitTorrent">
                <SettingsRow
                  title="做种速度限制"
                  description="BT 网络依赖用户分享，建议保留一定上传带宽，共同维护健康的分享环境"
                >
                  <UnitInput value={seedSpeed} onChange={setSeedSpeed} unit="MB/s" />
                </SettingsRow>
                <SettingsRow title="分享率限制" description="上传量 / 下载量达到设定比例后停止做种">
                  <UnitInput value={shareRatio} onChange={setShareRatio} unit="x" step="0.1" />
                </SettingsRow>
                <SettingsRow
                  title="做种时间限制"
                  description="下载完成后继续做种的小时数；0 表示不限制"
                >
                  <UnitInput value={seedHours} onChange={setSeedHours} unit="小时" />
                </SettingsRow>
              </SettingsGroup>
            </section>
          ) : null}

          {active === "notify" ? (
            <section>
              <PanelHeading title="通知" description="控制桌面提醒的默认行为。" />
              <SettingsGroup category="notify" section="desktop" title="桌面通知">
                <SettingsRow title="追番更新提醒" description="在追番剧集有新集放送时通知">
                  <Switch
                    checked={toggles.notifyUpdates}
                    onCheckedChange={(checked) => setToggle("notifyUpdates", checked)}
                  />
                </SettingsRow>
                <SettingsRow title="下载完成提醒">
                  <Switch
                    checked={toggles.notifyDownloadDone}
                    onCheckedChange={(checked) => setToggle("notifyDownloadDone", checked)}
                  />
                </SettingsRow>
                <SettingsRow title="同步失败提醒">
                  <Switch
                    checked={toggles.notifySyncFailure}
                    onCheckedChange={(checked) => setToggle("notifySyncFailure", checked)}
                  />
                </SettingsRow>
              </SettingsGroup>
            </section>
          ) : null}

          {active === "keys" ? (
            <section>
              <PanelHeading title="快捷键" description="点击快捷键后按下新的组合键。" />
              <SettingsGroup category="keys" section="playback" title="播放控制">
                {(
                  ["playPause", "seek", "nextEpisode", "danmaku", "fullscreen"] as ShortcutKey[]
                ).map((key) => (
                  <ShortcutRow
                    key={key}
                    label={shortcutLabels[key]}
                    value={shortcuts[key]}
                    recording={recordingShortcut === key}
                    onStart={() => setRecordingShortcut(key)}
                    onKeyDown={(event) => handleShortcutKey(key, event)}
                    onBlur={() => setRecordingShortcut(null)}
                  />
                ))}
              </SettingsGroup>
              <SettingsGroup category="keys" section="app" title="应用操作">
                <ShortcutRow
                  label={shortcutLabels.search}
                  value={shortcuts.search}
                  recording={recordingShortcut === "search"}
                  onStart={() => setRecordingShortcut("search")}
                  onKeyDown={(event) => handleShortcutKey("search", event)}
                  onBlur={() => setRecordingShortcut(null)}
                />
              </SettingsGroup>
            </section>
          ) : null}

          {active === "logs" ? (
            <section>
              <PanelHeading title="日志" />
              <SettingsGroup category="logs" section="logs" title="日志">
                <PlaceholderCard title="暂无日志内容" />
              </SettingsGroup>
            </section>
          ) : null}

          {active === "about" ? (
            <section>
              <PanelHeading title="关于" />
              <SettingsGroup category="about" section="version" title="版本">
                <div className="border-line bg-surface mt-4 flex items-start gap-5 rounded-[20px] border p-6 shadow-[var(--shadow-sm)]">
                  <div className="text-on-accent grid size-16 flex-none place-items-center rounded-2xl bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[var(--shadow-md)]">
                    <MelonMark className="size-8" />
                  </div>
                  <div className="min-w-0 flex-1 pt-1">
                    <div className="text-lg font-extrabold">melonbang</div>
                    <div className="text-ink-faint mt-0.5 text-[13px]">
                      v0.1.0 · Goal 1 · 追番基础版
                    </div>
                    <div className="mt-3.5 flex flex-wrap items-center gap-2">
                      <Button
                        size="sm"
                        onClick={() => showToast("已是最新版本", "当前版本 v0.1.0。")}
                      >
                        检查更新
                      </Button>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => showToast("官网暂未接入", "官网链接尚未配置。")}
                      >
                        官网
                      </Button>
                      <Button variant="outline" size="sm" asChild>
                        <a
                          href="https://github.com/83977/melonbang"
                          target="_blank"
                          rel="noreferrer"
                        >
                          <ExternalLink className="size-4" />
                          GitHub
                        </a>
                      </Button>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => showToast("开源许可", "许可证详情页暂未接入。")}
                      >
                        开源许可
                      </Button>
                    </div>
                  </div>
                </div>
              </SettingsGroup>

              <SettingsGroup category="about" section="notes" title="更新说明">
                <SettingsRow title="更新说明" description="查看当前版本的主要变化">
                  <Button variant="outline" size="sm" onClick={() => setNotesOpen(true)}>
                    查看
                  </Button>
                </SettingsRow>
              </SettingsGroup>

              <SettingsGroup category="about" section="links" title="链接">
                <SettingsRow title="反馈与建议">
                  <Button variant="outline" size="sm" asChild>
                    <a
                      href="https://github.com/83977/melonbang/issues"
                      target="_blank"
                      rel="noreferrer"
                    >
                      <ExternalLink className="size-4" />
                      GitHub Issues
                    </a>
                  </Button>
                </SettingsRow>
              </SettingsGroup>

              <SettingsGroup category="about" section="thanks" title="鸣谢">
                <PlaceholderCard title="暂无鸣谢内容" />
              </SettingsGroup>
            </section>
          ) : null}
        </main>
      </div>

      <DirectoryDialog
        open={directoryOpen}
        current={cacheDirectory}
        customValue={customDirectory}
        onOpenChange={setDirectoryOpen}
        onSelect={setCacheDirectory}
        onCustomChange={setCustomDirectory}
        onConfirm={handleDirectoryConfirm}
      />
      <UpdateNotesDialog open={notesOpen} onOpenChange={setNotesOpen} />
      <SettingsToast toast={toast} />
    </WindowFrame>
  );
}

function PanelHeading({ title, description }: { title: string; description?: string }) {
  return (
    <div>
      <h2 className="m-0 text-[22px] font-extrabold">{title}</h2>
      {description ? <p className="text-ink-faint mt-1 text-sm">{description}</p> : null}
    </div>
  );
}

function SettingsGroup({
  category,
  section,
  title,
  children
}: {
  category: SettingsCategory;
  section: string;
  title: string;
  children: ReactNode;
}) {
  return (
    <div id={sectionDomId(category, section)} className="scroll-mt-6">
      <div className="text-ink-faint mt-6 mb-1.5 text-[13px] font-extrabold tracking-[0.05em] uppercase">
        {title}
      </div>
      {children}
    </div>
  );
}

function SettingsRow({
  title,
  description,
  children
}: {
  title: string;
  description?: ReactNode;
  children?: ReactNode;
}) {
  return (
    <div className="border-line grid grid-cols-[minmax(0,1fr)_220px] items-center gap-4 py-3.5 [&:not(:first-child)]:border-t">
      <div className="min-w-0 flex-1">
        <div className="text-sm font-semibold">{title}</div>
        {description ? <div className="text-ink-faint mt-0.5 text-xs">{description}</div> : null}
      </div>
      {children ? (
        <div className="flex min-w-0 items-center justify-end gap-2">{children}</div>
      ) : (
        <span />
      )}
    </div>
  );
}

function ChoicePill<T extends string>({
  title,
  value,
  options,
  onChange
}: {
  title: string;
  value: T;
  options: readonly ChoiceOption<T>[];
  onChange: (value: T) => void;
}) {
  const [open, setOpen] = useState(false);
  const selected = options.find((option) => option.value === value) ?? options[0];

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="border-line-strong bg-surface hover:border-mint-300 inline-flex items-center gap-2 rounded-[10px] border px-3.5 py-2 text-[13px] font-bold transition"
      >
        {selected.label}
        <ChevronRight className="text-ink-faint size-3.5" />
      </button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
          </DialogHeader>
          <DialogBody className="flex flex-col gap-2">
            {options.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => {
                  onChange(option.value);
                  setOpen(false);
                }}
                className={cn(
                  "border-line bg-surface hover:border-mint-300 flex items-center gap-3 rounded-[14px] border p-3 text-left transition",
                  option.value === value && "border-mint-300 bg-mint-50 dark:bg-mint-400/10"
                )}
              >
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-bold">{option.label}</span>
                  {option.description ? (
                    <span className="text-ink-faint mt-0.5 block text-xs">
                      {option.description}
                    </span>
                  ) : null}
                </span>
                {option.value === value ? <Check className="text-mint-600 size-4" /> : null}
              </button>
            ))}
          </DialogBody>
        </DialogContent>
      </Dialog>
    </>
  );
}

function ThemeCard({
  label,
  active,
  preview,
  onClick
}: {
  label: string;
  active: boolean;
  preview: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "hover:border-mint-300 w-32 rounded-[14px] border-[1.5px] p-3 text-left transition",
        active ? "border-mint-400 shadow-[0_0_0_3px_rgba(67,201,159,.2)]" : "border-line-strong"
      )}
    >
      <div className={cn("mb-2.5 h-[54px] rounded-[9px]", preview)} />
      <b className="text-[13px]">{label}</b>
    </button>
  );
}

function RangeControl({
  value,
  min,
  max,
  suffix,
  onChange
}: {
  value: number;
  min: number;
  max: number;
  suffix: string;
  onChange: (value: number) => void;
}) {
  return (
    <div className="flex items-center gap-3">
      <input
        type="range"
        min={min}
        max={max}
        value={value}
        onChange={(event) => onChange(Number(event.currentTarget.value))}
        className="w-[180px]"
      />
      <span className="text-ink-soft w-12 text-right text-[12px] font-extrabold">
        {value}
        {suffix}
      </span>
    </div>
  );
}

function UnitInput({
  value,
  unit,
  step = "1",
  onChange
}: {
  value: string;
  unit: string;
  step?: string;
  onChange: (value: string) => void;
}) {
  return (
    <div className="grid w-[156px] grid-cols-[96px_44px] items-center gap-2">
      <Input
        type="number"
        inputMode="decimal"
        min="0"
        step={step}
        value={value}
        onChange={(event) => onChange(event.currentTarget.value)}
        className="h-9 w-full rounded-[10px] px-3 py-1.5 text-right"
      />
      <span className="text-ink-soft text-left text-[12px] font-extrabold">{unit}</span>
    </div>
  );
}

function ShortcutRow({
  label,
  value,
  recording,
  onStart,
  onKeyDown,
  onBlur
}: {
  label: string;
  value: string;
  recording: boolean;
  onStart: () => void;
  onKeyDown: (event: KeyboardEvent<HTMLButtonElement>) => void;
  onBlur: () => void;
}) {
  return (
    <SettingsRow title={label}>
      <button
        type="button"
        onClick={onStart}
        onKeyDown={onKeyDown}
        onBlur={onBlur}
        className={cn(
          "border-line-strong text-ink-soft rounded-full border px-2.5 py-[3px] text-[11.5px] font-bold transition",
          recording && "border-mint-300 bg-mint-50 text-mint-600 dark:bg-mint-400/15"
        )}
      >
        {recording ? "按下新的快捷键" : value}
      </button>
    </SettingsRow>
  );
}

function DirectoryDialog({
  open,
  current,
  customValue,
  onOpenChange,
  onSelect,
  onCustomChange,
  onConfirm
}: {
  open: boolean;
  current: string;
  customValue: string;
  onOpenChange: (open: boolean) => void;
  onSelect: (value: string) => void;
  onCustomChange: (value: string) => void;
  onConfirm: () => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>选择缓存目录</DialogTitle>
        </DialogHeader>
        <DialogBody className="flex flex-col gap-3">
          <div className="flex flex-col gap-2">
            {directoryOptions.map((option) => (
              <button
                key={option}
                type="button"
                onClick={() => {
                  onSelect(option);
                  onCustomChange("");
                }}
                className={cn(
                  "border-line bg-surface hover:border-mint-300 flex items-center gap-3 rounded-[14px] border p-3 text-left transition",
                  current === option &&
                    !customValue &&
                    "border-mint-300 bg-mint-50 dark:bg-mint-400/10"
                )}
              >
                <FolderOpen className="text-ink-faint size-4" />
                <span className="min-w-0 flex-1 truncate text-sm font-bold">{option}</span>
                {current === option && !customValue ? (
                  <Check className="text-mint-600 size-4" />
                ) : null}
              </button>
            ))}
          </div>
          <Input
            value={customValue}
            onChange={(event) => onCustomChange(event.currentTarget.value)}
            placeholder="输入自定义目录"
            className="rounded-[14px]"
          />
          <div className="flex justify-end gap-2">
            <Button variant="outline" size="sm" onClick={() => onOpenChange(false)}>
              取消
            </Button>
            <Button size="sm" onClick={onConfirm}>
              确定
            </Button>
          </div>
        </DialogBody>
      </DialogContent>
    </Dialog>
  );
}

function UpdateNotesDialog({
  open,
  onOpenChange
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>更新说明</DialogTitle>
        </DialogHeader>
        <DialogBody>
          <div className="border-line bg-surface-2 text-ink-faint rounded-[14px] border p-5 text-center text-sm font-semibold">
            暂无更新说明内容。
          </div>
        </DialogBody>
      </DialogContent>
    </Dialog>
  );
}

function PlaceholderCard({ title }: { title: string }) {
  return (
    <div className="border-line bg-surface mt-4 grid min-h-[140px] place-items-center rounded-[20px] border p-6 text-center shadow-[var(--shadow-sm)]">
      <div className="flex flex-col items-center gap-2">
        <div className="bg-surface-3 text-ink-faint grid size-12 place-items-center rounded-2xl">
          <Plus className="size-5" />
        </div>
        <b className="text-ink-soft text-sm">{title}</b>
      </div>
    </div>
  );
}

function SettingsToast({ toast }: { toast: ToastState | null }) {
  if (!toast) return null;

  return (
    <div className="border-line bg-surface fixed right-6 bottom-6 z-50 flex max-w-[340px] items-center gap-3 rounded-[14px] border p-3.5 shadow-[var(--shadow-lg)]">
      <div className="bg-mint-100 text-mint-600 dark:bg-mint-400/20 grid size-[34px] shrink-0 place-items-center rounded-[10px]">
        <Check className="size-4" />
      </div>
      <div className="min-w-0">
        <b className="block text-[13.5px]">{toast.title}</b>
        {toast.description ? (
          <span className="text-ink-faint block truncate text-xs">{toast.description}</span>
        ) : null}
      </div>
    </div>
  );
}

function formatShortcut(event: KeyboardEvent<HTMLButtonElement>): string {
  const key = event.key;
  if (["Control", "Shift", "Alt", "Meta"].includes(key)) return "";
  if (key === "Escape") return "";

  const parts: string[] = [];
  if (event.ctrlKey) parts.push("Ctrl");
  if (event.altKey) parts.push("Alt");
  if (event.shiftKey) parts.push("Shift");
  if (event.metaKey) parts.push("Meta");

  const normalized = {
    " ": "Space",
    ArrowLeft: "←",
    ArrowRight: "→",
    ArrowUp: "↑",
    ArrowDown: "↓"
  }[key];

  parts.push(normalized ?? key.toUpperCase());
  return parts.join(" ");
}

function MelonMark({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <circle cx="12" cy="13" r="8" />
      <path d="M12 5c-1.3 0-2.4.5-3.2 1.3M15.2 6.3A4.5 4.5 0 0 0 12 5" />
      <path d="M9 10v6M12 10v6M15 10v6" />
    </svg>
  );
}
