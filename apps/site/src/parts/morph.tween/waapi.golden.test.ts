// Conformance of the `waapi` variant with the Lean golden files (lean/Fw/Parts/MorphTweenOpt.lean).
// - packages/contracts/golden/parts/morph-tween-waapi.jsonl: the 11 engine-check rows of `goldenRows` (written by `goldenJsonl`).
//   Each row's prediction is checked against what the variant does (script `<o`: no rAF subscription; the other stages `=o`:
//   it animates exactly the properties the original writes, R2); the row set and the flag string are pinned.
// - packages/contracts/golden/parts/morph.tween.jsonl: Lean `ease` samples. The effect's cubic-bezier (parsed from the
//   variant's EASING string) must give them (MT1 `bezier_eq_ease`), and every flag keyframe must flip on the same
//   sample as the original's strict test, except at the exact tie (MT4 `flags_same_frame`).
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { decodeRat } from '../../engine/golden.testutil';
import { ease } from './logic';
import { faithfulSubscribes, waapiRun } from './waapi.fake.testutil';
import { EASING, FADE_CSS, flagOffset, navKeyframes, PROP_DARK, PROP_EXPANDED, PROP_MORPH, platformKeyframes, THETA_DARK, THETA_EXPANDED, THETA_POINTER } from './waapi.logic';

const golden = (name: string) =>
  readFileSync(new URL(`../../../../../packages/contracts/golden/parts/${name}.jsonl`, import.meta.url), 'utf8')
    .split('\n')
    .filter((l) => l.trim() !== '')
    .map((l) => decodeRat(JSON.parse(l)) as Record<string, unknown>);

interface Row {
  base: string;
  countType: string;
  engine: string;
  prediction: string;
  scenario: string;
  stage: string;
  variant: string;
}
const rows = golden('morph-tween-waapi') as unknown as Row[];

describe('morph.tween:waapi vs morph-tween-waapi.jsonl', () => {
  it('has the 11 rows of the variant, all for the flag', () => {
    expect(rows).toHaveLength(11);
    for (const r of rows) expect(['rewrite+?fw=morph.tween:waapi', 'rewrite']).toContain(r.variant);
    expect(rows.filter((r) => r.variant === 'rewrite+?fw=morph.tween:waapi')).toHaveLength(10);
  });

  it('script rows (`<o`): the variant subscribes no frame callback, the faithful driver does', () => {
    const w = waapiRun();
    expect(w.wheel(100)).toBe(true);
    expect(w.calls.length).toBeGreaterThan(0);
    expect(w.clockSubscribes()).toBe(0);
    expect(faithfulSubscribes()).toBeGreaterThan(0);
    const script = rows.filter((r) => r.stage === 'script');
    expect(script.map((r) => r.engine).sort()).toEqual(['chromium', 'webkit']);
    for (const r of script) expect(r.prediction).toBe('<o');
  });

  it('style, layout, paint, commit rows (`=o`): the animated properties are the ones the original writes (R2)', () => {
    const eq = rows.filter((r) => ['style', 'layout', 'paint', 'commit'].includes(r.stage));
    expect(eq).toHaveLength(8);
    for (const r of eq) expect(r.prediction).toBe('=o');
    const navProps = new Set(navKeyframes({ from: 0, to: 1 }).flatMap((k) => Object.keys(k.props)));
    const platformProps = new Set(platformKeyframes({ from: 0, to: 1 }).flatMap((k) => Object.keys(k.props)));
    expect([...navProps].sort()).toEqual([PROP_DARK, PROP_EXPANDED, PROP_MORPH].sort());
    expect([...platformProps].sort()).toEqual(['pointerEvents', PROP_MORPH].sort());
    expect(FADE_CSS).toBe('calc(1 - min(1, var(--morph) / 0.55))');
  });

  it('the bit-13 row (rewrite vs variant, `<o` compositeFailedBits): a custom-property animation is main thread, the variant adds none', () => {
    const bit = rows.filter((r) => r.stage === 'comp');
    expect(bit).toHaveLength(1);
    expect(bit[0]).toMatchObject({ base: 'rewrite+?fw=morph.tween:waapi', variant: 'rewrite', prediction: '<o', engine: 'chromium' });
    // the variant animates no compositable property: only custom properties and pointer-events
    const all = [...navKeyframes({ from: 0, to: 1 }), ...platformKeyframes({ from: 0, to: 1 })].flatMap((k) => Object.keys(k.props));
    for (const p of all) expect(['--morph', '--fw-morph-dark', '--fw-morph-expanded', 'pointerEvents']).toContain(p);
  });
});

