import { useEffect, useRef, useState } from "react";
import { Check, ChevronDown, ListFilter, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import {
  countActiveSourceFilters,
  emptySourceCandidateFilters,
  sourceSubtitleLanguageLabels,
  type SourceCandidateFilters,
  type SourceFilterOptions,
  type SourceSubtitleLanguage
} from "./sourceCandidateMetadata";

type SourceResultFilterBarProps = {
  filters: SourceCandidateFilters;
  options: SourceFilterOptions;
  includeUnknown: boolean;
  filteredCount: number;
  totalCount: number;
  onFiltersChange: (filters: SourceCandidateFilters) => void;
  onIncludeUnknownChange: (includeUnknown: boolean) => void;
};

export function SourceResultFilterBar({
  filters,
  options,
  includeUnknown,
  filteredCount,
  totalCount,
  onFiltersChange,
  onIncludeUnknownChange
}: SourceResultFilterBarProps) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const activeFilterCount = countActiveSourceFilters(filters);

  useEffect(() => {
    if (!open) return;
    const handlePointerDown = (event: MouseEvent): void => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const handleKeyDown = (event: KeyboardEvent): void => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("mousedown", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [open]);

  const update = <Key extends keyof SourceCandidateFilters>(
    key: Key,
    value: SourceCandidateFilters[Key]
  ): void => onFiltersChange({ ...filters, [key]: value });

  return (
    <div
      data-testid="source-filter-bar"
      className="border-line bg-surface relative z-20 mt-4 flex min-h-12 items-center justify-between gap-3 rounded-[16px] border px-3.5 py-2 shadow-[var(--shadow-xs)]"
    >
      <div className="flex min-w-0 items-center gap-3">
        <div ref={rootRef} className="relative shrink-0">
          <Button
            type="button"
            variant="outline"
            size="sm"
            aria-expanded={open}
            aria-controls="source-result-filter-panel"
            onClick={() => setOpen((current) => !current)}
          >
            <ListFilter className="size-3.5" />
            筛选
            {activeFilterCount > 0 ? (
              <span className="bg-mint-500 grid size-4 place-items-center rounded-full text-[10px] text-white">
                {activeFilterCount}
              </span>
            ) : null}
            <ChevronDown className={cn("size-3.5 transition", open && "rotate-180")} />
          </Button>

          {open ? (
            <div
              id="source-result-filter-panel"
              className="border-line bg-surface absolute top-[calc(100%+9px)] left-0 z-40 w-[min(560px,calc(100vw-48px))] rounded-[18px] border p-4 shadow-[var(--shadow-lg)]"
            >
              <div className="mb-3 flex items-center justify-between gap-3">
                <div>
                  <div className="text-sm font-extrabold">筛选资源属性</div>
                  <div className="text-ink-faint mt-0.5 text-[11.5px] font-semibold">
                    选择后立即更新当前结果
                  </div>
                </div>
                {activeFilterCount > 0 ? (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => onFiltersChange(emptySourceCandidateFilters)}
                  >
                    <RotateCcw className="size-3.5" />
                    重置
                  </Button>
                ) : null}
              </div>

              <div className="grid grid-cols-2 gap-3 max-sm:grid-cols-1">
                <FilterSelect
                  label="搜索源"
                  value={filters.providerId ?? ""}
                  allLabel="全部搜索源"
                  disabled={options.providers.length === 0}
                  onChange={(value) => update("providerId", value || null)}
                >
                  {options.providers.map((provider) => (
                    <option key={provider.value} value={provider.value}>
                      {provider.label}
                    </option>
                  ))}
                </FilterSelect>

                <FilterSelect
                  label="剧集"
                  value={filters.episode?.toString() ?? ""}
                  allLabel="全部剧集"
                  disabled={options.episodes.length === 0}
                  onChange={(value) => update("episode", value ? Number(value) : null)}
                >
                  {options.episodes.map((episode) => (
                    <option key={episode} value={episode}>
                      EP{episode}
                    </option>
                  ))}
                </FilterSelect>

                <FilterSelect
                  label="字幕组"
                  value={filters.releaseGroup ?? ""}
                  allLabel="全部字幕组"
                  disabled={options.releaseGroups.length === 0}
                  className="col-span-2 max-sm:col-span-1"
                  onChange={(value) => update("releaseGroup", value || null)}
                >
                  {options.releaseGroups.map((group) => (
                    <option key={group} value={group}>
                      {group}
                    </option>
                  ))}
                </FilterSelect>

                <FilterSelect
                  label="字幕"
                  value={filters.subtitleLanguage ?? ""}
                  allLabel="全部字幕"
                  disabled={options.subtitleLanguages.length === 0}
                  onChange={(value) =>
                    update("subtitleLanguage", (value || null) as SourceSubtitleLanguage | null)
                  }
                >
                  {options.subtitleLanguages.map((language) => (
                    <option key={language} value={language}>
                      {sourceSubtitleLanguageLabels[language]}
                    </option>
                  ))}
                </FilterSelect>

                <FilterSelect
                  label="清晰度"
                  value={filters.resolution ?? ""}
                  allLabel="全部清晰度"
                  disabled={options.resolutions.length === 0}
                  onChange={(value) => update("resolution", value || null)}
                >
                  {options.resolutions.map((resolution) => (
                    <option key={resolution} value={resolution}>
                      {resolution}
                    </option>
                  ))}
                </FilterSelect>
              </div>
            </div>
          ) : null}
        </div>

        <span className="text-ink-faint truncate text-[12px] font-semibold">
          显示 {filteredCount} / {totalCount} 条
        </span>
      </div>

      <label className="text-ink-soft flex shrink-0 cursor-pointer items-center gap-2 text-[12px] font-bold select-none">
        <span className="relative grid size-4 place-items-center">
          <input
            type="checkbox"
            checked={includeUnknown}
            onChange={(event) => onIncludeUnknownChange(event.target.checked)}
            className="peer border-line-strong checked:border-mint-500 checked:bg-mint-500 size-4 appearance-none rounded-[5px] border bg-white transition"
          />
          <Check className="pointer-events-none absolute size-3 text-white opacity-0 peer-checked:opacity-100" />
        </span>
        包含未知
      </label>
    </div>
  );
}

type FilterSelectProps = {
  label: string;
  value: string;
  allLabel: string;
  disabled: boolean;
  className?: string;
  onChange: (value: string) => void;
  children: React.ReactNode;
};

function FilterSelect({
  label,
  value,
  allLabel,
  disabled,
  className,
  onChange,
  children
}: FilterSelectProps) {
  return (
    <label className={cn("grid gap-1.5", className)}>
      <span className="text-ink-soft text-[11.5px] font-extrabold">{label}</span>
      <div className="relative">
        <select
          aria-label={label}
          value={value}
          disabled={disabled}
          onChange={(event) => onChange(event.target.value)}
          className="border-line bg-surface-2 text-ink focus:border-mint-400 h-10 w-full appearance-none rounded-[12px] border px-3 pr-9 text-[12.5px] font-bold transition outline-none disabled:opacity-50"
        >
          <option value="">{allLabel}</option>
          {children}
        </select>
        <ChevronDown className="text-ink-faint pointer-events-none absolute top-1/2 right-3 size-3.5 -translate-y-1/2" />
      </div>
    </label>
  );
}
