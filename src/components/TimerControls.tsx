import type { FocusPreset, SessionPhase } from '../domain/focusSession'

interface TimerControlsProps {
  phase: SessionPhase
  preset: FocusPreset
  remainingSeconds: number
  currentTaskTitle: string | null
  onStart(preset: FocusPreset): void
  onPause(): void
  onResume(): void
  onEnd(): void
}

function formatTime(seconds: number): string {
  const minutes = Math.floor(seconds / 60)
  const rest = seconds % 60
  return `${String(minutes).padStart(2, '0')}:${String(rest).padStart(2, '0')}`
}

export function TimerControls({
  phase,
  preset,
  remainingSeconds,
  currentTaskTitle,
  onStart,
  onPause,
  onResume,
  onEnd
}: TimerControlsProps): React.JSX.Element {
  const active = phase === 'focus' || phase === 'break' || phase === 'paused'
  const phaseLabel = phase === 'focus' ? '专注中' : phase === 'break' ? '休息中' : phase === 'paused' ? '已暂停' : '准备开始'

  return (
    <section className="panel-section timer-section">
      <div className="timer-header">
        <div>
          <div className="section-title">番茄钟</div>
          <div className="current-task">{currentTaskTitle ?? '还没选择任务'}</div>
        </div>
        <div className="phase-pill">{phaseLabel}</div>
      </div>

      <div className="timer-display">{active ? formatTime(remainingSeconds) : `${preset}:00`}</div>

      {phase === 'idle' ? (
        <div className="preset-row">
          {[25, 50, 90].map((value) => (
            <button key={value} type="button" onClick={() => onStart(value as FocusPreset)}>
              {value}m
            </button>
          ))}
        </div>
      ) : (
        <div className="control-row">
          {phase === 'paused' ? (
            <button type="button" onClick={onResume}>继续</button>
          ) : (
            <button type="button" onClick={onPause}>暂停</button>
          )}
          <button type="button" onClick={onEnd}>结束</button>
        </div>
      )}
    </section>
  )
}
