// Conformance of the `waapi` variant with the Lean golden files (lean/Fw/Parts/MorphTweenOpt.lean).
// - packages/contracts/golden/parts/morph-tween-waapi.jsonl (`goldenJsonl`): the 11 engine-check rows of `goldenRows`,
//   then the 4 `registrations` and the 7 `readers` of MT-R (REGISTRATIONS must equal them; the CSS readers must be listed),
//   then the 5 `registrationsScoped` and 7 `readersScoped` of the `waapi-scoped` arm, tagged `arm`.
//   Each row's prediction is checked against what the variant does (script `<o`: no rAF subscription; the other stages `=o`:
//   it animates exactly the properties the original writes, R2); the row set and the flag string are pinned.
// - packages/contracts/golden/parts/morph.tween.jsonl: Lean `ease` samples. The effect's cubic-bezier (parsed from the
//   variant's EASING string) must give them (MT1 `bezier_eq_ease`), and every flag keyframe must flip on the same
//   sample as the original's strict test, except at the exact tie (MT4 `flags_same_frame`).
// - packages/contracts/golden/parts/morph-tween-waapi.attr.jsonl (`attrJsonl`): the readers of `data-fw-morph`, the
//   marker rows (TS delay at most Lean `dlLo`, so sound, and within 2 ms of it) and two replayed histories; the driver's
//   written attribute must be in the band of the original's value after every frame (Lean `attr_band`).
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { decodeRat } from '../../engine/golden.testutil';
import { ease } from './logic';
import { faithfulSubscribes, waapiRun } from './waapi.fake.testutil';
import { ATTR_READERS, band, EASING, FADE_CSS, hasMarker, MARKER_THETAS, markerDelay, fadeCss, flagOffset, navKeyframes, PROP_DARK, PROP_EXPANDED, PROP_FADE, PROP_MORPH, PROP_PLATFORM, platformKeyframes, REGISTRATIONS, REGISTRATIONS_SCOPED, settledProps, THETA_DARK, THETA_EXPANDED, THETA_POINTER, type Registration } from './waapi.logic';

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
const all = golden('morph-tween-waapi');
const rows = all.filter((r) => 'prediction' in r) as unknown as Row[];
type ReaderRow = { prop: string; sel: string; depth: number };
const regRows = all.filter((r) => 'syntax' in r && !('arm' in r)) as unknown as Registration[];
const readerRows = all.filter((r) => 'sel' in r && !('arm' in r)) as unknown as ReaderRow[];
const untag = ({ arm: _arm, ...r }: Record<string, unknown>) => r;
const scopedRegRows = all.filter((r) => 'syntax' in r && r.arm === 'waapi-scoped').map(untag) as unknown as Registration[];
const scopedReaderRows = all.filter((r) => 'sel' in r && r.arm === 'waapi-scoped').map(untag) as unknown as ReaderRow[];

/** CSS-module classes whose rules read `var(prop)`: the last class of each selector of each innermost rule. */
function cssReaders(file: string, prop: string): Set<string> {
  const css = readFileSync(new URL(file, import.meta.url), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const out = new Set<string>();
  for (const m of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    if (!m[2]!.includes(`var(${prop})`)) continue;
    for (const sel of m[1]!.split(',')) {
      const classes = [...sel.replace(/:global\([^)]*\)/g, '').matchAll(/\.([A-Za-z_][\w-]*)/g)];
      const last = classes.at(-1)?.[1];
      if (last) out.add(last);
    }
  }
  return out;
}

describe('morph.tween:waapi registrations vs morph-tween-waapi.jsonl (MT-R)', () => {
  it('REGISTRATIONS equal the Lean registrations, in order', () => {
    expect(regRows).toHaveLength(4);
    expect(REGISTRATIONS.map((r) => ({ ...r }))).toEqual(regRows);
  });

  it('a property inherits iff a reader sits below the element that sets it or the original inherits it (Lean registrations_rule)', () => {
    expect(readerRows).toHaveLength(7);
    const origInherits = new Set([PROP_MORPH, PROP_FADE]);
    for (const r of REGISTRATIONS) expect(r.inherits, r.name).toBe(readerRows.some((q) => q.prop === r.name && q.depth > 0) || origInherits.has(r.name));
    expect(REGISTRATIONS.find((r) => r.name === PROP_MORPH)?.inherits).toBe(true);
    expect(REGISTRATIONS.find((r) => r.name === PROP_FADE)).toEqual({ name: PROP_FADE, syntax: '<number>', inherits: true, initialValue: '1' });
  });

  it('every CSS reader of --morph in the nav and the panel is a Lean reader (no reader missing from the rule)', () => {
    const lean = new Set(readerRows.filter((q) => q.prop === PROP_MORPH).map((q) => q.sel));
    const found = new Set([...cssReaders('../nav/nav.module.css', PROP_MORPH), ...cssReaders('../morph.panel/morph.module.css', PROP_MORPH)]);
    expect([...found].sort()).toEqual(['actions', 'earn', 'logo', 'nav', 'panel']);
    for (const s of found) expect(lean.has(s), s).toBe(true);
    expect([...cssReaders('../platform/platform.module.css', PROP_FADE)]).toEqual(['section']);
    expect(readerRows.filter((q) => q.prop === PROP_FADE)).toEqual([{ prop: PROP_FADE, sel: 'section', depth: 0 }]);
    for (const p of [PROP_DARK, PROP_EXPANDED]) {
      expect(cssReaders('../nav/nav.module.css', p).size + cssReaders('../morph.panel/morph.module.css', p).size, p).toBe(0);
      expect(readerRows.some((q) => q.prop === p)).toBe(false);
    }
  });
});

