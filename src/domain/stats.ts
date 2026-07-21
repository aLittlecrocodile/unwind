/**
 * 今日统计的纯计算逻辑。统计范围按自然日（本地时区）划分。
 */

import type { FocusPreset } from './focusSession'

export interface CompletedFocusBlock {
  completedAt: number
  preset: FocusPreset
}

export interface DailyStats {
  pomodoroCount: number
  focusMinutes: number
  tasksCompleted: number
  waterCount: number
}

export function isSameLocalDay(a: number, b: number): boolean {
  const da = new Date(a)
  const db = new Date(b)
  return da.getFullYear() === db.getFullYear() && da.getMonth() === db.getMonth() && da.getDate() === db.getDate()
}

export function computeDailyStats(
  now: number,
  focusBlocks: CompletedFocusBlock[],
  tasksCompletedAt: number[],
  waterTimestamps: number[]
): DailyStats {
  const todayFocusBlocks = focusBlocks.filter((b) => isSameLocalDay(b.completedAt, now))
  const focusMinutes = todayFocusBlocks.reduce((sum, b) => sum + b.preset, 0)
  const tasksCompleted = tasksCompletedAt.filter((t) => isSameLocalDay(t, now)).length
  const waterCount = waterTimestamps.filter((w) => isSameLocalDay(w, now)).length

  return {
    pomodoroCount: todayFocusBlocks.length,
    focusMinutes,
    tasksCompleted,
    waterCount
  }
}