/** The cubic-bezier of an EASING string, solved by bisection (independent of the engines' Newton steps). */
function bezierOf(easing: string): (x: number) => number {
  const m = /^cubic-bezier\(([^,]+),([^,]+),([^,]+),([^)]+)\)$/.exec(easing);
  if (!m) throw new Error(`not a cubic-bezier: ${easing}`);
  const [x1, y1, x2, y2] = m.slice(1).map(Number) as [number, number, number, number];
  const b = (a: number, c: number, s: number) => 3 * a * s * (1 - s) ** 2 + 3 * c * s * s * (1 - s) + s ** 3;
  return (x) => {
    let lo = 0;
    let hi = 1;
    for (let i = 0; i < 80; i++) {
      const mid = (lo + hi) / 2;
      if (b(x1, x2, mid) < x) lo = mid;
      else hi = mid;
    }
    return b(y1, y2, (lo + hi) / 2);
  };
}

describe('morph.tween:waapi easing and flag keyframes vs the Lean ease samples', () => {
  const samples = golden('morph.tween').filter((l) => l.fn === 'ease') as unknown as { in: { x: number }; out: number }[];
  const bez = bezierOf(EASING);

  it('the effect easing gives the Lean ease on every sample (MT1)', () => {
    expect(samples.length).toBeGreaterThanOrEqual(8);
    for (const s of samples) {
      const x = Math.min(1, Math.max(0, s.in.x));
      expect(Math.abs(bez(x) - s.out), `x=${s.in.x}`).toBeLessThanOrEqual(1e-9);
      expect(ease({ x: s.in.x })).toBeCloseTo(s.out, 9);
    }
  });

  const cases: { name: string; theta: number; from: number; to: number }[] = [];
  for (const [name, theta] of [['dark', THETA_DARK], ['expanded', THETA_EXPANDED], ['pointer', THETA_POINTER]] as const)
    for (const [from, to] of [[0, 1], [1, 0], [0.3, 1], [0.9, 0], [0, 0.1], [1, 1], [0, 0], [0.5, 0.5], [0.15, 0.25]] as const) cases.push({ name, theta, from, to });

  it('each flag flips on the sample where the original test `from + (to - from) * ease(x) > theta` flips (MT4)', () => {
    let checked = 0;
    for (const c of cases) {
      const off = flagOffset({ theta: c.theta, from: c.from, to: c.to });
      expect(off).toBeGreaterThanOrEqual(0);
      expect(off).toBeLessThanOrEqual(1);
      for (const s of samples) {
        const x = Math.min(1, Math.max(0, s.in.x));
        const p = bez(x);
        if (Math.abs(p - off) < 1e-9) continue; // the exact tie: engines flip at p >= offset (R3b), covered below
        const original = c.from + (c.to - c.from) * s.out > c.theta;
        const a = c.from > c.theta;
        const b = c.to > c.theta;
        const variant = p < off ? a : b;
        expect(variant, `${c.name} ${c.from}->${c.to} x=${s.in.x}`).toBe(original);
        checked++;
      }
    }
    expect(checked).toBeGreaterThan(100);
  });

  it('the keyframe quadruple is [0: a, c: a, c: b, 1: b], sorted, and ties flip (p >= c gives b)', () => {
    const kfs = navKeyframes({ from: 0, to: 1 });
    const dark = kfs.filter((k) => PROP_DARK in k.props);
    expect(dark.map((k) => k.offset)).toEqual([0, 0.2, 0.2, 1]);
    expect(dark.map((k) => k.props[PROP_DARK])).toEqual(['0', '0', '1', '1']);
    const exp = kfs.filter((k) => PROP_EXPANDED in k.props);
    expect(exp.map((k) => k.offset)).toEqual([0, 0.92, 0.92, 1]);
    expect(kfs.map((k) => k.offset)).toEqual([...kfs.map((k) => k.offset)].sort((a, b) => a - b));
    const falling = platformKeyframes({ from: 1, to: 0 }).filter((k) => 'pointerEvents' in k.props);
    expect(falling.map((k) => k.props.pointerEvents)).toEqual(['none', 'none', 'auto', 'auto']);
    expect(falling[1]!.offset).toBeCloseTo(1 - 0.5225, 12);
    // flat animation: offset 0 (Lean x / 0 = 0), constant flag
    expect(flagOffset({ theta: 0.2, from: 1, to: 1 })).toBe(0);
  });
});
