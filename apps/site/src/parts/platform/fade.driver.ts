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
  /** The section's CSS animations; the call also flushes style, so the scene attribute is applied by the time it returns. */
  animations(): readonly TimedAnim[];
  /** The dash svgs' SMIL clock (platform.glint pause), or null. */
  svg: { away(): void; back(): void } | null;
}

export interface FadedPause {
  set(zero: boolean): void;
  /** The scene writer's report of each value it wrote. */
  onScene(v: 'active' | 'paused'): void;
  dispose(): void;
}

/**
 * platform:faded-pause. While the morph fade is 0 the section is paused (the scene writer's faded input and the SMIL
 * clocks). The CSS animations' start times are saved at the pause and put back once the scene value is `active`
 * again, so every running animation reads the phase it would have had (Lean `visible_phase`); a finished animation
 * (settled entry) is left alone. The SMIL clock goes through the glint pause (Lean `glint_phase`).
 */
export function createFadedPause(host: FadedHost, setFaded: (faded: boolean) => void): FadedPause {
  let faded = false;
  let saved: Array<[TimedAnim, CSSNumberish]> = [];
  const restore = () => {
    if (saved.length === 0) return;
    host.animations();
    for (const [a, s] of saved) a.startTime = s;
    saved = [];
  };
  return {
    set(zero) {
      if (zero === faded) return;
      faded = zero;
      if (zero) {
        saved = [];
        for (const a of host.animations()) if (a.playState === 'running' && a.startTime != null) saved.push([a, a.startTime]);
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
      saved = [];
    },
  };
}

export interface FadedBus {
  set(zero: boolean): void;
  subscribe(fn: (zero: boolean) => void): () => void;
}

/** The tween's fade-zero edge to the platform section (the last value is replayed to a late subscriber). */
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
