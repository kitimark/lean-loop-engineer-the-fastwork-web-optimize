import { EASING_CSS as PANEL_EASING_CSS, effects as panelEffects } from '../morph.panel/threaded.logic';
import { active, armed, DURATION_MS, fade, frame, pointerNone, REST, type St } from './logic';
import { BASE, frameOut, hold, initEnd, moveStep, touchStart, type EndState, type Hooks, type Read } from './end.logic';
import { setRest, type RestEl } from '../morph.panel/rest.logic';
import { lockWrite, readsAt } from './scroll-lock.logic';

export interface PlatformEl {
  getBoundingClientRect(): { height: number; bottom: number };
  style: { pointerEvents: string; setProperty(name: string, value: string): void };
  hasAttribute?(name: string): boolean;
  toggleAttribute?(name: string, force: boolean): boolean;
}
export interface WheelLike {
  deltaY: number;
  cancelable?: boolean;
  readonly defaultPrevented: boolean;
  preventDefault(): void;
}
export interface TouchLike {
  touches: ArrayLike<{ clientY: number }>;
  cancelable?: boolean;
  readonly defaultPrevented: boolean;
  preventDefault(): void;
}
export interface TweenEnv {
  clock: { subscribe(tick: (t: number) => void, opts?: { own?: boolean }): () => void };
  /** `performance.now()` at the moment of a push (the start of the tween). */
  now(): number;
  /** `prefers-reduced-motion: reduce`, read at each push. */
  reduced(): boolean;
  /** `visualViewport.height`, else `innerHeight` (N2:13067). */
  viewportHeight(): number;
  platform(): PlatformEl | null;
  scrollY(): number;
  maxScrollY?(): number;
  scrollToInstant(top: number): void;
  addListener(type: 'wheel' | 'touchstart' | 'touchmove', fn: (e: never) => void, passive: boolean): void;
  removeListener(type: 'wheel' | 'touchstart' | 'touchmove', fn: (e: never) => void): void;
  /** The morph value, once per frame and per jump: the nav publishes it as `--morph`. */
  publish(value: number): void;
  /** The panel may mount: first intersection or first push (N2:13040 and 13076 `z(b, !0)`). */
  onActivate?(): void;
  lock?: { overlay(): boolean; set(on: boolean): void };
  fade?: EffectSink;
  rest?: boolean;
  panel?: EffectSink;
  hooks?: Hooks;
}

export interface EffectSink {
  push(from: number, to: number, start: number): void;
  settle(m: number): void;
  dispose(): void;
}

export interface PanelAnim {
  startTime: number | null;
  cancel(): void;
}
export interface PanelEl {
  animate(kfs: object[], opts: { duration: number; easing: string; fill: 'both' }): PanelAnim;
}

export function createPanelEffects(el: () => PanelEl | null): EffectSink {
  let live: PanelAnim[] = [];
  const drop = () => {
    for (const a of live) a.cancel();
    live = [];
  };
  return {
    push(from, to, start) {
      drop();
      const p = el();
      if (!p) return;
      const fx = panelEffects(from, to);
      const opts = { duration: DURATION_MS, easing: PANEL_EASING_CSS, fill: 'both' } as const;
      live = [p.animate(fx.main, opts), p.animate(fx.blur, opts)];
      for (const a of live) a.startTime = start;
    },
    settle: drop,
    dispose: drop,
  };
}

/**
 * The faithful driver (N2:12999-13089): a state machine of the tween, the two scroll-jacking listeners (wheel,
 * touchstart/touchmove: capture and non-passive, so they can `preventDefault`) and the scroll pin. Decisions are the
 * pure functions in logic.ts (Lean `MorphTween`); this file only wires them to the environment. Listeners are armed
 * while the platform is within 200 % of the viewport (`setNear`) or the morph is active, and released only between
 * frames of an inactive morph (`C() || I()` in the original). Every frame is one rAF registration of its own
 * (`n = requestAnimationFrame(T)`), cancelled and replaced on a retarget.
 */
