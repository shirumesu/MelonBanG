import { contextBridge, ipcRenderer } from "electron";
import type { BangumiBridge } from "../shared/contracts/bangumi";
import type { WindowControlsBridge } from "../shared/contracts/window";
import type { MelonbangBridge } from "../shared/contracts/bridge";

const bangumi: BangumiBridge = {
  getSession: () => ipcRenderer.invoke("bangumi:getSession"),
  signIn: () => ipcRenderer.invoke("bangumi:signIn"),
  signOut: () => ipcRenderer.invoke("bangumi:signOut"),
  listCollection: (filter) => ipcRenderer.invoke("bangumi:listCollection", filter),
  getCachedSubject: (subjectId) => ipcRenderer.invoke("bangumi:getCachedSubject", subjectId),
  getSubject: (subjectId) => ipcRenderer.invoke("bangumi:getSubject", subjectId),
  searchSubjects: (keyword) => ipcRenderer.invoke("bangumi:searchSubjects", keyword),
  getTrendingCurrent: () => ipcRenderer.invoke("bangumi:getTrendingCurrent"),
  getTodaySchedule: () => ipcRenderer.invoke("bangumi:getTodaySchedule"),
  getCalendar: () => ipcRenderer.invoke("bangumi:getCalendar"),
  updateTracking: (input) => ipcRenderer.invoke("bangumi:updateTracking", input),
  refreshCollection: (force) => ipcRenderer.invoke("bangumi:refreshCollection", force),
  getSyncState: () => ipcRenderer.invoke("bangumi:getSyncState")
};

const windowControls: WindowControlsBridge = {
  minimize: () => ipcRenderer.send("window:minimize"),
  toggleMaximize: () => ipcRenderer.send("window:toggleMaximize"),
  close: () => ipcRenderer.send("window:close"),
  isMaximized: () => ipcRenderer.invoke("window:isMaximized"),
  onMaximizeChange: (callback) => {
    const listener = (_event: unknown, maximized: boolean): void => callback(maximized);
    ipcRenderer.on("window:maximizeChanged", listener);
    return () => ipcRenderer.removeListener("window:maximizeChanged", listener);
  }
};

const api: MelonbangBridge = { bangumi, windowControls };

contextBridge.exposeInMainWorld("melonbang", api);
