import { DURATION_MS, fade } from '../morph.tween/logic';
import { EASING_CSS, keyframes } from './fade.logic';

export interface FadeAnim {
  startTime: number | null;
  cancel(): void;
}
export interface FadeEl {
  animate(kfs: { offset: number; opacity: number; filter: string }[], opts: { duration: number; easing: string; fill: 'both' }): FadeAnim;
  style: { setProperty(name: string, value: string): void };
}

export interface FadeSink {
  push(from: number, to: number, start: number): void;
  settle(m: number): void;
  dispose(): void;
}

export function createThreadedFade(el: () => FadeEl | null): FadeSink {
  let anim: FadeAnim | null = null;
  const drop = () => {
    anim?.cancel();
    anim = null;
  };
  return {
    push(from, to, start) {
      drop();
      const p = el();
      if (!p) return;
      const kfs = keyframes(from, to).map((k) => ({ offset: k.off, opacity: k.fade, filter: `blur(${k.blur}px)` }));
      anim = p.animate(kfs, { duration: DURATION_MS, easing: EASING_CSS, fill: 'both' });
      anim.startTime = start;
    },
    settle(m) {
      el()?.style.setProperty('--morph-fade', String(fade({ m })));
      drop();
    },
    dispose: drop,
  };
}

export interface TimedAnim {
  readonly playState: string;
  startTime: CSSNumberish | null;
}

export interface FadedHost {
  animations(): readonly TimedAnim[];
  restore(saved: ReadonlyMap<TimedAnim, CSSNumberish>): void;
  svg: { away(): void; back(): void } | null;
}

export interface FadedPause {
  set(zero: boolean): void;
  onScene(v: 'active' | 'paused'): void;
  dispose(): void;
}

export function createFadedPause(host: FadedHost, setFaded: (faded: boolean) => void): FadedPause {
  let faded = false;
  let saved = new Map<TimedAnim, CSSNumberish>();
  const restore = () => {
    if (saved.size === 0) return;
    host.restore(saved);
    saved = new Map();
  };
  return {
    set(zero) {
      if (zero === faded) return;
      faded = zero;
      if (zero) {
        saved = new Map();
        for (const a of host.animations()) if (a.playState === 'running' && a.startTime != null) saved.set(a, a.startTime);
        host.svg?.away();
      } else host.svg?.back();
      setFaded(zero);
    },
    onScene(v) {
      if (v === 'active') restore();
    },
    dispose() {
      if (faded) {
        faded = false;
        host.svg?.back();
        setFaded(false);
      }
      saved = new Map();
    },
  };
}

export interface FadedBus {
  set(zero: boolean): void;
  subscribe(fn: (zero: boolean) => void): () => void;
}

export function createFadedBus(): FadedBus {
  let last = false;
  const subs = new Set<(zero: boolean) => void>();
  return {
    set(zero) {
      if (zero === last) return;
      last = zero;
      for (const f of subs) f(zero);
    },
    subscribe(fn) {
      subs.add(fn);
      if (last) fn(true);
      return () => void subs.delete(fn);
    },
  };
}

export const fadedBus = createFadedBus();
