export const STILL_MAX = 8;
export const FRAME_CAP = 3600;
export const FOLLOW_ORDER = -1e9;

export interface FollowState {
  last: number;
  still: number;
  frames: number;
  on: boolean;
}

export function idleState(y: number): FollowState {
  return { last: y, still: 0, frames: 0, on: false };
}

export function wakeState(y: number): FollowState {
  return { last: y, still: 0, frames: 1, on: true };
}

/** Lean Fw.Parts.EngineScrollFollow.step. */
export function followStep(s: FollowState, y: number, ended: boolean): FollowState {
  if (s.on) {
    const still = y === s.last ? s.still + 1 : 0;
    const frames = s.frames + 1;
    return { last: y, still, frames, on: !ended && still < STILL_MAX && frames < FRAME_CAP };
  }
  return y === s.last ? s : wakeState(y);
}

/** Lean Fw.Parts.EngineScrollFollow.stepG. */
export function followStepG(coarse: boolean, s: FollowState, y: number, ended: boolean): FollowState {
  return coarse ? followStep(s, y, ended) : s;
}

/** Lean Fw.Parts.EngineScrollFollow.drive. */
export function followDrive(s: FollowState, ys: readonly number[]): { state: FollowState; frames: number } {
  let frames = 0;
  for (const y of ys) {
    if (!s.on) break;
    s = followStep(s, y, false);
    frames++;
  }
  return { state: s, frames };
}

export interface FollowEngine {
  register(id: string, order: number, cb: (f: { y: number }) => void): () => void;
  request(): void;
}

export interface FollowEnv {
  coarse(): boolean;
  readY(): number;
  onScrollEnd(fn: () => void): () => void;
}

/** Registers the loop on the scroll engine: each frame feeds `followStepG` and asks for the next while it is on. */
export function installFollow(engine: FollowEngine, env: FollowEnv): () => void {
  let s = idleState(env.readY());
  let ended = false;
  const offEnd = env.onScrollEnd(() => {
    ended = true;
  });
  const off = engine.register('engine.scroll.follow', FOLLOW_ORDER, (f) => {
    s = followStepG(env.coarse(), s, f.y, ended);
    ended = false;
    if (s.on) engine.request();
  });
  return () => {
    off();
    offEnd();
  };
}

export const windowFollowEnv: FollowEnv = {
  coarse: () => window.matchMedia('(pointer: coarse)').matches,
  readY: () => window.scrollY,
  onScrollEnd: (fn) => {
    window.addEventListener('scrollend', fn, { passive: true });
    return () => window.removeEventListener('scrollend', fn);
  },
};
