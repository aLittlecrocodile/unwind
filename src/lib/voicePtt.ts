/**
 * 按住说话（push-to-talk）语音通道，直连 Unwind 后端 /voice/ws。
 * 移植自 Unwind showcase 前端：麦克风 → AudioWorklet 采集 → 16k PCM 帧 →
 * WebSocket；下行为 JSON 事件（识别文本/回复文本）+ 二进制 TTS 音频。
 */

const WS_URL = 'ws://127.0.0.1:8000/voice/ws?user_id=showcase_user'
const TARGET_RATE = 16000
const FRAME_MS = 200

export interface PttEvents {
  onUserText(text: string, isFinal: boolean): void
  onAssistantText(text: string): void
  onTurnEnd(): void
  onAsset(url: string, title: string): void
  onError(message: string): void
}

const WORKLET_CODE = `
  class PetPcmWorklet extends AudioWorkletProcessor {
    process(inputs) {
      const channel = inputs[0][0]
      if (channel && channel.length) this.port.postMessage(channel.slice(0))
      return true
    }
  }
  registerProcessor('pet-pcm-capture', PetPcmWorklet)
`

function resample(f32: Float32Array, fromRate: number): Float32Array {
  if (fromRate === TARGET_RATE) return f32
  const ratio = fromRate / TARGET_RATE
  const outLen = Math.floor(f32.length / ratio)
  const out = new Float32Array(outLen)
  for (let i = 0; i < outLen; i++) {
    const idx = i * ratio
    const lo = Math.floor(idx)
    const hi = Math.min(lo + 1, f32.length - 1)
    out[i] = f32[lo] + (f32[hi] - f32[lo]) * (idx - lo)
  }
  return out
}

function floatToInt16(f32: Float32Array): ArrayBuffer {
  const out = new Int16Array(f32.length)
  for (let i = 0; i < f32.length; i++) {
    const s = Math.max(-1, Math.min(1, f32[i]))
    out[i] = s < 0 ? s * 0x8000 : s * 0x7fff
  }
  return out.buffer
}

export class PttSession {
  private ws: WebSocket | null = null
  private ctx: AudioContext | null = null
  private stream: MediaStream | null = null
  private recording = false
  private buffer: number[] = []
  private audioParts: ArrayBuffer[] = []
  private player: HTMLAudioElement | null = null

  constructor(private events: PttEvents) {}

  get ready(): boolean {
    return this.ws?.readyState === WebSocket.OPEN
  }

  async connect(): Promise<void> {
    if (this.ready) return
    await new Promise<void>((resolve, reject) => {
      const ws = new WebSocket(WS_URL)
      ws.binaryType = 'arraybuffer'
      ws.onopen = () => {
        this.ws = ws
        resolve()
      }
      ws.onerror = () => reject(new Error('语音服务连不上'))
      ws.onclose = () => {
        this.ws = null
      }
      ws.onmessage = (event) => this.handleMessage(event)
    })
  }

  private handleMessage(event: MessageEvent): void {
    if (event.data instanceof ArrayBuffer) {
      this.audioParts.push(event.data)
      return
    }
    let msg: Record<string, unknown>
    try {
      msg = JSON.parse(String(event.data))
    } catch {
      return
    }
    const type = msg.type
    if (type === 'user_text') {
      this.events.onUserText(String(msg.text ?? ''), Boolean(msg.is_final))
    } else if (type === 'assistant_text') {
      this.events.onAssistantText(String(msg.text ?? ''))
    } else if (type === 'audio_asset') {
      const url = String(msg.url ?? '')
      if (url) this.events.onAsset(url, String(msg.text ?? '专属音频'))
    } else if (type === 'turn_end') {
      this.playReply()
      this.events.onTurnEnd()
    } else if (type === 'error') {
      this.events.onError(String(msg.text ?? '语音链路出错'))
    }
  }

  private playReply(): void {
    if (!this.audioParts.length) return
    const blob = new Blob(this.audioParts, { type: 'audio/mpeg' })
    this.audioParts = []
    this.player?.pause()
    this.player = new Audio(URL.createObjectURL(blob))
    void this.player.play().catch(() => {})
  }

  async startHold(): Promise<void> {
    await this.connect()
    if (!this.ctx) {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true }
      })
      this.ctx = new AudioContext()
      const moduleUrl = URL.createObjectURL(new Blob([WORKLET_CODE], { type: 'application/javascript' }))
      await this.ctx.audioWorklet.addModule(moduleUrl)
      URL.revokeObjectURL(moduleUrl)
      const source = this.ctx.createMediaStreamSource(this.stream)
      const node = new AudioWorkletNode(this.ctx, 'pet-pcm-capture')
      const silent = this.ctx.createGain()
      silent.gain.value = 0
      node.port.onmessage = (event) => this.onFrame(event.data as Float32Array)
      source.connect(node)
      node.connect(silent)
      silent.connect(this.ctx.destination)
    }
    if (this.ctx.state === 'suspended') await this.ctx.resume()
    this.buffer = []
    this.audioParts = []
    this.recording = true
  }

  private onFrame(frame: Float32Array): void {
    if (!this.recording || !this.ctx || !this.ready) return
    const rs = resample(frame, this.ctx.sampleRate)
    for (let i = 0; i < rs.length; i++) this.buffer.push(rs[i])
    const frameSamples = (TARGET_RATE * FRAME_MS) / 1000
    while (this.buffer.length >= frameSamples) {
      this.ws?.send(floatToInt16(Float32Array.from(this.buffer.splice(0, frameSamples))))
    }
  }

  endHold(): void {
    if (!this.recording) return
    this.recording = false
    if (this.buffer.length && this.ready) {
      this.ws?.send(floatToInt16(Float32Array.from(this.buffer)))
      this.buffer = []
    }
    this.ws?.send(JSON.stringify({ type: 'utterance_end' }))
  }

  dispose(): void {
    this.recording = false
    this.player?.pause()
    this.stream?.getTracks().forEach((track) => track.stop())
    void this.ctx?.close()
    this.ws?.close()
    this.ctx = null
    this.stream = null
    this.ws = null
  }
}
