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
      // 只通知,不抢屏:减压产品不该自己制造压迫感。
      // 大窗由小人气泡里的"喘口气"邀请 chip 打开,主动权在用户手里。
      api?.notify('该休息了', '这轮打完了,小人想陪你喘口气。')
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
        : phase === 'paused'
          ? '已暂停 · 去工作台继续'
          : '待命中 · 点我聊聊'
    const phaseTotal = state.focusSession.phaseDurationSeconds
    const progress = (phase === 'focus' || phase === 'break') && phaseTotal > 0
      ? 1 - remainingSeconds / phaseTotal
      : null
    return (
      <PetMode
        buddyState={buddyState}
        statusLine={statusLine}
        progress={progress}
        waterDue={waterDue}
        tiredDue={tiredDue}
        onStandUp={() => dispatch({ type: 'confirm-stood-up' })}
        onDrinkWater={() => dispatch({ type: 'confirm-drank-water' })}
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
