import { app, BrowserWindow } from "electron";
import { createMainWindow } from "./app/createMainWindow";
import { registerBangumiIpc } from "./ipc/bangumi";

let mainWindow: BrowserWindow | null = null;

void app.whenReady().then(() => {
  registerBangumiIpc();
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
  return mainWindow;
}
