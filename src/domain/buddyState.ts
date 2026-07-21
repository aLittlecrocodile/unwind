/**
 * 桌宠状态模型。
 * 状态优先级（从高到低）：transient > water > tired > focus > rest > idle。
 * 上层（appStore）负责根据业务数据算出当前状态，本文件只描述状态本身和展示内容。
 */

export type BuddyState = 'idle' | 'focus' | 'rest' | 'tired' | 'water' | 'done' | 'stood' | 'hydrated'

export interface BuddyPresentation {
  face: string
  bubble: string
}

const PRESENTATIONS: Record<BuddyState, BuddyPresentation> = {
  idle: { face: '·_·', bubble: '今天想做点什么？' },
  focus: { face: '^_^', bubble: '在专心打字…' },
  rest: { face: '~o~', bubble: '这轮陪你打完啦，伸个懒腰～' },
  tired: { face: '-_-', bubble: '救命，好酸…真的要起来啦' },
  water: { face: '>_<', bubble: '喝水时间到' },
  done: { face: '^o^', bubble: '这个任务搞定啦！' },
  stood: { face: '^_^', bubble: '起身打卡，身体会感谢你' },
  hydrated: { face: '^o^', bubble: '喝水打卡完成' }
}

export function getBuddyPresentation(state: BuddyState): BuddyPresentation {
  return PRESENTATIONS[state]
}
