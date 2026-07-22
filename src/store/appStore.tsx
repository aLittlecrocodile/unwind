/**
 * 全局应用状态。用简单的 React Context + useReducer 实现，不引入额外状态库，
 * 因为 V1 数据量小、状态迁移逻辑集中在 domain 层，reducer 只做编排。
 */

import { createContext, useContext, useEffect, useReducer, useRef } from 'react'
import type { ReactNode, Dispatch } from 'react'
import type { BuddyState } from '../domain/buddyState'
import type { FocusPreset, FocusSession } from '../domain/focusSession'
import {
  createIdleSession,
  endSession,
  getRemainingSeconds,
  isPhaseFinished,
  pauseSession,
  resumeSession,
  startBreak,
  startFocus
} from '../domain/focusSession'
import type { HealthState } from '../domain/health'
import {
  createInitialHealthState,
  isTiredDue,
  isWaterDue,
  recordSatThroughFocusBlock,
  recordStandUp,
  recordWater
} from '../domain/health'
import type { CompletedFocusBlock } from '../domain/stats'
import { computeDailyStats } from '../domain/stats'
import type { Task } from '../domain/tasks'
import { completeTask, createTask, sortTasks } from '../domain/tasks'
import type { AppData } from '../storage/defaultData'
import { createDefaultAppData } from '../storage/defaultData'
import { getElectronApi } from '../lib/electronApi'

interface AppState {
  loaded: boolean
  tasks: Task[]
  focusSession: FocusSession
  health: HealthState
  focusBlocks: CompletedFocusBlock[]
  waterLogs: number[]
  compactMode: boolean
  alwaysOnTop: boolean
  /** 操作后短暂展示的提示状态，几秒后自动消失。 */
  transientState: BuddyState | null
}

type Action =
  | { type: 'hydrate'; data: AppData }
  | { type: 'add-task'; title: string; estimateMinutes: number }
  | { type: 'complete-task'; taskId: string }
  | { type: 'delete-task'; taskId: string }
  | { type: 'select-task'; taskId: string }
  | { type: 'start-focus'; preset: FocusPreset }
  | { type: 'pause-session' }
  | { type: 'resume-session' }
  | { type: 'end-session' }
  | { type: 'focus-phase-finished' }
  | { type: 'break-phase-finished' }
  | { type: 'confirm-stood-up' }
  | { type: 'confirm-drank-water' }
  | { type: 'set-compact-mode'; compact: boolean }
  | { type: 'clear-transient' }

const initialState: AppState = {
  loaded: false,
  tasks: [],
  focusSession: createIdleSession(),
  health: createInitialHealthState(),
  focusBlocks: [],
  waterLogs: [],
  compactMode: false,
  alwaysOnTop: true,
  transientState: null
}

function reducer(state: AppState, action: Action): AppState {
  switch (action.type) {
    case 'hydrate':
      return {
        ...state,
        loaded: true,
        tasks: action.data.tasks,
        focusSession: action.data.focusSession,
        health: action.data.health,
        focusBlocks: action.data.focusBlocks,
        waterLogs: action.data.waterLogs,
        compactMode: action.data.settings.compactMode,
        alwaysOnTop: action.data.settings.alwaysOnTop
      }

    case 'add-task': {
      const task = createTask(action.title, action.estimateMinutes)
      const shouldSelectTask = state.focusSession.phase === 'idle'
      return {
        ...state,
        tasks: [...state.tasks, task],
        focusSession: shouldSelectTask ? { ...state.focusSession, taskId: task.id, preset: task.estimateMinutes as FocusPreset } : state.focusSession
      }
    }

    case 'complete-task': {
      const tasks = state.tasks.map((t) => (t.id === action.taskId ? completeTask(t) : t))
      const isCurrentTask = state.focusSession.taskId === action.taskId
      return {
        ...state,
        tasks,
        transientState: 'done',
        focusSession: isCurrentTask ? { ...state.focusSession, taskId: null } : state.focusSession
      }
    }

    case 'delete-task':
      return {
        ...state,
        tasks: state.tasks.filter((t) => t.id !== action.taskId),
        focusSession: state.focusSession.taskId === action.taskId ? { ...state.focusSession, taskId: null } : state.focusSession
      }

    case 'select-task': {
      const task = state.tasks.find((t) => t.id === action.taskId && !t.done)
      if (!task) return state
      return { ...state, focusSession: { ...state.focusSession, taskId: task.id, preset: task.estimateMinutes as FocusPreset } }
    }

    case 'start-focus':
      return { ...state, focusSession: startFocus(state.focusSession, action.preset, state.focusSession.taskId) }

    case 'pause-session':
      return { ...state, focusSession: pauseSession(state.focusSession) }

    case 'resume-session':
      return { ...state, focusSession: resumeSession(state.focusSession) }

    case 'end-session':
      return { ...state, focusSession: endSession() }

    case 'focus-phase-finished': {
      const block: CompletedFocusBlock = { completedAt: Date.now(), preset: state.focusSession.preset }
      // 起身打卡有效期覆盖"刚结束的这个专注段"，而不是"最近 1 毫秒"——
      // 后者几乎不可能为真，导致哪怕这一段里刚起身过，久坐计数照样 +1。
      const blockStartedAt = Date.now() - state.focusSession.phaseDurationSeconds * 1000
      const health = state.health.lastStandAt !== null && state.health.lastStandAt >= blockStartedAt
        ? state.health
        : recordSatThroughFocusBlock(state.health)
      return {
        ...state,
        focusBlocks: [...state.focusBlocks, block],
        health,
        focusSession: startBreak(state.focusSession),
        transientState: 'done'
      }
    }

    case 'break-phase-finished':
      return { ...state, focusSession: endSession() }

    case 'confirm-stood-up':
      return { ...state, health: recordStandUp(state.health), transientState: 'stood' }

    case 'confirm-drank-water':
      return {
        ...state,
        health: recordWater(state.health),
        waterLogs: [...state.waterLogs, Date.now()],
        transientState: 'hydrated'
      }

    case 'set-compact-mode':
      return { ...state, compactMode: action.compact }

    case 'clear-transient':
      return { ...state, transientState: null }

    default:
      return state
  }
}