export function createTweenDriver(env: TweenEnv) {
  let st: St = REST;
  let near = false;
  let attached = false;
  const hooks = env.hooks ?? BASE;
  let end: EndState = initEnd(env.scrollY(), st);
  let cancelFrame: (() => void) | null = null;
  let locked = false;
  let overlay = false;

  const isActive = () => active({ target: st.target, value: st.value });
  const readOverlay = (was: boolean, now: boolean) => {
    if (env.lock && readsAt(was, now)) overlay = env.lock.overlay();
  };
  const syncLock = () => {
    if (!env.lock) return;
    const w = lockWrite(overlay, locked, isActive());
    if (w === null) return;
    locked = w;
    env.lock.set(w);
  };
  const updateFade = () => {
    const p = env.platform();
    if (!p) return;
    if (!env.fade) p.style.setProperty('--morph-fade', String(fade({ m: st.value })));
    p.style.pointerEvents = pointerNone({ m: st.value }) ? 'none' : '';
    if (env.rest && p.hasAttribute && p.toggleAttribute) setRest(p as RestEl, st.value);
  };
  const isArmed = () => {
    const p = env.platform();
    if (!p) return false;
    const r = p.getBoundingClientRect();
    return armed({ rectHeight: r.height, rectBottom: r.bottom, viewportHeight: env.viewportHeight() });
  };
  const move = (e: { preventDefault(): void; cancelable?: boolean; readonly defaultPrevented: boolean }, delta: number) => {
    const cancelable = e.cancelable !== false;
    const read: Read = {
      cancelable,
      get scrollY() {
        return env.scrollY();
      },
      arm: delta > 0 && !isActive() ? isArmed() : false,
      get now() {
        return env.now();
      },
      get reduced() {
        return env.reduced();
      },
    };
    const [next, out] = moveStep(hooks, { ...end, tw: st }, delta, read);
    if (out.prevent && cancelable) e.preventDefault();
    end = hold(hooks, next, e.defaultPrevented, () => read.scrollY);
    if (out.goal !== null) apply(next.tw);
  };
  const onWheel = (e: WheelLike) => move(e, e.deltaY);
  const onTouchStart = (e: TouchLike) => {
    end = touchStart(end, e.touches[0]?.clientY ?? null);
  };
  const onTouchMove = (e: TouchLike) => {
    const y = e.touches[0]?.clientY ?? end.touchY;
    const delta = end.touchY - y;
    end = { ...end, touchY: y };
    move(e, delta);
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

  const tick = (t: number) => {
    const was = isActive();
    st = frame({ state: st, now: t });
    readOverlay(was, isActive());
    if (!st.pending) {
      cancelFrame?.();
      cancelFrame = null;
      env.fade?.settle(st.value);
      env.panel?.settle(st.value);
    }
    env.publish(st.value);
    updateFade();
    syncLock();
    if (!isActive()) arm();
  };

  function apply(next: St) {
    if (next === st) return;
    const reduced = env.reduced();
    readOverlay(isActive(), active({ target: next.target, value: next.value }));
    env.onActivate?.();
    st = next;
    syncLock();
    if (reduced) {
      cancelFrame?.();
      cancelFrame = null;
      env.fade?.settle(st.value);
      env.panel?.settle(st.value);
      env.publish(st.value);
      updateFade();
      if (!isActive()) arm();
      return;
    }
    env.fade?.push(st.from, st.to, st.start);
    env.panel?.push(st.from, st.to, st.start);
    cancelFrame?.();
    cancelFrame = env.clock.subscribe(tick, { own: true });
  }

  return {
    /** The platform entered or left its 200 % margin (IntersectionObserver). */
    setNear(isNear: boolean) {
      near = isNear;
      if (near) env.onActivate?.();
      arm();
    },
    pin() {
      if (!isActive()) return;
      const to = frameOut(hooks, { ...end, tw: st }, env.scrollY(), () => env.maxScrollY?.() ?? Infinity);
      if (to !== null) env.scrollToInstant(to);
    },
    state: () => st,
    attached: () => attached,
    dispose() {
      cancelFrame?.();
      cancelFrame = null;
      env.fade?.dispose();
      env.panel?.dispose();
      if (locked) {
        locked = false;
        env.lock?.set(false);
      }
      detach();
    },
  };
}

export type TweenDriver = ReturnType<typeof createTweenDriver>;
