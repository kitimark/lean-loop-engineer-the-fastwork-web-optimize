import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import colPart from '../morph.columns/part.json';
import cdPart from '../morph.countdown/part.json';
import scenePart from './part.json';
import {
  HIDDEN_FRACTION,
  SCENE_ACTIVE_ABOVE,
  createSceneClock,
  createWriteGate,
  hiddenAtFraction,
  scenePausedAtMorph,
  sceneHidden,
} from './logic';
import { thresholdsFor } from './observe';

const root = resolve(__dirname, '../../../../..');
const lean = readFileSync(resolve(root, 'lean/Fw/Parts/HiddenPause.lean'), 'utf8');
const rows = readFileSync(resolve(root, 'packages/contracts/golden/engine/hidden-pause.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Record<string, string>);

/** `a/b` in Lean source to a number. */
const frac = (s: string): number => {
  const [a, b] = s.split('/').map(Number);
  return a! / b!;
};

describe('constants come from the Lean source', () => {
  it('HIDDEN_FRACTION is `hiddenPause`: decide (m <= N/D)', () => {
    const m = /def hiddenPause \(m : Rat\) : Bool := decide \(m ≤ (\d+\/\d+)\)/.exec(lean);
    expect(m, 'hiddenPause definition not found').not.toBeNull();
    expect(HIDDEN_FRACTION).toBe(frac(m![1]!));
  });
  it('SCENE_ACTIVE_ABOVE is `scenePaused`: !decide (N/D < m)', () => {
    const m = /def scenePaused \(m : Rat\) : Bool := !decide \((\d+\/\d+) < m\)/.exec(lean);
    expect(m, 'scenePaused definition not found').not.toBeNull();
    expect(SCENE_ACTIVE_ABOVE).toBe(frac(m![1]!));
  });
  it('the IntersectionObserver threshold is the constant', () => {
    expect(thresholdsFor('fraction')).toEqual([HIDDEN_FRACTION]);
    expect(thresholdsFor('rect')).toEqual([0]);
  });
});

describe('hidden pause decisions (Lean #guard and theorem statements)', () => {
  it('hiddenPause: true up to and at the threshold, false above (#guard line 159)', () => {
    expect(hiddenAtFraction(0)).toBe(true);
    expect(hiddenAtFraction(HIDDEN_FRACTION)).toBe(true);
    expect(hiddenAtFraction(81 / 1000)).toBe(false);
    expect(hiddenAtFraction(1)).toBe(false);
  });
  it('scenePaused implies hiddenPause (scenePaused_imp_hiddenPause)', () => {
    for (const m of [0, 0.0005, 0.001, 0.002, 0.05, 0.08, 0.5, 1]) {
      if (scenePausedAtMorph(m)) expect(hiddenAtFraction(m)).toBe(true);
    }
    expect(scenePausedAtMorph(1 / 1000)).toBe(true);
    expect(scenePausedAtMorph(2 / 1000)).toBe(false);
  });
  it('sceneHidden: no positive-area overlap is hidden (#guard lines 256-258)', () => {
    expect(sceneHidden(false, 0, 0)).toBe(true);
    expect(sceneHidden(true, 100, 1)).toBe(false);
    expect(sceneHidden(true, 100, 0)).toBe(true); // edge touch / zero height
    expect(sceneHidden(true, 0, 10)).toBe(true);
  });
});

describe('origClock (Lean origClock, naive_pause_shifts)', () => {
  /** frames (delta, morph): the Lean fold, with the TS clock fed one frame at a time */
  const run = (frames: [number, number][]) => {
    const c = createSceneClock(0, !scenePausedAtMorph(frames[0]![1]));
    let t = 0;
    for (const [d, m] of frames) {
      c.setActive(t, !scenePausedAtMorph(m));
      t += d;
    }
    return c.read(t);
  };
  it('matches the Lean #guards', () => {
    expect(run([[16, 0], [16, 1 / 20], [16, 1]])).toBe(32);
    expect(run([[16, 1 / 1000]])).toBe(0);
    expect(run([[16, 1 / 500]])).toBe(16);
  });
  it('differs from a play-state pause: a frame at 0.05 still counts (naive_pause_shifts)', () => {
    expect(run([[16, 1 / 20]])).toBe(16);
  });
});

describe('write gate (skipWrites_le, hsync)', () => {
  it('skips while hidden, replays only the latest per key on unhide', () => {
    const out: [string, string][] = [];
    const g = createWriteGate<string>((k, v) => out.push([k, v]));
    g.set('a', '1');
    g.setHidden(true);
    g.set('a', '2');
    g.set('a', '3');
    g.set('b', '9');
    expect(out).toEqual([['a', '1']]);
    g.setHidden(false);
    expect(out).toEqual([['a', '1'], ['a', '3'], ['b', '9']]);
    expect(g.skipped).toBe(3);
    g.set('a', '4');
    expect(out.at(-1)).toEqual(['a', '4']);
  });
});

describe('golden rows and registry', () => {
  it('8 rows, variant hidden-pause on base rewrite, both engines, four stages each', () => {
    expect(rows).toHaveLength(8);
    for (const r of rows) {
      expect(r.variant).toBe('hidden-pause');
      expect(r.base).toBe('rewrite');
    }
    expect(rows.filter((r) => r.engine === 'chromium')).toHaveLength(4);
    expect(rows.filter((r) => r.engine === 'webkit')).toHaveLength(4);
  });
  it('the three parts register the variant the rows name; faithful stays the head', () => {
    for (const p of [colPart, cdPart, scenePart]) {
      expect(Object.keys(p.variants)[0]).toBe('faithful');
      expect(Object.keys(p.variants)).toContain(rows[0]!.variant);
    }
  });
  it('the rows promise no script/layout growth: FireAnimationFrame equal, style and commit at most', () => {
    for (const r of rows.filter((x) => x.stage === 'script')) expect(r.prediction).toBe('=o');
    for (const r of rows.filter((x) => x.stage === 'style')) expect(r.prediction).toBe('≤o');
  });
});
