import { getBuddyPresentation } from '../domain/buddyState'
import type { BuddyState } from '../domain/buddyState'
import './WorkerBuddy.css'

interface WorkerBuddyProps {
  state: BuddyState
  bubbleOverride?: string
}

export function WorkerBuddy({ state, bubbleOverride }: WorkerBuddyProps): React.JSX.Element {
  const { face, bubble } = getBuddyPresentation(state)

  return (
    <div className="stage" data-state={state}>
      <div className="bubble show">{bubbleOverride ?? bubble}</div>

      <div className="desk" />
      <div className="laptop">
        <div className="screen" />
        <div className="base" />
      </div>
      <div className="cup" />

      <div className="buddy">
        <div className="fx sweat">💦</div>
        <div className="fx thirst">🥤</div>
        <div className="fx spark">✨</div>

        <div className="head">
          <div className="hair" />
          <div className="face">
            <span className="face-open">{face}</span>
            <span className="face-blink" aria-hidden="true">-_-</span>
          </div>
        </div>
        <div className="torso" />
        <div className="arm left" />
        <div className="arm right" />
        <div className="legs">
          <div className="leg left" />
          <div className="leg right" />
        </div>
      </div>
    </div>
  )
}
