import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { createPanelEffects, createTweenDriver, type PanelAnim, type PanelEl, type TweenEnv } from '../morph.tween/driver';
import { ease } from '../morph.tween/logic';
import { panelBlurPx, panelOpacity, panelScale } from './logic';
import { caAccepts, DURATION_MS, EASING, EASING_CSS, EFFECT_PROPS, installed, K_A, K_B, keyframes, offsets } from './threaded.logic';

const css = readFileSync(new URL('./morph.module.css', import.meta.url), 'utf8');
const goldenQueries = readFileSync(new URL('../../../../../packages/contracts/golden/parts/morph-panel-threaded.jsonl', import.meta.url), 'utf8')
  .split('\n')
  .filter((l) => l.includes('"fn":"bands"'))
  .map((l) => (JSON.parse(l) as { in: { query: string } }).in.query);
const ANIMATED = ['opacity', 'filter', 'transform'] as const;

function declaredBands(src: string): Record<string, Record<(typeof ANIMATED)[number], boolean>> {
  const out: Record<string, Record<(typeof ANIMATED)[number], boolean>> = {};
  const blank = () => ({ opacity: false, filter: false, transform: false });
  const queries = [...src.matchAll(/^ {2}@media ([^{]+?) \{$/gm)];
  const at = (q: string | null): Record<(typeof ANIMATED)[number], boolean> => (out[q ?? 'base'] ??= blank());
  at(null);
  for (const q of queries) at(q[1]!);
  const bounds = queries.map((q, i) => ({ q: q[1]!, from: q.index!, to: queries[i + 1]?.index ?? src.length }));
  const first = bounds[0]?.from ?? src.length;
  const scan = (text: string, into: Record<(typeof ANIMATED)[number], boolean>) => {
    for (const rule of text.matchAll(/^ {2,4}\.panel \{\n([\s\S]*?)\n {2,4}\}/gm)) {
      for (const p of ANIMATED) if (new RegExp(`^\\s*${p}:`, 'm').test(rule[1]!)) into[p] = true;
    }
  };
  scan(src.slice(0, first), at(null));
  for (const b of bounds) scan(src.slice(b.from, b.to), at(b.q));
  return out;
}

goldenConformance('morph-panel-threaded', {
  const: () => ({ kA: K_A, kB: K_B, blurMax: 12, duration: DURATION_MS, easing: [...EASING] }),
  keyframes: (i) => keyframes(i.from as number, i.to as number).map((k) => ({ off: k.off, opacity: k.opacity, blur: k.blur, scale: k.scale })),
  ca: (i) => {
    const n = offsets(i.from as number, i.to as number).length;
    return { kfs: n, accepts: caAccepts(n) };
  },
  bands: (i) => declaredBands(css)[i.query as string] ?? { opacity: false, filter: false, transform: false },
  installed: (i) => installed(i.reduced as boolean),
  effects: () => EFFECT_PROPS,
});

describe('morph.panel threaded: the CSS has no query the Lean bands do not know', () => {
  it('lists exactly the media queries of the bands', () => {
    expect(Object.keys(declaredBands(css)).sort()).toEqual(goldenQueries.sort());
  });
  it('only the base rule and reduced motion declare the animated properties (bands_equal)', () => {
    const bands = declaredBands(css);
    for (const [q, d] of Object.entries(bands)) {
      if (q === 'base') expect(d).toEqual({ opacity: true, filter: true, transform: true });
      else if (q === '(prefers-reduced-motion: reduce)') expect(d).toEqual({ opacity: false, filter: true, transform: false });
      else expect(d, q).toEqual({ opacity: false, filter: false, transform: false });
    }
  });
});

interface Anim extends PanelAnim {
  kfs: Record<string, number | string>[];
  opts: { duration: number; easing: string; fill: 'both' };
  cancelled: boolean;
}

type Tri = { opacity: number; blur: number; scale: number };

function sampleProp(a: Anim, T: number, key: string, read: (v: number | string) => number): number {
  const p = ease({ x: Math.min(1, Math.max(0, (T - (a.startTime ?? T)) / a.opts.duration)) });
  const i = Math.max(0, a.kfs.findIndex((k) => p <= (k.offset as number)) - 1);
  const [k0, k1] = [a.kfs[i]!, a.kfs[i + 1]!];
  const u = ((p - (k0.offset as number)) / ((k1.offset as number) - (k0.offset as number)));
  const v0 = read(k0[key]!);
  const v1 = read(k1[key]!);
  return v0 + (v1 - v0) * u;
}

const px = (v: number | string) => Number(/blur\((.*)px\)/.exec(String(v))![1]);
const sc = (v: number | string) => Number(/scale\((.*)\)/.exec(String(v))![1]);

type Ev = { wheel: number } | { frame: number } | { reduced: boolean };

function rig(threaded: boolean) {
  let now = 0;
  let reduced = false;
  let morph = 0;
  const frames = new Set<(t: number) => void>();
  let wheel: ((e: { deltaY: number; preventDefault(): void }) => void) | undefined;
  const anims: Anim[] = [];
  const el: PanelEl = {
    animate(kfs, opts) {
      const a: Anim = { kfs: kfs as Anim['kfs'], opts, startTime: null, cancelled: false, cancel: () => void (a.cancelled = true) };
      anims.push(a);
      return a;
    },
  };
  const sink = createPanelEffects(() => el);
  const env: TweenEnv = {
    clock: { subscribe: (tick) => (frames.add(tick), () => void frames.delete(tick)) },
    now: () => now,
    reduced: () => reduced,
    viewportHeight: () => 800,
    platform: () => ({ getBoundingClientRect: () => ({ height: 500, bottom: 800 }), style: { pointerEvents: '', setProperty: () => {} } }),
    scrollY: () => 1200,
    scrollToInstant: () => {},
    addListener: (t, fn) => void (t === 'wheel' && (wheel = fn as never)),
    removeListener: () => {},
    publish: (v) => void (morph = v),
    panel: threaded ? sink : undefined,
  };
  const d = createTweenDriver(env);
  d.setNear(true);
  const shown = (T: number): Tri => {
    const live = anims.filter((a) => !a.cancelled);
    const main = live.find((a) => 'opacity' in a.kfs[0]!);
    const blur = live.find((a) => 'filter' in a.kfs[0]!);
    if (!main || !blur) return { opacity: panelOpacity(morph), blur: panelBlurPx(morph), scale: panelScale(morph) };
    return {
      opacity: sampleProp(main, T, 'opacity', Number),
      scale: sampleProp(main, T, 'transform', sc),
      blur: sampleProp(blur, T, 'filter', px),
    };
  };
  const run = (ev: Ev) => {
    if ('wheel' in ev) wheel?.({ deltaY: ev.wheel, preventDefault: () => {} });
    else if ('reduced' in ev) reduced = ev.reduced;
    else {
      now = ev.frame;
      for (const f of [...frames]) f(ev.frame);
    }
  };
  return { run, shown, anims, sink, setNow: (t: number) => void (now = t) };
}

const ticks = (from: number, to: number) => Array.from({ length: Math.floor((to - from) / 16) + 1 }, (_, k) => ({ frame: from + 16 * k }));
const at = (evs: Ev[]): Array<[number, Ev]> => evs.map((e) => ['frame' in e ? e.frame : 0, e]);

function play(events: Array<[number, Ev]>) {
  const base = rig(false);
  const thr = rig(true);
  const out: Array<{ T: number; base: Tri; thr: Tri }> = [];
  for (const [t, ev] of events) {
    for (const r of [base, thr]) {
      r.setNow(t);
      r.run(ev);
    }
    if ('frame' in ev) out.push({ T: t, base: base.shown(t), thr: thr.shown(t) });
  }
  return { out, base, thr };
}

const same = (o: { T: number; base: Tri; thr: Tri }) => {
  expect(o.thr.opacity, `opacity T=${o.T}`).toBeCloseTo(o.base.opacity, 9);
  expect(o.thr.blur, `blur T=${o.T}`).toBeCloseTo(o.base.blur, 9);
  expect(o.thr.scale, `scale T=${o.T}`).toBeCloseTo(o.base.scale, 9);
};

describe('morph.panel variant threaded (Lean MorphPanelThreaded)', () => {
  it('shows the original opacity, blur and scale on every frame of an open and a close (threaded_eq)', () => {
    const evs: Array<[number, Ev]> = [[3, { wheel: 50 }], ...at(ticks(8, 900)), [905, { wheel: -50 }], ...at(ticks(910, 1800))];
    const { out } = play(evs);
    out.forEach(same);
    expect(out.some((o) => o.base.opacity > 0 && o.base.opacity < 1)).toBe(true);
  });

  it('a retarget mid-push starts its effects at the shown values (retarget_from_shown)', () => {
    const evs: Array<[number, Ev]> = [[3, { wheel: 50 }], ...at(ticks(8, 120)), [130, { wheel: -50 }], ...at(ticks(136, 900))];
    const { out, thr } = play(evs);
    out.forEach(same);
    expect(thr.anims).toHaveLength(4);
    const before = out.findLast((o) => o.T < 130)!.thr;
    expect(thr.anims[2]!.kfs[0]!.opacity).toBeCloseTo(before.opacity, 9);
    expect(px(thr.anims[3]!.kfs[0]!.filter!)).toBeCloseTo(before.blur, 9);
  });

  it('installs two effects per push, the blur alone, with the proved timing', () => {
    const { thr } = play([[3, { wheel: 50 }], ...at(ticks(8, 900))]);
    expect(thr.anims).toHaveLength(2);
    expect(Object.keys(thr.anims[0]!.kfs[0]!).sort()).toEqual(['offset', 'opacity', 'transform']);
    expect(Object.keys(thr.anims[1]!.kfs[0]!).sort()).toEqual(['filter', 'offset']);
    for (const a of thr.anims) {
      expect(a.opts).toEqual({ duration: 680, easing: EASING_CSS, fill: 'both' });
      expect(a.startTime).toBe(3);
    }
    expect(thr.anims.every((a) => a.cancelled)).toBe(true);
  });

  it('a reduced-motion push installs no effect (reduced_no_effect)', () => {
    const evs: Array<[number, Ev]> = [[0, { reduced: true }], [3, { wheel: 50 }], ...at(ticks(8, 100))];
    const { out, thr } = play(evs);
    expect(thr.anims).toHaveLength(0);
    for (const o of out) expect(o.thr).toEqual(o.base);
  });

  it('dispose cancels live effects', () => {
    const r = rig(true);
    r.setNow(3);
    r.run({ wheel: 50 });
    expect(r.anims.filter((a) => !a.cancelled)).toHaveLength(2);
    r.sink.dispose();
    expect(r.anims.every((a) => a.cancelled)).toBe(true);
  });
});
