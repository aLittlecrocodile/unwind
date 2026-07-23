import { useEffect, useRef, useState } from 'react'
import { WorkerBuddy } from './WorkerBuddy'
import type { BuddyState } from '../domain/buddyState'
import { getElectronApi } from '../lib/electronApi'
import { PttSession } from '../lib/voicePtt'
import './PetMode.css'

interface PetModeProps {
  buddyState: BuddyState
  statusLine: string
  /** 当前阶段进度 0-1（专注/休息倒计时），没在计时则为 null */
  progress: number | null
  waterDue: boolean
  tiredDue: boolean
  /** 专注中久坐提醒不打断，气泡/chips 让位给专注场景 */
  isFocusing: boolean
  onStandUp: () => void
  onDrinkWater: () => void
  onExpand: () => void
}

const QUICK_CHIPS = ['我压力好大', '来点雨声', '给我一张安心签']
const IDLE_BUBBLE = '点一下 🎙 跟我说话，或点我打字'
/** 对话内容展示这么久后淡回场景提示，避免错误信息/旧回复永远挂着 */
const MESSAGE_TTL_MS = 30_000
const CHAT_TIMEOUT_MS = 15_000
/** 按下超过这个时长视为"按住说话"，松手即结束；短于它则是"点一下"切换 */
const HOLD_THRESHOLD_MS = 300
const HIDE_MS = 10 * 60 * 1000

