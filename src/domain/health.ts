/**
 * 久坐 / 喝水提醒的判定逻辑。纯函数，输入健康记录和当前时间，输出是否该提醒。
 */

export interface HealthState {
  lastWaterAt: number | null
  waterCount: number
  /** 最近一次确认"我起来了"的时间；null 表示还没起过。 */
  lastStandAt: number | null
  /** 连续未起身跨过的专注段数量，起身后清零。 */
  consecutiveSitFocusBlocks: number
}

export const WATER_INTERVAL_MS = 60 * 60 * 1000 // 60 分钟提醒一次喝水
export const SIT_BLOCKS_BEFORE_TIRED = 2 // 连续 2 个专注段没起身就进入疲惫状态

export function createInitialHealthState(): HealthState {
  return {
    lastWaterAt: null,
    waterCount: 0,
    lastStandAt: null,
    consecutiveSitFocusBlocks: 0
  }
}

export function isWaterDue(health: HealthState, now: number = Date.now()): boolean {
  if (health.lastWaterAt === null) return true
  return now - health.lastWaterAt >= WATER_INTERVAL_MS
}

export function isTiredDue(health: HealthState): boolean {
  return health.consecutiveSitFocusBlocks >= SIT_BLOCKS_BEFORE_TIRED
}

export function recordWater(health: HealthState, now: number = Date.now()): HealthState {
  return { ...health, lastWaterAt: now, waterCount: health.waterCount + 1 }
}

export function recordStandUp(health: HealthState, now: number = Date.now()): HealthState {
  return { ...health, lastStandAt: now, consecutiveSitFocusBlocks: 0 }
}

/** 一个专注段结束但用户没有确认起身时调用。 */
export function recordSatThroughFocusBlock(health: HealthState): HealthState {
  return { ...health, consecutiveSitFocusBlocks: health.consecutiveSitFocusBlocks + 1 }
}
