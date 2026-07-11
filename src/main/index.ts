import { app, BrowserWindow } from "electron";
import { createMainWindow } from "./app/createMainWindow";
import { registerBangumiIpc } from "./ipc/bangumi";
import { registerDownloadIpc } from "./ipc/download";
import { registerPlaybackIpc } from "./ipc/playback";
import { registerSourceIpc } from "./ipc/sources";
import { bindWindowMaximizeEvents, registerWindowIpc } from "./ipc/window";

let mainWindow: BrowserWindow | null = null;

if (process.env.MELONBANG_MUTE_AUDIO === "1") {
  app.commandLine.appendSwitch("mute-audio");
}

void app.whenReady().then(() => {
  registerBangumiIpc();
  registerDownloadIpc();
  registerPlaybackIpc(() => mainWindow);
  registerSourceIpc();
  registerWindowIpc();
  createAndStoreMainWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createAndStoreMainWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

function createAndStoreMainWindow(): BrowserWindow {
  mainWindow = createMainWindow();
  bindWindowMaximizeEvents(mainWindow);
  return mainWindow;
}
