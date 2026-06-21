import { createContext, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";

type ThemeMode = "light" | "dark" | "system";
type AccentKey = "mint" | "cherry" | "sky" | "grape" | "gold";

type ThemeContextValue = {
  accent: AccentKey;
  mode: ThemeMode;
  resolvedTheme: "light" | "dark";
  setAccent: (accent: AccentKey) => void;
  setMode: (mode: ThemeMode) => void;
};

const STORAGE_MODE = "melonbang.theme.mode";
const STORAGE_ACCENT = "melonbang.theme.accent";

const accentPalettes: Record<AccentKey, Record<string, string>> = {
  mint: {
    "--primary": "#43c99f",
    "--primary-foreground": "#08321f",
    "--mint-50": "#eafaf3",
    "--mint-100": "#d2f4e6",
    "--mint-200": "#a7e9cf",
    "--mint-300": "#6fd9b1",
    "--mint-400": "#43c99f",
    "--mint-500": "#22b388",
    "--mint-600": "#129a73"
  },
  cherry: {
    "--primary": "#ff6b81",
    "--primary-foreground": "#ffffff",
    "--mint-50": "#fff0f3",
    "--mint-100": "#ffdce3",
    "--mint-200": "#ffb0bd",
    "--mint-300": "#ff869a",
    "--mint-400": "#ff6b81",
    "--mint-500": "#ef4f69",
    "--mint-600": "#d63a54"
  },
  sky: {
    "--primary": "#6aa6f0",
    "--primary-foreground": "#ffffff",
    "--mint-50": "#eef6ff",
    "--mint-100": "#d9ebff",
    "--mint-200": "#bcdcff",
    "--mint-300": "#8bbcf6",
    "--mint-400": "#6aa6f0",
    "--mint-500": "#4b8adf",
    "--mint-600": "#356fc2"
  },
  grape: {
    "--primary": "#9c87e8",
    "--primary-foreground": "#ffffff",
    "--mint-50": "#f3f0ff",
    "--mint-100": "#e5ddff",
    "--mint-200": "#d3c5ff",
    "--mint-300": "#b6a4f0",
    "--mint-400": "#9c87e8",
    "--mint-500": "#856ed7",
    "--mint-600": "#6f57c4"
  },
  gold: {
    "--primary": "#ffb83d",
    "--primary-foreground": "#4b3200",
    "--mint-50": "#fff8eb",
    "--mint-100": "#fff0d2",
    "--mint-200": "#ffe2a4",
    "--mint-300": "#ffcf6b",
    "--mint-400": "#ffb83d",
    "--mint-500": "#e09c18",
    "--mint-600": "#b97c00"
  }
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [mode, setModeState] = useState<ThemeMode>(
    () => readStorage<ThemeMode>(STORAGE_MODE) ?? "system"
  );
  const [accent, setAccentState] = useState<AccentKey>(
    () => readStorage<AccentKey>(STORAGE_ACCENT) ?? "mint"
  );
  const [resolvedTheme, setResolvedTheme] = useState<"light" | "dark">("light");

  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");

    const applyTheme = (): void => {
      const nextTheme = mode === "system" ? (media.matches ? "dark" : "light") : mode;
      setResolvedTheme(nextTheme);
      document.documentElement.classList.toggle("dark", nextTheme === "dark");
    };

    applyTheme();
    media.addEventListener("change", applyTheme);
    return () => media.removeEventListener("change", applyTheme);
  }, [mode]);

  useEffect(() => {
    const palette = accentPalettes[accent];
    for (const [token, value] of Object.entries(palette)) {
      document.documentElement.style.setProperty(token, value);
    }
  }, [accent]);

  function setMode(nextMode: ThemeMode): void {
    setModeState(nextMode);
    writeStorage(STORAGE_MODE, nextMode);
  }

  function setAccent(nextAccent: AccentKey): void {
    setAccentState(nextAccent);
    writeStorage(STORAGE_ACCENT, nextAccent);
  }

  const value = useMemo<ThemeContextValue>(
    () => ({
      accent,
      mode,
      resolvedTheme,
      setAccent,
      setMode
    }),
    [accent, mode, resolvedTheme]
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const value = useContext(ThemeContext);
  if (!value) {
    throw new Error("ThemeProvider is missing.");
  }
  return value;
}

function readStorage<T extends string>(key: string): T | null {
  try {
    return window.localStorage.getItem(key) as T | null;
  } catch {
    return null;
  }
}

function writeStorage(key: string, value: string): void {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // Ignore storage failures; theme still applies in memory.
  }
}
