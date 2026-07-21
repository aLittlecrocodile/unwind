import { useState } from 'react'
import type { Task } from '../domain/tasks'

interface TodoListProps {
  tasks: Task[]
  currentTaskId: string | null
  onAdd(title: string, estimateMinutes: number): void
  onSelect(taskId: string): void
  onComplete(taskId: string): void
  onDelete(taskId: string): void
}

export function TodoList({ tasks, currentTaskId, onAdd, onSelect, onComplete, onDelete }: TodoListProps): React.JSX.Element {
  const [title, setTitle] = useState('')
  const [estimate, setEstimate] = useState(50)

  function handleSubmit(event: React.FormEvent): void {
    event.preventDefault()
    if (!title.trim()) return
    onAdd(title, estimate)
    setTitle('')
    setEstimate(50)
  }

  return (
    <section className="panel-section todo-section">
      <div className="section-title">今日 Todo</div>
      <form className="task-form" onSubmit={handleSubmit}>
        <input
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          placeholder="写下一个任务"
          aria-label="任务标题"
        />
        <select value={estimate} onChange={(event) => setEstimate(Number(event.target.value))} aria-label="预估时长">
          <option value={25}>25m</option>
          <option value={50}>50m</option>
          <option value={90}>90m</option>
        </select>
        <button type="submit">添加</button>
      </form>

      <div className="task-list">
        {tasks.length === 0 ? (
          <div className="empty-state">还没有任务，先给小人安排点活。</div>
        ) : (
          tasks.map((task) => (
            <div className={`task-row ${task.done ? 'done' : ''} ${task.id === currentTaskId ? 'active' : ''}`} key={task.id}>
              <button className="task-check" type="button" onClick={() => onComplete(task.id)} aria-label="完成任务">
                {task.done ? '✓' : '○'}
              </button>
              <button className="task-main" type="button" onClick={() => onSelect(task.id)} disabled={task.done}>
                <span className="task-title">{task.title}</span>
                <span className="task-meta">{task.estimateMinutes} 分钟</span>
              </button>
              <button className="task-delete" type="button" onClick={() => onDelete(task.id)} aria-label="删除任务">
                ×
              </button>
            </div>
          ))
        )}
      </div>
    </section>
  )
}
