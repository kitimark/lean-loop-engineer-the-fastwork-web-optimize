import { active, dir, frame, push, taken, type St } from './logic';

export interface Hooks {
  target(pin: number, maxY: () => number): number;
  allow(fresh: boolean, ctr: number): boolean;
  release: boolean;
}

export const BASE: Hooks = { target: (pin) => pin, allow: () => true, release: false };

export const FLIP_N = 16;

export interface Read {
  readonly scrollY: number;
  readonly arm: boolean;
  readonly now: number;
  readonly reduced: boolean;
  /** `Event.cancelable` of the move; absent means true (Lean `Fw.Parts.ComboScroll`, the cancelable bit of `wstep`). */
  readonly cancelable?: boolean;
}

export interface EndState {
  tw: St;
  touchY: number;
  pin: number;
  ctr: number;
  fresh: boolean;
  rel: boolean;
  /** Lean `ComboScroll.W.held`: the last move was prevented and the browser let that stand; only then may the frame writer write. */
  held: boolean;
}

export interface Out {
  prevent: boolean;
  goal: number | null;
  flip: boolean;
  write: number | null;
}

const NONE: Out = { prevent: false, goal: null, flip: false, write: null };

export type EndEv =
  | { ev: 'touchstart'; y: number | null }
  | ({ ev: 'touchmove'; y: number | null } & Read)
  | ({ ev: 'wheel'; delta: number } & Read)
  | { ev: 'scroll' | 'resize'; y: number; maxY: number }
  | { ev: 'tick'; now: number };

export const initEnd = (pin: number, tw: St): EndState => ({ tw, touchY: 0, pin, ctr: 0, fresh: false, rel: false, held: true });

const isActive = (tw: St): boolean => active({ target: tw.target, value: tw.value });
const away = (target: number, d: number): number => (target === 1 ? -d : d);
const ctrAfter = (s: EndState, d: number): number => Math.max(0, s.ctr + away(s.tw.target, d));
const free = (h: Hooks, s: EndState): boolean => h.release && s.rel;
const pinAfter = (h: Hooks, s: EndState, r: Read): number => (isActive(s.tw) && !free(h, s) ? s.pin : r.scrollY);

const blocked = (h: Hooks, s: EndState, d: number, g: number): boolean =>
  (s.tw.target === g && s.tw.to === g) || (isActive(s.tw) && !h.allow(s.fresh, ctrAfter(s, d)));

/** The inner step of a move (Lean `MorphEnd.moveStep`). */
function innerMove(h: Hooks, s: EndState, d: number, r: Read): [EndState, Out] {
  if (!taken({ active: isActive(s.tw), delta: d, armed: r.arm })) return [{ ...s, ctr: ctrAfter(s, d) }, NONE];
  const g = dir({ delta: d });
  if (g === null || blocked(h, s, d, g)) {
    return [{ ...s, pin: pinAfter(h, s, r), ctr: ctrAfter(s, d) }, { ...NONE, prevent: !free(h, s) }];
  }
  const pin = pinAfter(h, s, r);
  return [
    { ...s, tw: push({ state: s.tw, goal: g, reduced: r.reduced, now: r.now }), pin, ctr: 0, fresh: false, rel: g === 0 },
    { prevent: !(h.release && g === 0), goal: g, flip: isActive(s.tw), write: null },
  ];
}

/**
 * A move (Lean `ComboScroll.wstep`, move case). With `release` a move holds the page only when it is prevented and
 * cancelable; a move that brings the hold back re-pins where the page is. Without `release` nothing changes.
 */
export function moveStep(h: Hooks, s: EndState, d: number, r: Read): [EndState, Out] {
  const [next, out] = innerMove(h, s, d, r);
  if (!h.release) return [next, out];
  const holds = out.prevent && r.cancelable !== false;
  return [{ ...next, held: holds, pin: holds && !s.held ? r.scrollY : next.pin }, out];
}

export function frameOut(h: Hooks, s: EndState, y: number, maxY: () => number): number | null {
  if (!isActive(s.tw) || (h.release && (s.rel || !s.held))) return null;
  const t = h.target(s.pin, maxY);
  return y !== t ? t : null;
}

export function touchStart(s: EndState, y: number | null): EndState {
  return { ...s, touchY: y ?? 0, ctr: 0, fresh: true };
}

export function step(h: Hooks, s: EndState, e: EndEv): [EndState, Out] {
  switch (e.ev) {
    case 'touchstart':
      return [touchStart(s, e.y), NONE];
    case 'touchmove': {
      const y = e.y ?? s.touchY;
      return moveStep(h, { ...s, touchY: y }, s.touchY - y, e);
    }
    case 'wheel':
      return moveStep(h, s, e.delta, e);
    case 'scroll':
    case 'resize':
      return [s, { ...NONE, write: frameOut(h, s, e.y, () => e.maxY) }];
    case 'tick':
      return [s.tw.pending ? { ...s, tw: frame({ state: s.tw, now: e.now }) } : s, NONE];
  }
}
