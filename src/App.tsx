import { useEffect } from 'react'
import { HealthActions } from './components/HealthActions'
import { PetMode } from './components/PetMode'
import { TimerControls } from './components/TimerControls'
import { TodayStats } from './components/TodayStats'
import { TodoList } from './components/TodoList'
import { WorkerBuddy } from './components/WorkerBuddy'
import { isTiredDue, isWaterDue } from './domain/health'
import { getElectronApi } from './lib/electronApi'
import { AppStoreProvider, useAppStore } from './store/appStore'
import './styles/global.css'

function AppContent(): React.JSX.Element {
  const { state, dispatch, buddyState, remainingSeconds, dailyStats, sortedTasks, currentTask } = useAppStore()
  const api = getElectronApi()

  useEffect(() => {
    api?.setCompactMode(state.compactMode)
  }, [api, state.compactMode])

  useEffect(() => {
    api?.setAlwaysOnTop(state.alwaysOnTop)
  }, [api, state.alwaysOnTop])

  useEffect(() => {
    if (!state.loaded) return
    if (state.focusSession.phase === 'break') {
      api?.notify('该休息了', '打工小人喊 Unwind 来陪你喘口气。')
      api?.openUnwind()
    }
  }, [api, state.focusSession.phase, state.loaded])

  useEffect(() => {
    if (!state.loaded) return
    if (isTiredDue(state.health)) {
      api?.notify('久坐提醒', '已经连续坐了很久，点一下“我起来了”让小人回血。')
    }
  }, [api, state.health.consecutiveSitFocusBlocks, state.loaded])

  if (!state.loaded) {
    return <div className="loading-shell">打工小人正在开机…</div>
  }

  const waterDue = isWaterDue(state.health)
  const tiredDue = isTiredDue(state.health)
  const phase = state.focusSession.phase
  const bubbleOverride = currentTask && phase === 'focus' ? `${currentTask.title} · ${Math.ceil(remainingSeconds / 60)}m` : undefined

  if (state.compactMode) {
    const statusLine = phase === 'focus'
      ? `专注中 · ${currentTask?.title ?? '未命名任务'} · ${Math.ceil(remainingSeconds / 60)}m`
      : phase === 'break'
        ? '休息中 · 喘口气吧'
        : '待命中 · 点我聊聊'
    return (
      <PetMode
        buddyState={buddyState}
        statusLine={statusLine}
        onExpand={() => dispatch({ type: 'set-compact-mode', compact: false })}
      />
    )
  }

  return (
    <main className="app-shell">
      <div className="drag-region" />
      <header className="app-header">
        <div>
          <h1>打工小人</h1>
          <p>陪你分段工作，顺手照顾自己。</p>
        </div>
        <div className="header-actions">
          <button type="button" onClick={() => api?.openUnwind()}>喘口气</button>
          <button type="button" onClick={() => dispatch({ type: 'set-compact-mode', compact: true })}>迷你</button>
        </div>
      </header>

      <WorkerBuddy state={buddyState} bubbleOverride={bubbleOverride} />

      {(waterDue || tiredDue || phase === 'break') && (
        <HealthActions
          onDrinkWater={() => dispatch({ type: 'confirm-drank-water' })}
          onStandUp={() => dispatch({ type: 'confirm-stood-up' })}
        />
      )}

      <TimerControls
        phase={phase}
        preset={state.focusSession.preset}
        remainingSeconds={remainingSeconds}
        currentTaskTitle={currentTask?.title ?? null}
        onStart={(preset) => dispatch({ type: 'start-focus', preset })}
        onPause={() => dispatch({ type: 'pause-session' })}
        onResume={() => dispatch({ type: 'resume-session' })}
        onEnd={() => dispatch({ type: 'end-session' })}
      />

      <TodoList
        tasks={sortedTasks}
        currentTaskId={state.focusSession.taskId}
        onAdd={(title, estimateMinutes) => dispatch({ type: 'add-task', title, estimateMinutes })}
        onSelect={(taskId) => dispatch({ type: 'select-task', taskId })}
        onComplete={(taskId) => dispatch({ type: 'complete-task', taskId })}
        onDelete={(taskId) => dispatch({ type: 'delete-task', taskId })}
      />

      <TodayStats stats={dailyStats} />
    </main>
  )
}

export function App(): React.JSX.Element {
  return (
    <AppStoreProvider>
      <AppContent />
    </AppStoreProvider>
  )
}
