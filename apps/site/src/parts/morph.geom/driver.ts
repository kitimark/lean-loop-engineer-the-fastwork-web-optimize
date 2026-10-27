import { DURATION_MS } from '../morph.tween/logic';
import { buildAnims, keyframes, TIME_END, type Anim, type Kf, type Layout, type Vp } from './tracks';

export const M_DURATION = 1000;

export interface AnimHandle {
  currentTime: number;
  cancel(): void;
}

export interface GeomEnv {
  allowed(): boolean;
  enter(): { vp: Vp; layout: Layout };
  leave(): void;
  animate(a: Anim, kf: Kf[], duration: number): AnimHandle | null;
}

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
