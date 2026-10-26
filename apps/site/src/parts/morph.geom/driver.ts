/**
 * Driver of morph.geom:on (no DOM): follows today's tween. The first `--morph` above 0 enters the flip (layer tree, one
 * paused Web Animation per track); each later value only writes `currentTime`; a value of 0 takes the tree down. Track
 * domain: m tracks use duration 1000 and currentTime = 1000 m; the 60 Hz time tracks use duration TIME_END and
 * currentTime = the tween time that shows m (TS stand-in: valid for a push from 0 toward 1; a reversal is
 * morph-timed's job).
 */
import { DURATION_MS } from '../morph.tween/logic';
import { buildAnims, keyframes, TIME_END, type Anim, type Kf, type Layout, type Vp } from './tracks';

export const M_DURATION = 1000;

export interface AnimHandle {
  currentTime: number;
  cancel(): void;
}

export interface GeomEnv {
  /** the faithful fallbacks: not on dark, or reduced motion */
  allowed(): boolean;
  enter(): { vp: Vp; layout: Layout };
  leave(): void;
  /** create a paused effect on the element of `a`; null when the element is absent */
  animate(a: Anim, kf: Kf[], duration: number): AnimHandle | null;
}

/** Tween time that shows m for an open push (inverse of `1 - (1 - i)^3`), in ms. */
export const timeOf = (m: number): number => Math.min(TIME_END, DURATION_MS * (1 - Math.cbrt(1 - Math.min(1, Math.max(0, m)))));

export function createGeomDriver(env: GeomEnv) {
  let live: { a: Anim; h: AnimHandle }[] | null = null;
  return {
    apply(m: number): void {
      if (live === null) {
        if (!(m > 0) || !env.allowed()) return;
        const { vp, layout } = env.enter();
        live = [];
        for (const a of buildAnims(vp, layout)) {
          const h = env.animate(a, keyframes(a), a.ks === 'time' ? TIME_END : M_DURATION);
          if (h) live.push({ a, h });
        }
      }
      if (!(m > 0)) {
        for (const { h } of live) h.cancel();
        live = null;
        env.leave();
        return;
      }
      const t = timeOf(m);
      for (const { a, h } of live) h.currentTime = a.ks === 'time' ? t : m * M_DURATION;
    },
    active: () => live !== null,
    dispose(): void {
      if (live) for (const { h } of live) h.cancel();
      if (live) env.leave();
      live = null;
    },
  };
}
