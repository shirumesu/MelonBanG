import { BrowserWindow, ipcMain } from "electron";

export function registerWindowIpc(): void {
  ipcMain.on("window:minimize", (event) => {
    BrowserWindow.fromWebContents(event.sender)?.minimize();
  });

  ipcMain.on("window:toggleMaximize", (event) => {
    const window = BrowserWindow.fromWebContents(event.sender);
    if (!window) {
      return;
    }
    if (window.isMaximized()) {
      window.unmaximize();
    } else {
      window.maximize();
    }
  });

  ipcMain.on("window:close", (event) => {
    BrowserWindow.fromWebContents(event.sender)?.close();
  });

  ipcMain.handle(
    "window:isMaximized",
    (event) => BrowserWindow.fromWebContents(event.sender)?.isMaximized() ?? false
  );
}

/**
 * Forward native maximize/unmaximize events to the renderer so the custom
 * titlebar can swap its maximize/restore icon.
 */
export function bindWindowMaximizeEvents(window: BrowserWindow): void {
  const emit = (): void => {
    if (!window.isDestroyed()) {
      window.webContents.send("window:maximizeChanged", window.isMaximized());
    }
  };
  window.on("maximize", emit);
  window.on("unmaximize", emit);
}