describe('morph.tween:waapi-scoped registrations vs morph-tween-waapi.jsonl (MT-R scoped arm)', () => {
  it('REGISTRATIONS_SCOPED equal the Lean registrationsScoped, in order', () => {
    expect(scopedRegRows).toHaveLength(5);
    expect(REGISTRATIONS_SCOPED.map((r) => ({ ...r }))).toEqual(scopedRegRows);
  });

  it('a property inherits iff a reader sits below the element that sets it (Lean registrationsScoped_rule)', () => {
    expect(scopedReaderRows).toHaveLength(7);
    for (const r of REGISTRATIONS_SCOPED) expect(r.inherits, r.name).toBe(scopedReaderRows.some((q) => q.prop === r.name && q.depth > 0));
    expect(REGISTRATIONS_SCOPED.find((r) => r.name === PROP_FADE)?.inherits).toBe(false);
    expect(REGISTRATIONS_SCOPED.find((r) => r.name === PROP_PLATFORM)?.inherits).toBe(false);
  });

  it('the platform readers are the section only: its fade reads --platform-morph, its CSS reads --morph-fade', () => {
    expect(scopedReaderRows.filter((q) => q.sel === 'section')).toEqual([
      { prop: PROP_PLATFORM, sel: 'section', depth: 0 },
      { prop: PROP_FADE, sel: 'section', depth: 0 },
    ]);
    expect(scopedReaderRows.filter((q) => q.sel !== 'section')).toEqual(readerRows.filter((q) => q.sel !== 'section'));
    expect([...cssReaders('../platform/platform.module.css', PROP_FADE)]).toEqual(['section']);
    expect(cssReaders('../platform/platform.module.css', PROP_PLATFORM).size).toBe(0);
    expect(fadeCss('waapi-scoped')).toBe('calc(1 - min(1, var(--platform-morph) / 0.55))');
    expect(fadeCss('waapi')).toBe(FADE_CSS);
  });

  it('the platform animation carries the nav --morph values on --platform-morph (premise of Lean fade_eq)', () => {
    for (const [from, to] of [[0, 1], [1, 0], [0.3, 0.9]] as const) {
      const nav = navKeyframes({ from, to }).filter((k) => PROP_MORPH in k.props);
      const plat = platformKeyframes({ from, to }, 'waapi-scoped').filter((k) => PROP_PLATFORM in k.props);
      expect(plat.map((k) => [k.offset, k.props[PROP_PLATFORM]])).toEqual(nav.map((k) => [k.offset, k.props[PROP_MORPH]]));
      const keys = new Set(platformKeyframes({ from, to }, 'waapi-scoped').flatMap((k) => Object.keys(k.props)));
      expect([...keys].sort()).toEqual(['pointerEvents', PROP_PLATFORM].sort());
    }
    expect(settledProps(0.7, 'waapi-scoped').platform).toEqual({ [PROP_PLATFORM]: '0.7' });
    expect(settledProps(0.7).platform).toEqual({ [PROP_MORPH]: '0.7' });
  });
});

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

describe('morph.tween:waapi attribute writes vs morph-tween-waapi.attr.jsonl (Lean attr_band, waapi_vis)', () => {
  const attr = golden('morph-tween-waapi.attr');
  const readers = attr.filter((r) => r.kind === 'attrReader');
  const markerRows = attr.filter((r) => r.kind === 'marker') as { from: number; to: number; theta: number; marker: boolean; delay: number | null }[];
  const evs = attr.filter((r) => r.kind === 'attrEv') as { case: string; ev: string; t: number; goal?: number; band?: boolean[]; old?: boolean[] }[];

  it('ATTR_READERS equal the Lean attrReaders, in order', () => {
    expect(readers.map(({ sel, cmp, theta }) => ({ sel, cmp, theta }))).toEqual([...ATTR_READERS]);
    expect(new Set(MARKER_THETAS)).toEqual(new Set(readers.map((r) => r.theta)));
  });

  it('a push gets a marker iff Lean markerB, with a delay at most Lean dlLo and within 2 ms of it', () => {
    expect(markerRows).toHaveLength(108);
    for (const r of markerRows) {
      expect(hasMarker(r.from, r.to, r.theta), JSON.stringify(r)).toBe(r.marker);
      if (!r.marker) continue;
      const d = markerDelay(r.from, r.to, r.theta);
      expect(d, JSON.stringify(r)).toBeLessThanOrEqual(r.delay!);
      expect(d, JSON.stringify(r)).toBeGreaterThanOrEqual(r.delay! - 2);
    }
  });

  // script runs (finish and marker events, frame callbacks) against the faithful driver's one rAF callback per frame
  const runs: Record<string, [number, number]> = { open: [7, 42], reverse: [13, 64] };
  for (const name of ['open', 'reverse']) {
    it(`${name}: after every frame the written attribute is in the band of the original's value; the old driver's is not`, () => {
      const w = waapiRun();
      let stale = 0;
      let frames = 0;
      for (const e of evs.filter((r) => r.case === name)) {
        if (e.ev === 'push') {
          w.setTimeline(e.t);
          expect(w.wheel(e.goal === 1 ? 100 : -100)).toBe(true);
          continue;
        }
        w.frameAt(e.t);
        frames++;
        expect(band(w.hints.at(-1)!), `${name} t=${e.t}`).toEqual(e.band);
        if (JSON.stringify(e.old) !== JSON.stringify(e.band)) stale++;
      }
      expect(stale).toBeGreaterThan(0);
      expect([w.scriptRuns(), frames]).toEqual(runs[name]);
    });
  }
});
