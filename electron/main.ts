import { app, BrowserWindow, ipcMain, screen, session } from 'electron'
import { join } from 'node:path'
import { is } from '@electron-toolkit/utils'
import { loadAppData, saveAppData } from './storage'
import { notify } from './notifications'
import type { AppData } from '../src/storage/defaultData'

const COMPACT_SIZE = { width: 340, height: 560 }
const EXPANDED_SIZE = { width: 420, height: 640 }

// Unwind 减压主界面（本地 FastAPI 后端渲染）。桌面端最大红利：
// Electron 视 127.0.0.1 为可信源，语音三件套（按住说话/通话/跟随呼吸）全部可用。
const UNWIND_URL = 'http://127.0.0.1:8000/showcase'
const UNWIND_SIZE = { width: 1320, height: 880 }

let mainWindow: BrowserWindow | null = null
let unwindWindow: BrowserWindow | null = null
let petHideTimer: ReturnType<typeof setTimeout> | null = null

function openUnwindWindow(): void {
  if (unwindWindow && !unwindWindow.isDestroyed()) {
    unwindWindow.show()
    unwindWindow.focus()
    return
  }
  unwindWindow = new BrowserWindow({
    width: UNWIND_SIZE.width,
    height: UNWIND_SIZE.height,
    title: 'Unwind · 把压力，呼出去',
    backgroundColor: '#eef0ec',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false
    }
  })
  unwindWindow.on('closed', () => {
    unwindWindow = null
  })
  void unwindWindow.loadURL(UNWIND_URL)
}

function createWindow(): void {
  // 小人默认站在屏幕右下角、Dock 正上方——桌宠的视觉锚点是脚,不是悬在半空
  const { workArea } = screen.getPrimaryDisplay()

  mainWindow = new BrowserWindow({
    width: COMPACT_SIZE.width,
    height: COMPACT_SIZE.height,
    x: workArea.x + workArea.width - COMPACT_SIZE.width - 24,
    y: workArea.y + workArea.height - COMPACT_SIZE.height - 8,
    frame: false,
    resizable: false,
    transparent: true,
    backgroundColor: '#00000000',
    alwaysOnTop: true,
    skipTaskbar: false,
    webPreferences: {
      preload: join(__dirname, '../preload/preload.mjs'),
      contextIsolation: true,
      nodeIntegration: false,
      // electron-vite 输出 ESM preload(.mjs)，Electron 仅在关闭 renderer
      // 沙箱时才能加载 ESM preload——否则桥接静默失败，所有 IPC 变成空转
      sandbox: false
    }
  })

  // 点击穿透的兜底：只在"小人窗口自己"获得焦点时恢复可交互。挂在
  // app 级 browser-window-focus 上会在任何窗口（包括 Unwind 大窗）拿到
  // 焦点时都触发，把还没被鼠标碰过的小人强制拉出穿透模式。
  mainWindow.on('focus', () => {
    mainWindow?.setIgnoreMouseEvents(false)
  })

  if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
    mainWindow.loadURL(process.env['ELECTRON_RENDERER_URL'])
  } else {
    mainWindow.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

function registerIpcHandlers(): void {
  ipcMain.handle('app-data:load', (): AppData => loadAppData())

  ipcMain.handle('app-data:save', (_event, data: AppData): void => {
    saveAppData(data)
  })

  ipcMain.handle('window:set-compact-mode', (_event, compact: boolean): void => {
    if (!mainWindow) return
    const size = compact ? COMPACT_SIZE : EXPANDED_SIZE
    const bounds = mainWindow.getBounds()
    mainWindow.setResizable(true)
    // 保持右下角不动:小人站在 Dock 上方,切换尺寸向左上生长,不会伸出屏幕
    mainWindow.setBounds(
      {
        x: bounds.x + bounds.width - size.width,
        y: bounds.y + bounds.height - size.height,
        width: size.width,
        height: size.height
      },
      true
    )
    // 小人形态锁定尺寸;工作台允许用户自己拉大
    if (compact) mainWindow.setResizable(false)
  })

  ipcMain.handle('window:set-always-on-top', (_event, alwaysOnTop: boolean): void => {
    mainWindow?.setAlwaysOnTop(alwaysOnTop)
  })

  ipcMain.handle('notification:show', (_event, title: string, body: string): void => {
    notify(title, body)
  })

  ipcMain.handle('unwind:open', (): void => {
    openUnwindWindow()
  })

  // "躲起来":小人暂避一段时间(到点自动回来;点 Dock 图标随时召回)
  ipcMain.handle('window:hide-temporarily', (_event, ms: number): void => {
    if (!mainWindow) return
    mainWindow.hide()
    if (petHideTimer) clearTimeout(petHideTimer)
    petHideTimer = setTimeout(() => mainWindow?.show(), ms)
  })

  // 桌宠透明区域点击穿透：鼠标不在小人/交互件上时，点击落到桌面
  ipcMain.handle('window:set-click-through', (_event, ignore: boolean): void => {
    mainWindow?.setIgnoreMouseEvents(ignore, { forward: true })
  })

  // 手动拖拽：-webkit-app-region 在透明+点击穿透的无边框窗口上不可靠，
  // 渲染层用 pointer 事件算屏幕坐标增量，走这两个通道挪窗口
  ipcMain.handle('window:get-position', (): [number, number] => {
    if (!mainWindow) return [0, 0]
    const [x, y] = mainWindow.getPosition()
    return [x, y]
  })

  ipcMain.handle('window:move-to', (_event, x: number, y: number): void => {
    mainWindow?.setPosition(Math.round(x), Math.round(y))
  })

  // 小人对话直连 Unwind 决策后端；在主进程发请求，天然无 CORS 问题
  ipcMain.handle('unwind:chat', async (_event, text: string): Promise<unknown> => {
    const resp = await fetch('http://127.0.0.1:8000/showcase/chat', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ request_text: text })
    })
    if (!resp.ok) throw new Error(`unwind backend HTTP ${resp.status}`)
    return await resp.json()
  })
}

app.whenReady().then(() => {
  // Unwind 页面需要麦克风（语音通话/跟随呼吸）与通知权限
  session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
    callback(permission === 'media' || permission === 'notifications')
  })
  registerIpcHandlers()
  loadAppData()
  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

// 兜底：应用被重新激活（如点击 Dock 图标）时召回躲起来的小人并恢复可交互
app.on('activate', () => {
  if (petHideTimer) {
    clearTimeout(petHideTimer)
    petHideTimer = null
  }
  mainWindow?.show()
  mainWindow?.setIgnoreMouseEvents(false)
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})
