import { watchHidden } from '../engine.scene/observe';
import { SCENE_ATTR } from '../platform/scene';
import { PERIOD_MS, phase } from './logic';

export const VARIANT = 'offscreen-pause';
export const FLAG = 'platform.sweep:offscreen-pause';

export interface PauseState {
  readonly loc: number;
  readonly clk: number;
  readonly paused: boolean;
  readonly off: number;
}

export const init = (off: number): PauseState => ({ loc: off, clk: 0, paused: false, off });

export function seek(s: PauseState, rep: boolean): PauseState {
  if (rep) return { ...s, paused: true };
  return s.paused ? { ...s, paused: false, loc: s.clk + s.off } : s;
}

export const tick = (s: PauseState, d: number, rep: boolean): PauseState => ({ ...s, clk: s.clk + d, loc: rep ? s.loc : s.loc + d });

export const step = (s: PauseState, d: number, rep: boolean): PauseState => tick(seek(s, rep), d, rep);

export const ticks = (rep: boolean): number => (rep ? 0 : 1);

export const orig = (off: number, ds: readonly number[]): number => off + ds.reduce((a, b) => a + b, 0);

export { PERIOD_MS, phase };

export const reportAction = (paused: boolean, rep: boolean): 'pause' | 'resume' | 'none' => (rep ? (paused ? 'none' : 'pause') : paused ? 'resume' : 'none');

// A script pause overrides the CSS play state for good (WebKit CSSAnimation.cpp:278-287@862f17d).
export interface Held {
  readonly start: CSSNumberish | null;
  readonly cur: number;
  readonly fz: number;
  readonly since: number;
  readonly frozen: boolean;
}

interface ElState {
  paused: boolean;
  readonly held: Map<Animation, Held>;
}

export const holdNew = (held: boolean, running: boolean): boolean => !held && running;

export const close = (h: Held, now: number): Held =>
  h.frozen ? { ...h, fz: h.fz + (now - h.since), since: now } : { ...h, cur: h.cur + (now - h.since), since: now };

export const setScene = (h: Held, now: number, active: boolean): Held => ({ ...close(h, now), frozen: !active });

export const resumeTime = (h: Held, now: number): number => close(h, now).cur;

export const startShift = (h: Held, now: number): number => close(h, now).fz;

export function watchSweepPause(
  els: Element[],
  IO: typeof IntersectionObserver = IntersectionObserver,
  now: () => number = () => performance.now(),
  host: Element | null = null,
  MO: typeof MutationObserver | null = typeof MutationObserver === 'undefined' ? null : MutationObserver,
): () => void {
  const state = new Map<Element, ElState>();
  for (const el of els) state.set(el, { paused: false, held: new Map() });
  const sceneFrozen = () => host?.getAttribute(SCENE_ATTR) === 'paused';
  const hold = (el: Element, st: ElState) => {
    for (const a of el.getAnimations()) {
      if (!holdNew(st.held.has(a), a.playState === 'running')) continue;
      st.held.set(a, { start: a.startTime, cur: Number(a.currentTime ?? 0), fz: 0, since: now(), frozen: sceneFrozen() });
      a.pause();
    }
  };
  const resume = (st: ElState) => {
    for (const [a, h] of st.held) {
      if (a.playState !== 'paused') continue;
      const t = now();
      if (h.start == null) a.currentTime = resumeTime(h, t);
      a.play();
      if (h.start != null) a.startTime = Number(h.start) + startShift(h, t);
    }
    st.held.clear();
  };
  const stop = watchHidden(
    els,
    'rect',
    (el, hidden) => {
      const st = state.get(el);
      if (!st) return;
      const act = reportAction(st.paused, hidden);
      if (act === 'pause') {
        st.paused = true;
        hold(el, st);
      } else if (act === 'resume') {
        resume(st);
        st.paused = false;
      }
    },
    IO,
  );
  const mo = host && MO ? new MO(() => {
    const t = now();
    const active = !sceneFrozen();
    for (const [el, st] of state) {
      for (const [a, h] of st.held) st.held.set(a, setScene(h, t, active));
      if (st.paused) hold(el, st);
    }
  }) : null;
  mo?.observe(host!, { attributes: true, attributeFilter: [SCENE_ATTR] });
  return () => {
    stop();
    mo?.disconnect();
    for (const st of state.values()) if (st.paused) resume(st);
  };
}
