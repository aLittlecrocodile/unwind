import type { FocusSession } from '../domain/focusSession'
import { createIdleSession } from '../domain/focusSession'
import type { HealthState } from '../domain/health'
import { createInitialHealthState } from '../domain/health'
import type { CompletedFocusBlock } from '../domain/stats'
import type { Task } from '../domain/tasks'

export interface AppSettings {
  compactMode: boolean
  alwaysOnTop: boolean
}

export interface AppData {
  version: 1
  tasks: Task[]
  focusSession: FocusSession
  health: HealthState
  focusBlocks: CompletedFocusBlock[]
  waterLogs: number[]
  settings: AppSettings
}

export function createDefaultAppData(): AppData {
  return {
    version: 1,
    tasks: [],
    focusSession: createIdleSession(),
    health: createInitialHealthState(),
    focusBlocks: [],
    waterLogs: [],
    settings: {
      compactMode: false,
      alwaysOnTop: true
    }
  }
}
