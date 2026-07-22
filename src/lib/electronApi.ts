import type { AppData } from '../storage/defaultData'

export interface WorkerBuddyApi {
  loadAppData(): Promise<AppData>
  saveAppData(data: AppData): Promise<void>
  setCompactMode(compact: boolean): Promise<void>
  setAlwaysOnTop(alwaysOnTop: boolean): Promise<void>
  notify(title: string, body: string): Promise<void>
  openUnwind(): Promise<void>
  unwindChat(text: string): Promise<UnwindReply>
  setClickThrough(ignore: boolean): Promise<void>
  hidePet(ms: number): Promise<void>
  getPetPosition(): Promise<[number, number]>
  movePetTo(x: number, y: number): Promise<void>
}

export interface UnwindReply {
  reply: string | null
  reply_audio_url: string | null
  selected_skill: string | null
  asset: { title?: string; playback_url?: string | null } | null
  skill_card: Record<string, unknown> | null
  timer_sec: number | null
}

export function getElectronApi(): WorkerBuddyApi | null {
  return window.workerBuddy ?? null
}