interface AppContextValue {
  state: AppState
  dispatch: Dispatch<Action>
  buddyState: BuddyState
  remainingSeconds: number
  dailyStats: ReturnType<typeof computeDailyStats>
  sortedTasks: Task[]
  currentTask: Task | null
}

const AppContext = createContext<AppContextValue | null>(null)

function deriveBuddyState(state: AppState): BuddyState {
  if (state.transientState) return state.transientState
  if (isWaterDue(state.health)) return 'water'
  if (isTiredDue(state.health)) return 'tired'
  if (state.focusSession.phase === 'focus') return 'focus'
  if (state.focusSession.phase === 'break') return 'rest'
  if (state.focusSession.phase === 'paused') return 'idle'
  return 'idle'
}

export function AppStoreProvider({ children }: { children: ReactNode }): React.JSX.Element {
  const [state, dispatch] = useReducer(reducer, initialState)
  const [, refreshTimerDisplay] = useReducer((value: number) => value + 1, 0)
  const api = useRef(getElectronApi())

  // 启动时从本地加载数据
  useEffect(() => {
    if (!api.current) {
      dispatch({ type: 'hydrate', data: createDefaultAppData() })
      return
    }

    api.current
      .loadAppData()
      .then((data) => dispatch({ type: 'hydrate', data }))
      .catch(() => dispatch({ type: 'hydrate', data: createDefaultAppData() }))
  }, [])

  // 状态变化后持久化（跳过初次加载前的写入）
  useEffect(() => {
    if (!state.loaded) return
    const data: AppData = {
      version: 1,
      tasks: state.tasks,
      focusSession: state.focusSession,
      health: state.health,
      focusBlocks: state.focusBlocks,
      waterLogs: state.waterLogs,
      settings: { compactMode: state.compactMode, alwaysOnTop: state.alwaysOnTop }
    }
    api.current?.saveAppData(data)
  }, [state])

  // 计时驱动：每秒刷新倒计时显示，并在阶段结束时切换状态。
  useEffect(() => {
    if (state.focusSession.phase !== 'focus' && state.focusSession.phase !== 'break') return

    const timer = setInterval(() => {
      if (state.focusSession.phase === 'focus' && isPhaseFinished(state.focusSession)) {
        dispatch({ type: 'focus-phase-finished' })
      } else if (state.focusSession.phase === 'break' && isPhaseFinished(state.focusSession)) {
        dispatch({ type: 'break-phase-finished' })
      } else {
        refreshTimerDisplay()
      }
    }, 1000)
    return () => clearInterval(timer)
  }, [state.focusSession])

  // transient 状态（done）几秒后自动消失
  useEffect(() => {
    if (!state.transientState) return
    const timer = setTimeout(() => dispatch({ type: 'clear-transient' }), 8000)
    return () => clearTimeout(timer)
  }, [state.transientState])

  const buddyState = deriveBuddyState(state)
  const remainingSeconds = getRemainingSeconds(state.focusSession)
  const dailyStats = computeDailyStats(
    Date.now(),
    state.focusBlocks,
    state.tasks.filter((t) => t.completedAt !== null).map((t) => t.completedAt as number),
    state.waterLogs
  )
  const sortedTasks = sortTasks(state.tasks)
  const currentTask = state.tasks.find((t) => t.id === state.focusSession.taskId) ?? null

  const value: AppContextValue = { state, dispatch, buddyState, remainingSeconds, dailyStats, sortedTasks, currentTask }

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>
}

export function useAppStore(): AppContextValue {
  const ctx = useContext(AppContext)
  if (!ctx) throw new Error('useAppStore must be used within AppStoreProvider')
  return ctx
}
