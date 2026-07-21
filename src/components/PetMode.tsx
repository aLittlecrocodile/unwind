import { useEffect, useRef, useState } from 'react'
import { WorkerBuddy } from './WorkerBuddy'
import type { BuddyState } from '../domain/buddyState'
import { getElectronApi } from '../lib/electronApi'
import { PttSession } from '../lib/voicePtt'
import './PetMode.css'

interface PetModeProps {
  buddyState: BuddyState
  statusLine: string
  onExpand: () => void
}

const QUICK_CHIPS = ['我压力好大', '来点雨声', '给我一张安心签']
const IDLE_BUBBLE = '按住 🎙 跟我说话，或点我打字'

export function PetMode({ buddyState, statusLine, onExpand }: PetModeProps): React.JSX.Element {
  const api = getElectronApi()
  const [chatOpen, setChatOpen] = useState(false)
  const [bubble, setBubble] = useState(IDLE_BUBBLE)
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [holding, setHolding] = useState(false)
  const voiceRef = useRef<HTMLAudioElement | null>(null)
  const ambientRef = useRef<HTMLAudioElement | null>(null)
  const inputRef = useRef<HTMLInputElement | null>(null)
  const pttRef = useRef<PttSession | null>(null)
  const replyRef = useRef('')

  useEffect(() => {
    if (chatOpen) inputRef.current?.focus()
  }, [chatOpen])

  useEffect(() => () => {
    voiceRef.current?.pause()
    ambientRef.current?.pause()
    pttRef.current?.dispose()
  }, [])

  function playAmbient(url: string): void {
    ambientRef.current?.pause()
    ambientRef.current = new Audio(url)
    void ambientRef.current.play().catch(() => {})
  }

  function ptt(): PttSession {
    if (!pttRef.current) {
      pttRef.current = new PttSession({
        onUserText: (text, isFinal) => {
          if (text) setBubble(isFinal ? `听到啦：「${text}」` : `「${text}」`)
        },
        onAssistantText: (text) => {
          replyRef.current += text
          setBubble(replyRef.current)
        },
        onTurnEnd: () => setBusy(false),
        onAsset: (url) => playAmbient(url),
        onError: (message) => {
          setBusy(false)
          setBubble(`语音这条路不太顺：${message}`)
        }
      })
    }
    return pttRef.current
  }

  async function holdStart(): Promise<void> {
    if (busy) return
    try {
      setHolding(true)
      setBubble('我在听……')
      await ptt().startHold()
    } catch {
      setHolding(false)
      setBubble('麦克风没打开，检查一下系统授权？')
    }
  }

  function holdEnd(): void {
    if (!holding) return
    setHolding(false)
    setBusy(true)
    replyRef.current = ''
    setBubble('嗯，让我想想……')
    ptt().endHold()
  }

  async function send(text: string): Promise<void> {
    const line = text.trim()
    if (!line || busy || !api) return
    setBusy(true)
    setInput('')
    setBubble(`「${line}」……我想想`)
    try {
      const res = await api.unwindChat(line)
      setBubble(res.reply || '我在呢。')
      if (res.reply_audio_url) {
        voiceRef.current?.pause()
        voiceRef.current = new Audio(res.reply_audio_url)
        void voiceRef.current.play().catch(() => {})
      }
      if (res.asset?.playback_url) playAmbient(res.asset.playback_url)
    } catch {
      setBubble('我这会儿有点走神了，再说一次？')
    } finally {
      setBusy(false)
    }
  }

  return (
    <main
      className="pet-shell"
      onMouseEnter={() => api?.setClickThrough(false)}
      onMouseLeave={() => {
        if (!holding) api?.setClickThrough(true)
      }}
    >
      <div className="drag-region" />

      <div className={`pet-bubble ${busy ? 'busy' : ''}`}>{bubble}</div>

      <button
        type="button"
        className="pet-body"
        title={chatOpen ? '收起输入' : '打字聊'}
        onClick={() => setChatOpen((open) => !open)}
      >
        <WorkerBuddy state={buddyState} bubbleOverride="" />
      </button>

      <div className="pet-mic-row">
        <button
          type="button"
          className={`pet-mic ${holding ? 'holding' : ''}`}
          title="按住说话"
          onPointerDown={(event) => {
            event.currentTarget.setPointerCapture(event.pointerId)
            void holdStart()
          }}
          onPointerUp={holdEnd}
          onPointerCancel={holdEnd}
        >
          🎙
        </button>
        <div className="pet-status">{holding ? '松开结束' : statusLine}</div>
      </div>

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

      <div className="pet-toolbar">
        <button type="button" onClick={() => api?.openUnwind()}>Unwind ⤢</button>
        <button type="button" onClick={onExpand}>工作台</button>
      </div>
    </main>
  )
}
