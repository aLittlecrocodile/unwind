import type { DailyStats } from '../domain/stats'

interface TodayStatsProps {
  stats: DailyStats
}

export function TodayStats({ stats }: TodayStatsProps): React.JSX.Element {
  return (
    <section className="stats-row" aria-label="今日统计">
      <div className="stat-item">
        <span className="stat-value">{stats.pomodoroCount}</span>
        <span className="stat-label">番茄</span>
      </div>
      <div className="stat-item">
        <span className="stat-value">{stats.focusMinutes}</span>
        <span className="stat-label">分钟</span>
      </div>
      <div className="stat-item">
        <span className="stat-value">{stats.tasksCompleted}</span>
        <span className="stat-label">完成</span>
      </div>
      <div className="stat-item">
        <span className="stat-value">{stats.waterCount}</span>
        <span className="stat-label">喝水</span>
      </div>
    </section>
  )
}
