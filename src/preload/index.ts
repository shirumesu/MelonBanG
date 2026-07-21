import { contextBridge, ipcRenderer } from "electron";
import type { BangumiBridge } from "../shared/contracts/bangumi";
import type { DownloadBridge } from "../shared/contracts/download";
import type { PlaybackBridge } from "../shared/contracts/playback";
import type { SourceBridge } from "../shared/contracts/source";
import type { WindowControlsBridge } from "../shared/contracts/window";
import type { MelonbangBridge } from "../shared/contracts/bridge";

const bangumi: BangumiBridge = {
  getSession: () => ipcRenderer.invoke("bangumi:getSession"),
  signIn: () => ipcRenderer.invoke("bangumi:signIn"),
  cancelSignIn: () => ipcRenderer.invoke("bangumi:cancelSignIn"),
  signOut: () => ipcRenderer.invoke("bangumi:signOut"),
  listCollection: (filter) => ipcRenderer.invoke("bangumi:listCollection", filter),
  getCachedSubject: (subjectId) => ipcRenderer.invoke("bangumi:getCachedSubject", subjectId),
  getSubject: (subjectId) => ipcRenderer.invoke("bangumi:getSubject", subjectId),
  searchSubjects: (keyword) => ipcRenderer.invoke("bangumi:searchSubjects", keyword),
  getCachedTrendingCurrent: () => ipcRenderer.invoke("bangumi:getCachedTrendingCurrent"),
  getTrendingCurrent: () => ipcRenderer.invoke("bangumi:getTrendingCurrent"),
  getCachedTodaySchedule: () => ipcRenderer.invoke("bangumi:getCachedTodaySchedule"),
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

const download: DownloadBridge = {
  create: (input) => ipcRenderer.invoke("download:create", input),
  list: () => ipcRenderer.invoke("download:list"),
  pause: (downloadId) => ipcRenderer.invoke("download:pause", downloadId),
  resume: (downloadId) => ipcRenderer.invoke("download:resume", downloadId),
  remove: (downloadId) => ipcRenderer.invoke("download:remove", downloadId),
  onUpdate: (callback) => {
    const listener = (_event: unknown, snapshot: Parameters<typeof callback>[0]): void =>
      callback(snapshot);
    ipcRenderer.on("download:update", listener);
    return () => ipcRenderer.removeListener("download:update", listener);
  }
};

const playback: PlaybackBridge = {
  startFromDownload: (input) => ipcRenderer.invoke("playback:startFromDownload", input),
  startEpisode: (input) => ipcRenderer.invoke("playback:startEpisode", input),
  getEpisodeProgress: (input) => ipcRenderer.invoke("playback:getEpisodeProgress", input),
  getSession: () => ipcRenderer.invoke("playback:getSession"),
  loadDanmaku: (sessionId) => ipcRenderer.invoke("playback:loadDanmaku", sessionId),
  searchDanmakuEpisodes: (input) => ipcRenderer.invoke("playback:searchDanmakuEpisodes", input),
  selectDanmakuEpisode: (input) => ipcRenderer.invoke("playback:selectDanmakuEpisode", input),
  loadDanmakuSource: (input) => ipcRenderer.invoke("playback:loadDanmakuSource", input),
  setDanmakuSourceEnabled: (input) => ipcRenderer.invoke("playback:setDanmakuSourceEnabled", input),
  seek: (input) => ipcRenderer.invoke("playback:seek", input),
  updateProgress: (input) => ipcRenderer.invoke("playback:updateProgress", input),
  stop: (sessionId) => ipcRenderer.invoke("playback:stop", sessionId),
  onEvent: (callback) => {
    const listener = (_event: unknown, session: Parameters<typeof callback>[0]): void =>
      callback(session);
    ipcRenderer.on("playback:update", listener);
    return () => ipcRenderer.removeListener("playback:update", listener);
  }
};

const source: SourceBridge = {
  search: (input) => ipcRenderer.invoke("source:search", input),
  enqueue: (input) => ipcRenderer.invoke("source:enqueue", input)
};

const api: MelonbangBridge = { bangumi, download, playback, source, windowControls };

contextBridge.exposeInMainWorld("melonbang", api);
