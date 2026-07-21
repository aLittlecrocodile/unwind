/**
 * 番茄钟会话状态机。V1 支持三档时长：25 / 50 / 90 分钟专注，休息时长随专注时长走。
 * 计时用时间戳而不是纯递减计数器，避免系统睡眠/唤醒导致计时误差。
 */

export type FocusPreset = 25 | 50 | 90

export type SessionPhase = 'idle' | 'focus' | 'break' | 'paused'

export interface FocusSession {
  phase: SessionPhase
  preset: FocusPreset
  taskId: string | null
  /** 本阶段（专注或休息）应该持续的总秒数。 */
  phaseDurationSeconds: number
  /** 本阶段的到期时间戳（毫秒）；phase 为 paused 时无意义。 */
  phaseEndsAt: number | null
  /** 暂停时刻剩余的秒数，用于恢复计时。 */
  pausedRemainingSeconds: number | null
  /** 暂停前所在的阶段（focus 或 break），恢复时用它决定回到哪个阶段。 */
  pausedFromPhase: 'focus' | 'break' | null
}

const BREAK_MINUTES: Record<FocusPreset, number> = {
  25: 5,
  50: 10,
  90: 15
}

export function createIdleSession(): FocusSession {
  return {
    phase: 'idle',
    preset: 25,
    taskId: null,
    phaseDurationSeconds: 0,
    phaseEndsAt: null,
    pausedRemainingSeconds: null,
    pausedFromPhase: null
  }
}

export function startFocus(session: FocusSession, preset: FocusPreset, taskId: string | null): FocusSession {
  const durationSeconds = preset * 60
  return {
    ...session,
    phase: 'focus',
    preset,
    taskId,
    phaseDurationSeconds: durationSeconds,
    phaseEndsAt: Date.now() + durationSeconds * 1000,
    pausedRemainingSeconds: null,
    pausedFromPhase: null
  }
}

export function startBreak(session: FocusSession): FocusSession {
  const durationSeconds = BREAK_MINUTES[session.preset] * 60
  return {
    ...session,
    phase: 'break',
    phaseDurationSeconds: durationSeconds,
    phaseEndsAt: Date.now() + durationSeconds * 1000,
    pausedRemainingSeconds: null,
    pausedFromPhase: null
  }
}

export function pauseSession(session: FocusSession): FocusSession {
  if (session.phase !== 'focus' && session.phase !== 'break') return session
  return {
    ...session,
    phase: 'paused',
    pausedRemainingSeconds: getRemainingSeconds(session),
    pausedFromPhase: session.phase
  }
}

export function resumeSession(session: FocusSession): FocusSession {
  if (session.phase !== 'paused' || session.pausedRemainingSeconds === null || session.pausedFromPhase === null) {
    return session
  }
  const remaining = session.pausedRemainingSeconds
  return {
    ...session,
    phase: session.pausedFromPhase,
    phaseEndsAt: Date.now() + remaining * 1000,
    pausedRemainingSeconds: null,
    pausedFromPhase: null
  }
}

export function endSession(): FocusSession {
  return createIdleSession()
}

/** 返回当前阶段剩余秒数，不会小于 0。 */
export function getRemainingSeconds(session: FocusSession): number {
  if (session.phase === 'paused') return session.pausedRemainingSeconds ?? 0
  if (session.phaseEndsAt === null) return 0
  return Math.max(0, Math.round((session.phaseEndsAt - Date.now()) / 1000))
}

export function isPhaseFinished(session: FocusSession): boolean {
  return (session.phase === 'focus' || session.phase === 'break') && getRemainingSeconds(session) <= 0
}
