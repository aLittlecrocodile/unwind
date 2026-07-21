import { contextBridge, ipcRenderer } from 'electron'
import type { AppData } from '../src/storage/defaultData'

const api = {
  loadAppData: (): Promise<AppData> => ipcRenderer.invoke('app-data:load'),
  saveAppData: (data: AppData): Promise<void> => ipcRenderer.invoke('app-data:save', data),
  setCompactMode: (compact: boolean): Promise<void> => ipcRenderer.invoke('window:set-compact-mode', compact),
  setAlwaysOnTop: (alwaysOnTop: boolean): Promise<void> => ipcRenderer.invoke('window:set-always-on-top', alwaysOnTop),
  notify: (title: string, body: string): Promise<void> => ipcRenderer.invoke('notification:show', title, body),
  openUnwind: (): Promise<void> => ipcRenderer.invoke('unwind:open'),
  unwindChat: (text: string): Promise<unknown> => ipcRenderer.invoke('unwind:chat', text),
  setClickThrough: (ignore: boolean): Promise<void> => ipcRenderer.invoke('window:set-click-through', ignore)
}

contextBridge.exposeInMainWorld('workerBuddy', api)

export type WorkerBuddyApi = typeof api
