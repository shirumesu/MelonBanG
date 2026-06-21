import { useState } from "react";
import type { ButtonHTMLAttributes, ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import {
  ChevronLeft,
  Expand,
  MessageSquareText,
  Pause,
  Play,
  Send,
  SkipBack,
  SkipForward,
  Volume2
} from "lucide-react";
import {
  DANMAKU_COLORS,
  DANMAKU_MESSAGES,
  NOW_PLAYING,
  PLAYER_EPISODES,
  SPEEDS,
  type PlayerEpisode
} from "@/data/player";
import { WindowFrame } from "@/app/shell/WindowFrame";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";

type RightPanel = "episodes" | "settings";
type DanmakuArea = "quarter" | "half" | "full";
type SendMode = "scroll" | "top" | "bottom";

const colorChoices = ["#fff", "#ffd56b", "#ff9eb5", "#86c5ff", "#9be7c4", "#c8a8f0"];

function PlayerIconButton({
  active,
  className,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { active?: boolean }) {
  return (
    <button
      type="button"
      className={cn(
        "grid flex-none place-items-center rounded-lg bg-transparent p-1 text-white/90 transition hover:text-white",
        active && "text-mint-300",
        className
      )}
      {...props}
    >
      {children}
    </button>
  );
}

function PlayerPop({ children, onClick }: { children: ReactNode; onClick?: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-full bg-white/[0.15] px-2.5 py-1 text-xs font-bold whitespace-nowrap text-white transition hover:bg-white/[0.25]"
    >
      {children}
    </button>
  );
}

function EpisodeItem({
  episode,
  selected,
  onSelect
}: {
  episode: PlayerEpisode;
  selected: boolean;
  onSelect: () => void;
}) {
  const current = selected || episode.state === "current";
  const watched = episode.state === "watched";
  const unaired = episode.state === "unaired";

  return (
    <button
      type="button"
      disabled={unaired}
      onClick={onSelect}
      className={cn(
        "flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition",
        current && "bg-mint-50 outline-mint-200 dark:bg-mint-400/15 outline outline-1",
        !current && "hover:bg-surface-2",
        unaired && "cursor-not-allowed opacity-60"
      )}
    >
      <span
        className={cn(
          "bg-surface-3 text-ink-soft grid size-[30px] flex-none place-items-center rounded-[9px] text-[13px] font-extrabold",
          current && "bg-mint-400 text-on-accent",
          watched && !current && "bg-mint-100 text-mint-600"
        )}
      >
        {episode.n}
      </span>
      <span className="min-w-0 flex-1">
        <b className="block truncate text-[13px]">
          第{episode.n}话 · {episode.title}
        </b>
        <span className="text-ink-faint text-[11px]">{episode.duration}</span>
      </span>
      {current ? (
        <Badge variant="mint" className="text-[10px]">
          播放中
        </Badge>
      ) : watched ? (
        <span className="text-ink-faint text-[11px]">已看</span>
      ) : unaired ? (
        <Badge variant="outline" className="text-[10px]">
          待播
        </Badge>
      ) : null}
    </button>
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
    <div className="border-line flex items-center gap-3 py-[11px] [&:not(:first-child)]:border-t">
      <div className="flex-1">
        <div className="text-[13px] font-semibold">{title}</div>
        {description ? (
          <div className="text-ink-faint text-[11px] font-medium">{description}</div>
        ) : null}
      </div>
      {children}
    </div>
  );
}

function Segmented<T extends string>({
  options,
  value,
  onChange
}: {
  options: Array<{ value: T; label: string }>;
  value: T;
  onChange: (value: T) => void;
}) {
  return (
    <div className="border-line bg-surface-2 inline-flex rounded-full border p-[3px]">
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          onClick={() => onChange(option.value)}
          className={cn(
            "rounded-full px-2.5 py-1 text-[11.5px] font-bold transition",
            option.value === value ? "bg-mint-400 text-on-accent" : "text-ink-soft hover:text-ink"
          )}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

export function PlayerRoute() {
  const navigate = useNavigate();
  const [playing, setPlaying] = useState(true);
  const [danmakuEnabled, setDanmakuEnabled] = useState(true);
  const [panel, setPanel] = useState<RightPanel>("episodes");
  const [speedIndex, setSpeedIndex] = useState(2);
  const [selectedEpisode, setSelectedEpisode] = useState(7);
  const [danmakuText, setDanmakuText] = useState("");
  const [showDanmaku, setShowDanmaku] = useState(true);
  const [danmakuArea, setDanmakuArea] = useState<DanmakuArea>("half");
  const [sendMode, setSendMode] = useState<SendMode>("scroll");
  const [selectedColor, setSelectedColor] = useState(colorChoices[0]);
  const [blockedTypes, setBlockedTypes] = useState(new Set(["top", "bottom"]));

  function cycleSpeed(): void {
    setSpeedIndex((value) => (value + 1) % SPEEDS.length);
  }

  function toggleBlocked(type: string): void {
    setBlockedTypes((current) => {
      const next = new Set(current);
      if (next.has(type)) {
        next.delete(type);
      } else {
        next.add(type);
      }
      return next;
    });
  }

  const mainIcon = playing ? (
    <Pause className="size-8 fill-current" />
  ) : (
    <Play className="size-8 fill-current" />
  );
  const smallIcon = playing ? (
    <Pause className="size-[18px] fill-current" />
  ) : (
    <Play className="size-[18px] fill-current" />
  );

  return (
    <WindowFrame crumb="正在播放">
      <div className="grid h-full min-h-0 grid-cols-[1fr_344px] max-[1080px]:grid-cols-1">
        <section className="flex min-w-0 flex-col bg-[var(--player-bg)]">
          <div className="relative min-h-0 flex-1 overflow-hidden bg-[radial-gradient(120%_100%_at_70%_20%,rgba(22,64,74,.6),var(--player-bg)_70%)]">
            <div className="absolute inset-0 bg-[linear-gradient(135deg,var(--mint-600),var(--sky-500))] opacity-[.18]" />

            <div
              className={cn(
                "pointer-events-none absolute inset-0 z-[4] overflow-hidden transition-opacity",
                danmakuEnabled ? "opacity-100" : "opacity-0"
              )}
            >
              {DANMAKU_MESSAGES.map((message, i) => (
                <span
                  key={`${message}-${i}`}
                  className="absolute text-[18px] font-bold whitespace-nowrap text-white will-change-transform [text-shadow:0_1px_4px_rgba(0,0,0,.6)]"
                  style={{
                    top: `${6 + ((i * 37) % 52)}%`,
                    color: DANMAKU_COLORS[i % DANMAKU_COLORS.length],
                    fontSize: `${15 + (i % 4) * 2}px`,
                    animation: `danmaku-fly ${7 + (i % 5)}s linear ${i * 0.55}s infinite`
                  }}
                >
                  {message}
                </span>
              ))}
            </div>

            <div className="absolute top-0 right-0 left-0 z-10 flex items-center gap-3 bg-[linear-gradient(180deg,rgba(0,0,0,.4),transparent)] px-[18px] py-4 text-white">
              <button
                type="button"
                onClick={() => void navigate(-1)}
                className="grid size-9 place-items-center rounded-xl bg-white/[0.18] text-white transition hover:bg-white/[0.25]"
                aria-label="返回"
              >
                <ChevronLeft className="size-[18px]" />
              </button>
              <div className="text-sm font-bold">
                {NOW_PLAYING.title} · {NOW_PLAYING.ep}「{NOW_PLAYING.epTitle}」
              </div>
              <div className="flex-1" />
              <span className="rounded-full bg-white/[0.15] px-2.5 py-1 text-[11.5px] font-bold text-white">
                {NOW_PLAYING.source}
              </span>
            </div>

            <div
              className={cn(
                "absolute inset-0 z-[5] grid place-items-center transition",
                playing && "opacity-0"
              )}
            >
              <button
                type="button"
                onClick={() => setPlaying((value) => !value)}
                className="grid size-[78px] place-items-center rounded-full border border-white/[0.3] bg-white/[0.15] text-white backdrop-blur-md transition hover:scale-105 hover:bg-white/[0.25]"
                aria-label={playing ? "暂停" : "播放"}
              >
                {mainIcon}
              </button>
            </div>
          </div>

          <div className="border-t border-[var(--player-border)] bg-[var(--player-surface)] px-4 pt-2.5 pb-3.5 text-white">
            <div className="mb-2.5 h-[5px] cursor-pointer rounded-full bg-white/20">
              <div className="relative h-full rounded-full">
                <div className="absolute top-0 bottom-0 left-0 w-[54%] rounded-full bg-white/[0.3]" />
                <div className="absolute top-0 bottom-0 left-0 w-[42%] rounded-full bg-[linear-gradient(90deg,var(--mint-400),var(--mint-300))]" />
                <div className="absolute top-1/2 left-[42%] size-[13px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-white shadow-[0_2px_6px_rgba(0,0,0,.4)]" />
              </div>
            </div>

            <div className="flex items-center gap-3 text-sm">
              <div className="flex flex-none items-center gap-2.5">
                <PlayerIconButton onClick={() => setPlaying((value) => !value)}>
                  {smallIcon}
                </PlayerIconButton>
                <PlayerIconButton title="上一集">
                  <SkipBack className="size-[18px] fill-current" />
                </PlayerIconButton>
                <PlayerIconButton title="下一集">
                  <SkipForward className="size-[18px] fill-current" />
                </PlayerIconButton>
                <PlayerIconButton title="音量">
                  <Volume2 className="size-5" />
                </PlayerIconButton>
                <div className="relative h-1 w-[60px] flex-none rounded-full bg-white/[0.25] after:absolute after:inset-y-0 after:left-0 after:w-[64%] after:rounded-full after:bg-white" />
                <span className="font-semibold whitespace-nowrap text-white/90 tabular-nums">
                  {NOW_PLAYING.time}
                </span>
              </div>

              <div className="flex min-w-0 flex-1 items-center justify-center gap-2">
                <PlayerIconButton
                  active={danmakuEnabled}
                  title="弹幕开关"
                  onClick={() => setDanmakuEnabled((value) => !value)}
                  aria-pressed={danmakuEnabled}
                >
                  <MessageSquareText className="size-4" />
                </PlayerIconButton>
                <div className="flex max-w-[520px] flex-1 items-center gap-2 rounded-full border border-[var(--player-border)] bg-[var(--player-bg)] px-3.5 py-2 text-white">
                  <input
                    value={danmakuText}
                    onChange={(event) => setDanmakuText(event.target.value)}
                    placeholder="发个友善的弹幕，见证当下…"
                    className="min-w-0 flex-1 bg-transparent text-[13px] outline-none placeholder:text-[#6c7c85]"
                  />
                  <span className="text-[11px] text-[#6c7c85]">
                    {Math.max(0, 28 - danmakuText.length)}
                  </span>
                </div>
                <Button size="sm">
                  <Send className="size-4" />
                  发送
                </Button>
              </div>

              <div className="flex flex-none items-center gap-2.5">
                <PlayerPop>1080P</PlayerPop>
                <PlayerPop onClick={() => setPanel("episodes")}>选集</PlayerPop>
                <PlayerPop onClick={cycleSpeed}>{SPEEDS[speedIndex]}</PlayerPop>
                <PlayerIconButton title="全屏">
                  <Expand className="size-[18px]" />
                </PlayerIconButton>
              </div>
            </div>
          </div>
        </section>

        <aside className="border-line bg-surface flex min-h-0 flex-col border-l max-[1080px]:hidden">
          <div className="border-line border-b px-3.5 py-3">
            <div className="border-line bg-surface inline-flex w-full gap-1 rounded-full border p-1.5 shadow-none">
              <button
                type="button"
                onClick={() => setPanel("episodes")}
                className={cn(
                  "flex flex-1 justify-center rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                  panel === "episodes"
                    ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_5px_12px_rgba(34,179,136,.28)]"
                    : "text-ink-soft hover:text-ink"
                )}
              >
                选集
              </button>
              <button
                type="button"
                onClick={() => setPanel("settings")}
                className={cn(
                  "flex flex-1 justify-center rounded-full px-[15px] py-2 text-[13px] font-bold transition",
                  panel === "settings"
                    ? "text-on-accent bg-[linear-gradient(135deg,var(--mint-400),var(--mint-300))] shadow-[0_5px_12px_rgba(34,179,136,.28)]"
                    : "text-ink-soft hover:text-ink"
                )}
              >
                弹幕设置
              </button>
            </div>
          </div>

          <div className="min-h-0 flex-1 overflow-auto px-3.5 py-3">
            {panel === "episodes" ? (
              <div className="flex flex-col gap-1">
                {PLAYER_EPISODES.map((episode) => (
                  <EpisodeItem
                    key={episode.n}
                    episode={episode}
                    selected={episode.n === selectedEpisode}
                    onSelect={() => setSelectedEpisode(episode.n)}
                  />
                ))}
              </div>
            ) : (
              <div>
                <SettingRow title="显示弹幕" description="关闭后将隐藏所有弹幕">
                  <Switch checked={showDanmaku} onCheckedChange={setShowDanmaku} />
                </SettingRow>
                <SettingRow title="弹幕透明度">
                  <input type="range" min="10" max="100" defaultValue="80" className="w-[120px]" />
                </SettingRow>
                <SettingRow title="显示区域">
                  <Segmented<DanmakuArea>
                    value={danmakuArea}
                    onChange={setDanmakuArea}
                    options={[
                      { value: "quarter", label: "1/4" },
                      { value: "half", label: "半屏" },
                      { value: "full", label: "全屏" }
                    ]}
                  />
                </SettingRow>
                <SettingRow title="字体大小">
                  <input type="range" min="12" max="36" defaultValue="18" className="w-[120px]" />
                </SettingRow>
                <SettingRow title="弹幕速度">
                  <input type="range" min="1" max="10" defaultValue="6" className="w-[120px]" />
                </SettingRow>
                <SettingRow title="弹幕密度">
                  <input type="range" min="1" max="10" defaultValue="7" className="w-[120px]" />
                </SettingRow>

                <div className="bg-line my-[18px] h-px" />
                <div className="text-ink-faint mb-2 text-xs font-bold">发送偏好</div>

                <SettingRow title="发送模式">
                  <Segmented<SendMode>
                    value={sendMode}
                    onChange={setSendMode}
                    options={[
                      { value: "scroll", label: "滚动" },
                      { value: "top", label: "顶部" },
                      { value: "bottom", label: "底部" }
                    ]}
                  />
                </SettingRow>
                <SettingRow title="弹幕颜色">
                  <div className="flex gap-1.5">
                    {colorChoices.map((color) => (
                      <button
                        key={color}
                        type="button"
                        aria-label={`选择颜色 ${color}`}
                        onClick={() => setSelectedColor(color)}
                        className={cn(
                          "size-[22px] rounded-full",
                          selectedColor === color && "outline-mint-400 outline-2 outline-offset-2"
                        )}
                        style={{ background: color }}
                      />
                    ))}
                  </div>
                </SettingRow>
                <SettingRow title="描边阴影" description="提升暗背景下可读性">
                  <Switch defaultChecked />
                </SettingRow>

                <div className="bg-line my-[18px] h-px" />
                <div className="text-ink-faint mb-2 text-xs font-bold">屏蔽类型</div>
                <div className="flex flex-wrap gap-2">
                  {[
                    { key: "scroll", label: "滚动" },
                    { key: "top", label: "顶部" },
                    { key: "bottom", label: "底部" },
                    { key: "color", label: "彩色" }
                  ].map((entry) => {
                    const blocked = blockedTypes.has(entry.key);
                    return (
                      <button
                        key={entry.key}
                        type="button"
                        onClick={() => toggleBlocked(entry.key)}
                        className={cn(
                          "rounded-full border px-3 py-1.5 text-xs font-bold transition",
                          blocked
                            ? "bg-cherry-400 border-transparent text-white"
                            : "border-line bg-surface-2 text-ink-soft"
                        )}
                      >
                        {entry.label}
                      </button>
                    );
                  })}
                </div>
              </div>
            )}
          </div>
        </aside>
      </div>
    </WindowFrame>
  );
}
