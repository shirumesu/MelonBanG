import { app, BrowserWindow } from "electron";
import { createMainWindow } from "./app/createMainWindow";
import { registerBangumiIpc } from "./ipc/bangumi";
import { bindWindowMaximizeEvents, registerWindowIpc } from "./ipc/window";

let mainWindow: BrowserWindow | null = null;

void app.whenReady().then(() => {
  registerBangumiIpc();
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
