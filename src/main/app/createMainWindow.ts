import { BrowserWindow, shell } from "electron";
import { existsSync } from "node:fs";
import { join } from "node:path";

const isDev = Boolean(process.env.ELECTRON_RENDERER_URL);

export function createMainWindow(): BrowserWindow {
  const preloadPath = resolvePreloadPath();
  if (!existsSync(preloadPath)) {
    throw new Error(`Preload bundle is missing: ${preloadPath}`);
  }

  const window = new BrowserWindow({
    width: 1500,
    height: 960,
    minWidth: 1200,
    minHeight: 820,
    titleBarStyle: "hidden",
    backgroundColor: "#0F1722",
    show: false,
    autoHideMenuBar: true,
    webPreferences: {
      preload: preloadPath,
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      devTools: isDev
    }
  });

  window.webContents.setWindowOpenHandler(({ url }) => {
    if (isSafeExternalUrl(url)) {
      void shell.openExternal(url);
    }
    return { action: "deny" };
  });

  window.webContents.on("will-navigate", (event, url) => {
    if (url !== window.webContents.getURL()) {
      event.preventDefault();
    }
  });

  window.once("ready-to-show", () => {
    window.show();
  });

  if (isDev && process.env.ELECTRON_RENDERER_URL) {
    void window.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    void window.loadFile(join(import.meta.dirname, "../renderer/index.html"));
  }

  return window;
}

function isSafeExternalUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" || parsed.protocol === "mailto:";
  } catch {
    return false;
  }
}

function resolvePreloadPath(): string {
  const candidates = ["../preload/index.mjs", "../preload/index.js"];

  for (const candidate of candidates) {
    const resolved = join(import.meta.dirname, candidate);
    if (existsSync(resolved)) {
      return resolved;
    }
  }

  return join(import.meta.dirname, candidates[0]);
}