export function PetMode({
  buddyState,
  statusLine,
  progress,
  waterDue,
  tiredDue,
  isFocusing,
  onStandUp,
  onDrinkWater,
  onExpand
}: PetModeProps): React.JSX.Element {
  const api = getElectronApi()
  const [chatOpen, setChatOpen] = useState(false)
  /** 对话产生的临时内容；null 时气泡回落到场景提示 */
  const [message, setMessage] = useState<string | null>(null)
  /** 上一句"你说的"，和小人的回复分层展示，不再互相覆盖 */
  const [userLine, setUserLine] = useState<string | null>(null)
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [recording, setRecording] = useState(false)
  const [nowPlaying, setNowPlaying] = useState<string | null>(null)
  const [poked, setPoked] = useState(false)
  const voiceRef = useRef<HTMLAudioElement | null>(null)
  const ambientRef = useRef<HTMLAudioElement | null>(null)
  const inputRef = useRef<HTMLInputElement | null>(null)
  const pttRef = useRef<PttSession | null>(null)
  const replyRef = useRef('')
  const recordingRef = useRef(false)
  const pressAtRef = useRef(0)
  const stoppedByPressRef = useRef(false)
  const [dragging, setDragging] = useState(false)
  const dragRef = useRef<{ pointerId: number; startX: number; startY: number; winX: number; winY: number; moved: boolean } | null>(null)
  const dragRafRef = useRef(0)
  const dragTargetRef = useRef<{ x: number; y: number } | null>(null)
  const dragConsumedClickRef = useRef(false)

  useEffect(() => {
    if (chatOpen) inputRef.current?.focus()
  }, [chatOpen])

  useEffect(() => () => {
    voiceRef.current?.pause()
    ambientRef.current?.pause()
    pttRef.current?.dispose()
  }, [])

  // 旧内容自动衰减：说完话安静一会儿后，气泡让位给场景提示
  useEffect(() => {
    if (!message || busy || recording) return
    const timer = setTimeout(() => {
      setMessage(null)
      setUserLine(null)
    }, MESSAGE_TTL_MS)
    return () => clearTimeout(timer)
  }, [message, busy, recording])

  function say(text: string): void {
    setUserLine(null)
    setMessage(text)
  }

  function playAmbient(url: string, title: string): void {
    ambientRef.current?.pause()
    const audio = new Audio(url)
    audio.onended = () => {
      if (ambientRef.current === audio) setNowPlaying(null)
    }
    ambientRef.current = audio
    setNowPlaying(title)
    void audio.play().catch(() => setNowPlaying(null))
  }

  function stopAmbient(): void {
    ambientRef.current?.pause()
    ambientRef.current = null
    setNowPlaying(null)
  }

  function ptt(): PttSession {
    if (!pttRef.current) {
      pttRef.current = new PttSession({
        onUserText: (text, isFinal) => {
          if (!text) return
          if (isFinal) {
            setUserLine(text)
            setMessage('听到啦，我想想…')
          } else {
            setMessage(`「${text}」`)
          }
        },
        onAssistantText: (text) => {
          replyRef.current += text
          setMessage(replyRef.current)
        },
        onTurnEnd: () => setBusy(false),
        onAsset: (url, title) => playAmbient(url, title),
        onError: () => {
          setBusy(false)
          recordingRef.current = false
          setRecording(false)
          say('语音这条路断了，缓一下再试？')
        }
      })
    }
    return pttRef.current
  }

  async function startRecording(): Promise<void> {
    if (busy) return
    try {
      recordingRef.current = true
      setRecording(true)
      setUserLine(null)
      setMessage('我在听……')
      await ptt().startHold()
    } catch {
      recordingRef.current = false
      setRecording(false)
      say('麦克风没打开，看看系统授权？')
    }
  }

  function stopRecording(): void {
    if (!recordingRef.current) return
    recordingRef.current = false
    setRecording(false)
    setBusy(true)
    replyRef.current = ''
    setMessage('嗯，让我想想……')
    ptt().endHold()
  }

  // 点一下开始/再点结束；按住超过阈值则松手即结束（两种习惯都伺候）
  function micDown(event: React.PointerEvent<HTMLButtonElement>): void {
    event.currentTarget.setPointerCapture(event.pointerId)
    pressAtRef.current = Date.now()
    if (recordingRef.current) {
      stoppedByPressRef.current = true
      stopRecording()
    } else {
      stoppedByPressRef.current = false
      void startRecording()
    }
  }

  function micUp(): void {
    if (stoppedByPressRef.current) {
      stoppedByPressRef.current = false
      return
    }
    if (recordingRef.current && Date.now() - pressAtRef.current >= HOLD_THRESHOLD_MS) {
      stopRecording()
    }
  }

  // 手动拖拽：-webkit-app-region 在"透明+无边框+点击穿透"窗口上不可靠，
  // 改用 pointer 事件算屏幕坐标增量、经 IPC 挪窗口。小人身体和状态胶囊都能拖；
  // 位移小于阈值仍算点击（点小人还是开聊天）。
  async function dragStart(event: React.PointerEvent<HTMLElement>): Promise<void> {
    if (!api) return
    const { pointerId, screenX, screenY } = event
    event.currentTarget.setPointerCapture(pointerId)
    const [winX, winY] = await api.getPetPosition()
    dragRef.current = { pointerId, startX: screenX, startY: screenY, winX, winY, moved: false }
  }

  function dragMove(event: React.PointerEvent<HTMLElement>): void {
    const drag = dragRef.current
    if (!drag || event.pointerId !== drag.pointerId) return
    const dx = event.screenX - drag.startX
    const dy = event.screenY - drag.startY
    if (!drag.moved && Math.abs(dx) + Math.abs(dy) < 5) return
    if (!drag.moved) {
      drag.moved = true
      setDragging(true)
    }
    dragTargetRef.current = { x: drag.winX + dx, y: drag.winY + dy }
    // rAF 节流：每帧最多发一次 IPC；dragEnd 后残留的最后一帧照发，落到终点
    if (!dragRafRef.current) {
      dragRafRef.current = requestAnimationFrame(() => {
        dragRafRef.current = 0
        const target = dragTargetRef.current
        if (target) void api?.movePetTo(Math.round(target.x), Math.round(target.y))
      })
    }
  }

  function dragEnd(): void {
    const drag = dragRef.current
    if (!drag) return
    if (drag.moved) dragConsumedClickRef.current = true
    dragRef.current = null
    setDragging(false)
  }

  async function send(text: string): Promise<void> {
    const line = text.trim()
    if (!line || busy || !api) return
    setBusy(true)
    setInput('')
    setUserLine(line)
    setMessage('我想想……')
    let timeoutId: ReturnType<typeof setTimeout> | undefined
    try {
      const chat = api.unwindChat(line)
      // 超时放弃后迟到的失败不该变成 unhandled rejection
      chat.catch(() => {})
      const res = await Promise.race([
        chat,
        new Promise<never>((_, reject) => {
          timeoutId = setTimeout(() => reject(new Error('timeout')), CHAT_TIMEOUT_MS)
        })
      ])
      setMessage(res.reply || '我在呢。')
      if (res.reply_audio_url) {
        voiceRef.current?.pause()
        voiceRef.current = new Audio(res.reply_audio_url)
        void voiceRef.current.play().catch(() => {})
      }
      if (res.asset?.playback_url) playAmbient(res.asset.playback_url, res.asset.title ?? '环境音')
    } catch (error) {
      setMessage(
        error instanceof Error && error.message === 'timeout'
          ? '后端半天没吭声，再戳我一次？'
          : '我这会儿有点走神了，再说一次？'
      )
    } finally {
      clearTimeout(timeoutId)
      setBusy(false)
    }
  }

  // 没有对话内容时，气泡展示当下最要紧的场景（喝水/久坐 > 休息邀请 > 待命提示）
  // 久坐提醒不打断专注：专注中即使 tiredDue 为真也不抢气泡。
  let contextText = IDLE_BUBBLE
  let contextChips: { label: string; run: () => void }[] = []
  if (waterDue || (tiredDue && !isFocusing)) {
    contextText = waterDue ? '一小时没喝水啦，润一口再战？' : '坐满两轮了，起来抖一抖？'
    contextChips = [
      { label: '我起来了', run: () => { onStandUp(); say('起身打卡！身体会谢你的') } },
      { label: '喝水了', run: () => { onDrinkWater(); say('咕咚咕咚，补水完成') } }
    ]
  } else if (buddyState === 'rest') {
    contextText = '这轮打完了，跟我喘口气？'
    contextChips = [{ label: '好，喘口气 ⤢', run: () => api?.openUnwind() }]
  }
  const bubbleText = message ?? contextText

  return (
    <main
      className={`pet-shell ${dragging ? 'dragging' : ''}`}
      onMouseEnter={() => api?.setClickThrough(false)}
      onMouseLeave={() => {
        // 录音或拖拽中窗口可能落后于指针，此时开穿透会让事件流断掉
        if (!recording && !dragRef.current) api?.setClickThrough(true)
      }}
    >
      <div className={`pet-bubble ${busy ? 'busy' : ''}`}>
        {userLine && message && <div className="pet-bubble-you">你：{userLine}</div>}
        <div className="pet-bubble-text">{bubbleText}</div>
      </div>

      {!message && contextChips.length > 0 && (
        <div className="pet-chips">
          {contextChips.map((chip) => (
            <button key={chip.label} type="button" onClick={chip.run}>
              {chip.label}
            </button>
          ))}
        </div>
      )}

      {chatOpen && (
        <div className="pet-chat">
          <div className="pet-chips">
            {QUICK_CHIPS.map((chip) => (
              <button key={chip} type="button" disabled={busy} onClick={() => void send(chip)}>
                {chip}
              </button>
            ))}
          </div>
          <div className="pet-input-row">
            <input
              ref={inputRef}
              value={input}
              placeholder="打字也行…"
              disabled={busy}
              onChange={(event) => setInput(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter') void send(input)
              }}
            />
            <button type="button" disabled={busy || !input.trim()} onClick={() => void send(input)}>
              说
            </button>
          </div>
        </div>
      )}

      <button
        type="button"
        className={`pet-body ${poked ? 'poked' : ''}`}
        title={chatOpen ? '收起输入' : '打字聊（按住可拖动）'}
        onClick={() => {
          if (dragConsumedClickRef.current) {
            dragConsumedClickRef.current = false
            return
          }
          setChatOpen((open) => !open)
          setPoked(true)
        }}
        onAnimationEnd={() => setPoked(false)}
        onPointerDown={(event) => void dragStart(event)}
        onPointerMove={dragMove}
        onPointerUp={dragEnd}
        onPointerCancel={dragEnd}
      >
        <WorkerBuddy state={buddyState} bubbleOverride="" />
      </button>

      <div className="pet-mic-row">
        <button
          type="button"
          className={`pet-mic ${recording ? 'holding' : ''}`}
          title="点一下说话，再点结束（按住也行）"
          onPointerDown={micDown}
          onPointerUp={micUp}
          onPointerCancel={micUp}
        >
          🎙
        </button>
        <div
          className="pet-status"
          title="按住拖动"
          onPointerDown={(event) => void dragStart(event)}
          onPointerMove={dragMove}
          onPointerUp={dragEnd}
          onPointerCancel={dragEnd}
        >
          {progress !== null && (
            <span className="pet-status-fill" style={{ width: `${Math.round(progress * 100)}%` }} />
          )}
          <span className="pet-status-text">{recording ? '在听 · 再点一下结束' : statusLine}</span>
        </div>
      </div>

      {nowPlaying && (
        <button type="button" className="pet-playing" onClick={stopAmbient} title="停止播放">
          ♪ {nowPlaying} · 停
        </button>
      )}

      <div className="pet-toolbar">
        <button type="button" onClick={() => api?.openUnwind()}>喘口气 ⤢</button>
        <button type="button" onClick={onExpand}>工作台</button>
        <button type="button" title="躲 10 分钟，点 Dock 图标随时叫回" onClick={() => api?.hidePet(HIDE_MS)}>
          躲起来
        </button>
      </div>
    </main>
  )
}
