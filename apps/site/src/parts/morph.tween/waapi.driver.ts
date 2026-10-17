import { active, armed, dir, push, REST, taken, type St } from './logic';
import { navKeyframes, platformKeyframes, settledProps, TIMING, toWaapi } from './waapi.logic';
import type { TouchLike, WheelLike } from './driver';

export interface AnimLike {
  startTime: number | null;
  onfinish: (() => void) | null;
  cancel(): void;
  effect: { getComputedTiming(): { progress: number | null } } | null;
}
export interface AnimTarget {
  animate(keyframes: Record<string, string | number>[], options: typeof TIMING): AnimLike;
}
export interface WaapiEnv {
  /** `document.timeline.currentTime` (premise R5: the clock the frames use; native even when `performance.now()` is shimmed). */
  timelineNow(): number | null;
  reduced(): boolean;
  viewportHeight(): number;
  nav(): AnimTarget | null;
  /** `.start-selling-platform`, looked up each time. */
  platform(): (AnimTarget & { getBoundingClientRect(): { height: number; bottom: number } }) | null;
  scrollY(): number;
  scrollToInstant(top: number): void;
  addListener(type: 'wheel' | 'touchstart' | 'touchmove', fn: (e: never) => void, passive: boolean): void;
  removeListener(type: 'wheel' | 'touchstart' | 'touchmove', fn: (e: never) => void): void;
  /** Write the settled value inline (reduced-motion jump); never per frame. */
  settle(value: number, props: ReturnType<typeof settledProps>): void;
  /** Publish `data-fw-morph` at the start and the end of a tween only. */
  hint(value: number): void;
  /** The platform needs its fade expression (idempotent). */
  preparePlatform?(): void;
  onActivate?(): void;
}

/**
 * The `waapi` driver: the same decisions as the faithful driver (logic.ts: dir, taken, armed, push), but the tween is
 * one Web Animations animation per element (nav: `--morph` and the two flags; platform: `--morph` and the pointer cut)
 * with `startTime = document.timeline.currentTime` read at the push (R5). No rAF subscription and no style write per
 * frame. The running value is read from the animation's computed progress, only at a push or a listener decision. A
 * retarget cancels the old animations and starts from that value; reduced motion cancels and jumps.
 */
export function createWaapiDriver(env: WaapiEnv) {
  let st: St = REST;
  let near = false;
  let attached = false;
  let touchY = 0;
  let pinned = env.scrollY();
  let anims: AnimLike[] = [];
  let flight = false;

  const valueNow = (): number => {
    if (!flight) return st.value;
    const p = anims[0]?.effect?.getComputedTiming().progress;
    const q = p === null || p === undefined ? 1 : Math.min(1, Math.max(0, p));
    return st.from + (st.to - st.from) * q;
  };
  const isActive = () => active({ target: st.target, value: valueNow() });
  const isArmed = () => {
    const p = env.platform();
    if (!p) return false;
    const r = p.getBoundingClientRect();
    return armed({ rectHeight: r.height, rectBottom: r.bottom, viewportHeight: env.viewportHeight() });
  };
  const takenFor = (delta: number) => taken({ active: isActive(), delta, armed: delta > 0 && !isActive() ? isArmed() : false });

  const onWheel = (e: WheelLike) => {
    if (!takenFor(e.deltaY)) return;
    if (!isActive()) pinned = env.scrollY();
    e.preventDefault();
    push_(e.deltaY);
  };
  const onTouchStart = (e: TouchLike) => {
    touchY = e.touches[0]?.clientY ?? 0;
  };
  const onTouchMove = (e: TouchLike) => {
    const y = e.touches[0]?.clientY ?? touchY;
    const delta = touchY - y;
    touchY = y;
    if (!takenFor(delta)) return;
    if (!isActive()) pinned = env.scrollY();
    e.preventDefault();
    push_(delta);
  };
  const attach = () => {
    if (attached) return;
    attached = true;
    env.addListener('wheel', onWheel as (e: never) => void, false);
    env.addListener('touchstart', onTouchStart as (e: never) => void, true);
    env.addListener('touchmove', onTouchMove as (e: never) => void, false);
  };
  const detach = () => {
    if (!attached) return;
    attached = false;
    env.removeListener('wheel', onWheel as (e: never) => void);
    env.removeListener('touchstart', onTouchStart as (e: never) => void);
    env.removeListener('touchmove', onTouchMove as (e: never) => void);
  };
  const arm = () => (near || isActive() ? attach() : detach());

  const cancelAll = () => {
    for (const a of anims) {
      a.onfinish = null;
      a.cancel();
    }
    anims = [];
  };
  const settleFlight = () => {
    flight = false;
    st = { ...st, value: st.to, pending: false };
    env.hint(st.value);
    if (!isActive()) arm();
  };

  function push_(delta: number) {
    const goal = dir({ delta });
    if (goal === null) return;
    const reduced = env.reduced();
    if (push({ state: st, goal, reduced, now: 0 }) === st) return; // already heading there (N2:13037)
    const cur = valueNow();
    const next = push({ state: { ...st, value: cur }, goal, reduced, now: 0 });
    env.onActivate?.();
    env.preparePlatform?.();
    cancelAll();
    st = next;
    if (reduced) {
      flight = false;
      env.settle(st.value, settledProps(st.value));
      if (!isActive()) arm();
      return;
    }
    const t = env.timelineNow();
    const nav = env.nav();
    const platform = env.platform();
    if (nav) anims.push(nav.animate(toWaapi(navKeyframes({ from: st.from, to: st.to })), TIMING));
    if (platform) anims.push(platform.animate(toWaapi(platformKeyframes({ from: st.from, to: st.to })), TIMING));
    if (t !== null) for (const a of anims) a.startTime = t;
    const first = anims[0];
    if (!first) return settleFlight();
    flight = true;
    env.hint(st.from);
    first.onfinish = () => {
      if (anims[0] === first) settleFlight();
    };
  }

  return {
    /** The platform entered or left its 200 % margin (IntersectionObserver). */
    setNear(isNear: boolean) {
      near = isNear;
      if (near) {
        env.onActivate?.();
        env.preparePlatform?.();
      }
      arm();
    },
    /** Called every scroll frame: while the morph runs, put the page back where the push began (N2:13077-13079). */
    pin() {
      if (isActive() && env.scrollY() !== pinned) env.scrollToInstant(pinned);
    },
    state: () => ({ ...st, value: valueNow() }),
    attached: () => attached,
    animations: () => anims.slice(),
    dispose() {
      cancelAll();
      flight = false;
      detach();
    },
  };
}

export type WaapiDriver = ReturnType<typeof createWaapiDriver>;
