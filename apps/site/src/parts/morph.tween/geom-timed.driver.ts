import { buildAnims, cssValue, evalAt, selector, type Anim, type Kf, type Layout, type Vp } from '../morph.geom/tracks';
import { DURATION_MS } from './logic';
import { EASING_CSS, rebase, timeKnots, type Knots } from './geom-timed.logic';
import type { EffectSink } from './driver';

export interface TimedAnim {
  startTime: number | null;
  cancel(): void;
  pause(): void;
}
export interface TimedOpts {
  duration: number;
  easing: string;
  fill: 'backwards' | 'both';
}
export interface TimedEnv {
  allowed(): boolean;
  enter(): { vp: Vp; layout: Layout };
  leave(): void;
  fresh(vp: Vp): boolean;
  animate(a: Anim, kf: Kf[], opts: TimedOpts): TimedAnim | null;
  goal(rules: string | null): void;
}

const PROP: Record<string, string> = { backdropFilter: 'backdrop-filter' };

export function pushKeyframes(a: Anim, m0: number, g: number): { kf: Kf[]; easing: string } {
  const time = a.ks === 'time';
  const xs = a.offsets;
  const parts: Knots[] = a.values.map((ys, i) => (time ? timeKnots(a, i, m0, g) : rebase(xs, ys, m0, g)));
  const offsets = parts[0].offsets;
  const kf = offsets.map((offset, k) => ({ offset, [a.prop]: cssValue(a.prop, parts.map((p) => p.values[k])) }));
  return { kf, easing: time ? 'linear' : EASING_CSS };
}

export const GOAL_ATTR = 'data-mg-goal';
export function goalRules(anims: Anim[]): string {
  const by = new Map<string, string[]>();
  for (const a of anims) {
    const x = a.ks === 'time' ? DURATION_MS : 1;
    const v = cssValue(a.prop, a.values.map((_, f) => evalAt(a, f, x)));
    const s = selector(a);
    by.set(s, [...(by.get(s) ?? []), `${PROP[a.prop] ?? a.prop}:${v}`]);
  }
  return [...by].map(([s, d]) => `html[${GOAL_ATTR}] ${s}{${d.join(';')}}`).join('');
}

export type TimedGeom = EffectSink & {
  take(from: number, to: number, start: number): boolean;
  warm(): void;
  cool(): void;
  live(): boolean;
  held(): boolean;
};

export function createTimedGeom(env: TimedEnv): TimedGeom {
  let anims: Anim[] | null = null;
  let live: TimedAnim[] = [];
  let held: Vp | null = null;
  const drop = () => {
    for (const h of live) h.cancel();
    live = [];
  };
  const leave = () => {
    drop();
    if (anims) {
      env.goal(null);
      env.leave();
    }
    anims = null;
    held = null;
  };
  const create = (from: number, to: number, start: number | null) => {
    const fill = to === 1 ? 'backwards' : 'both';
    for (const a of anims ?? []) {
      const { kf, easing } = pushKeyframes(a, from, to);
      const h = env.animate(a, kf, { duration: DURATION_MS, easing, fill });
      if (!h) continue;
      if (start === null) h.pause();
      else h.startTime = start;
      live.push(h);
    }
  };
  const warm = () => {
    if (anims !== null) return;
    const { vp, layout } = env.enter();
    anims = buildAnims(vp, layout);
    held = vp;
    create(0, 1, null);
  };
  const take = (from: number, to: number, start: number): boolean => {
    if (held !== null) {
      const vp = held;
      if (!env.allowed() || !env.fresh(vp)) leave();
      else if (from === 0 && to === 1) {
        held = null;
        env.goal(goalRules(anims ?? []));
        for (const h of live) h.startTime = start;
        return true;
      } else held = null;
    }
    if (anims === null) {
      if (!env.allowed()) return false;
      const { vp, layout } = env.enter();
      anims = buildAnims(vp, layout);
    }
    drop();
    env.goal(to === 1 ? goalRules(anims) : null);
    create(from, to, start);
    return true;
  };
  return {
    take,
    warm,
    cool: () => {
      if (held !== null) leave();
    },
    push: (f, t, s) => void take(f, t, s),
    live: () => anims !== null,
    held: () => held !== null,
    settle(m) {
      if (anims === null) return;
      if (held === null && m > 0) drop();
      else leave();
    },
    dispose: leave,
  };
}
