import { contextBridge, ipcRenderer } from "electron";
import type { BangumiBridge } from "../shared/contracts/bangumi";

const bangumi: BangumiBridge = {
  getSession: () => ipcRenderer.invoke("bangumi:getSession"),
  signIn: () => ipcRenderer.invoke("bangumi:signIn"),
  signOut: () => ipcRenderer.invoke("bangumi:signOut"),
  listCollection: (filter) => ipcRenderer.invoke("bangumi:listCollection", filter),
  getSubject: (subjectId) => ipcRenderer.invoke("bangumi:getSubject", subjectId),
  searchSubjects: (keyword) => ipcRenderer.invoke("bangumi:searchSubjects", keyword),
  updateTracking: (input) => ipcRenderer.invoke("bangumi:updateTracking", input),
  refreshCollection: (force) => ipcRenderer.invoke("bangumi:refreshCollection", force),
  getSyncState: () => ipcRenderer.invoke("bangumi:getSyncState")
};

contextBridge.exposeInMainWorld("melonbang", {
  bangumi
});
