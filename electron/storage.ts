import { app } from 'electron'
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import type { AppData } from '../src/storage/defaultData'
import { createDefaultAppData } from '../src/storage/defaultData'

const DATA_FILE = 'worker-buddy-data.json'

function getDataPath(): string {
  return join(app.getPath('userData'), DATA_FILE)
}

function ensureDataDir(filePath: string): void {
  const dir = dirname(filePath)
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
}

export function loadAppData(): AppData {
  const filePath = getDataPath()
  if (!existsSync(filePath)) {
    const defaultData = createDefaultAppData()
    saveAppData(defaultData)
    return defaultData
  }

  try {
    const raw = readFileSync(filePath, 'utf-8')
    const parsed = JSON.parse(raw) as AppData
    return { ...createDefaultAppData(), ...parsed }
  } catch {
    const backupPath = `${filePath}.broken-${Date.now()}`
    try {
      renameSync(filePath, backupPath)
    } catch {
      // 备份失败时仍返回默认数据，避免应用启动失败。
    }
    const defaultData = createDefaultAppData()
    saveAppData(defaultData)
    return defaultData
  }
}

export function saveAppData(data: AppData): void {
  const filePath = getDataPath()
  ensureDataDir(filePath)
  writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf-8')
}
