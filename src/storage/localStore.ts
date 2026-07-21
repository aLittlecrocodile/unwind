import type { AppData } from './defaultData'
import { createDefaultAppData } from './defaultData'
import { getElectronApi } from '../lib/electronApi'

export async function loadLocalAppData(): Promise<AppData> {
  const api = getElectronApi()
  if (!api) return createDefaultAppData()
  return api.loadAppData()
}

export async function saveLocalAppData(data: AppData): Promise<void> {
  const api = getElectronApi()
  if (!api) return
  await api.saveAppData(data)
}
