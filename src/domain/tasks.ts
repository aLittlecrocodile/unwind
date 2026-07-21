/**
 * Todo 相关的数据结构和纯函数。不涉及持久化或 IPC。
 */

export interface Task {
  id: string
  title: string
  estimateMinutes: number
  done: boolean
  createdAt: number
  completedAt: number | null
}

export function createTask(title: string, estimateMinutes: number): Task {
  return {
    id: crypto.randomUUID(),
    title: title.trim(),
    estimateMinutes,
    done: false,
    createdAt: Date.now(),
    completedAt: null
  }
}

export function completeTask(task: Task): Task {
  if (task.done) return task
  return { ...task, done: true, completedAt: Date.now() }
}

export function reopenTask(task: Task): Task {
  if (!task.done) return task
  return { ...task, done: false, completedAt: null }
}

/** 未完成任务在前，完成任务在后；同组内按创建时间排序。 */
export function sortTasks(tasks: Task[]): Task[] {
  return [...tasks].sort((a, b) => {
    if (a.done !== b.done) return a.done ? 1 : -1
    return a.createdAt - b.createdAt
  })
}
