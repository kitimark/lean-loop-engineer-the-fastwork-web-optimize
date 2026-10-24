/**
 * Pure end-of-page reducer of morph.tween (no DOM) and the hooks the three end bricks rewrite. Restated from
 * `Fw.Parts.MorphEnd` (lean/Fw/Parts/MorphEnd.lean `moveStep`, `frameOut`, `step`; original N2:13017-13090); golden
 * vectors packages/contracts/golden/parts/morph.end.jsonl (end.golden.test.ts). With `BASE` hooks it is the
 * original event by event (Lean `faithful_eq_orig`). The bricks (`morph.end.clamp`, `.flip`, `.release`) each
 * rewrite one hook; composition order is free (Lean `order_free`).
 */
import { active, dir, frame, push, taken, type St } from './logic';

/** What a brick may change; the defaults are the original. */
export interface Hooks {
  /** Where the pin is restored to each frame, given the pin and the page's real maxY (read only if needed). */
  target(pin: number, maxY: () => number): number;
  /** Whether an active morph may flip: `fresh` = a touch began since the last push, `ctr` = net travel against the goal. */
  allow(fresh: boolean, ctr: number): boolean;
  /** Drop the pin and stop `preventDefault` from a close start until the next open. */
  release: boolean;
}

export const BASE: Hooks = { target: (pin) => pin, allow: () => true, release: false };

/** Net travel (px) against the goal that lets an active morph flip without a new touch (Lean `flipN`). */
export const FLIP_N = 16;

/** Reads of the page at one input event; getters keep each read lazy, as the original reads only what it needs. */
export interface Read {
  readonly scrollY: number;
  readonly arm: boolean;
  readonly now: number;
  readonly reduced: boolean;
}

export interface EndState {
  tw: St;
  touchY: number;
  pin: number;
  ctr: number;
  fresh: boolean;
  rel: boolean;
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

export const initEnd = (pin: number, tw: St): EndState => ({ tw, touchY: 0, pin, ctr: 0, fresh: false, rel: false });

const isActive = (tw: St): boolean => active({ target: tw.target, value: tw.value });
const away = (target: number, d: number): number => (target === 1 ? -d : d);
const ctrAfter = (s: EndState, d: number): number => Math.max(0, s.ctr + away(s.tw.target, d));
const free = (h: Hooks, s: EndState): boolean => h.release && s.rel;
const pinAfter = (h: Hooks, s: EndState, r: Read): number => (isActive(s.tw) && !free(h, s) ? s.pin : r.scrollY);

const blocked = (h: Hooks, s: EndState, d: number, g: number): boolean =>
  (s.tw.target === g && s.tw.to === g) || (isActive(s.tw) && !h.allow(s.fresh, ctrAfter(s, d)));

/** One wheel or touchmove of delta `d` (Lean `moveStep`). */
export function moveStep(h: Hooks, s: EndState, d: number, r: Read): [EndState, Out] {
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

/** The pin restore of one scroll or resize frame (Lean `frameOut`); `y` is scrollY, `maxY` the real end. */
export function frameOut(h: Hooks, s: EndState, y: number, maxY: () => number): number | null {
  if (!isActive(s.tw) || (h.release && s.rel)) return null;
  const t = h.target(s.pin, maxY);
  return y !== t ? t : null;
}

export function touchStart(s: EndState, y: number | null): EndState {
  return { ...s, touchY: y ?? 0, ctr: 0, fresh: true };
}

/** Whole reducer (Lean `step`), for the golden replay. */
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
