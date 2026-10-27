import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { buildAnims, cssValue, evalAt, type Layout } from '../morph.geom/tracks';
import { ease } from './logic';
import { at, crossMs, idealAt, rebase } from './geom-timed.logic';
import { goalRules, pushKeyframes } from './geom-timed.driver';

const lines = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/morph-geom-timed.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as { fn: string; in: Record<string, unknown>; out: unknown });
const of = (fn: string) => lines.filter((l) => l.fn === fn);

const PANEL_X = [0, 0.08, 0.8, 1];
const panelO = (m: number) => Math.min(1, Math.max(0, (m - 0.08) / 0.72));
const PANEL_Y = PANEL_X.map(panelO);

describe('morph.tween:geom-timed against the Lean golden', () => {
  it('rebase: the keyframes of a push up or down equal the golden', () => {
    const cases = of('rebase');
    expect(cases.length).toBe(7);
    for (const c of cases) {
      const { m0, g } = c.in as { m0: number; g: number };
      const out = c.out as { offsets: number[]; values: number[] };
      const k = rebase(PANEL_X, PANEL_Y, m0, g);
      expect(k.offsets.length, `${m0}->${g}`).toBe(out.offsets.length);
      out.offsets.forEach((o, i) => {
        expect(k.offsets[i]).toBeCloseTo(o, 8);
        expect(k.values[i]).toBeCloseTo(out.values[i], 8);
      });
    }
  });

  it('cross: the first whole millisecond of each threshold equals the golden', () => {
    const cases = of('cross');
    expect(cases.length).toBe(12);
    for (const c of cases) {
      const { m0, g, c: cut } = c.in as { m0: number; g: number; c: number };
      expect(crossMs(m0, g, cut), `${m0}->${g} @${cut}`).toBe(c.out);
    }
  });

  it('scenario: each push set shows the ideal tween (rebased keyframes at the bezier output) at every sample', () => {
    const scenarios = of('scenario');
    expect(scenarios.length).toBe(6);
    for (const sc of scenarios) {
      const evs = (sc.in as { events: { e: number; g: number }[] }).events;
      const { t, m } = sc.out as { t: number[]; m: number[] };
      let f = 0;
      let to = 0;
      let start = 0;
      let seen = 0;
      t.forEach((time, i) => {
        while (seen < evs.length && evs[seen].e <= time) {
          f = idealAt(f, to, evs[seen].e - start);
          to = evs[seen].g;
          start = evs[seen].e;
          seen++;
        }
        const ideal = idealAt(f, to, time - start);
        expect(ideal, `${sc.in.name} t=${time}`).toBeCloseTo(m[i], 5);
        if (f !== to) {
          const k = rebase([0, 1], [0, 1], f, to);
          const el = Math.min(1, Math.max(0, (time - start) / 680));
          expect(at(k.offsets, k.values, ease({ x: el })), `${sc.in.name} t=${time} rebased`).toBeCloseTo(m[i], 5);
        }
      });
    }
  });

  it('a reversal starts where the old set shows: the new set at its start equals the old at that time', () => {
    for (const e of [100, 300, 500]) {
      const old = idealAt(0, 1, e);
      const k = rebase(PANEL_X, PANEL_Y, old, 0);
      expect(k.values[0]).toBeCloseTo(panelO(old), 12);
    }
  });
});

const layout = (eng: 'webkit' | 'chromium'): Layout => ({ eng, a: 0, b: 1, inset: 24, logoW: 160, lw: 144, w0: 176, gL: 0, imgs: [[[0, 200], [200, 200]], [[0, 200]]] });

describe('morph.tween:geom-timed track keyframes', () => {
  for (const eng of ['webkit', 'chromium'] as const) {
    for (const [w, h] of [[390, 844], [1280, 800]]) {
      it(`${eng} ${w}: the last keyframe is the goal style (up) and the rest look (down); the first is the event-time value`, () => {
        const anims = buildAnims({ w, h }, layout(eng));
        const goal = goalRules(anims);
        for (const a of anims) {
          if (a.ks === 'time') continue;
          const up = pushKeyframes(a, 0.3, 1).kf;
          const x1 = a.values.map((_, f) => evalAt(a, f, 1));
          expect(String(up.at(-1)![a.prop])).toBe(cssValue(a.prop, x1));
          expect(goal).toContain(cssValue(a.prop, x1));
          const down = pushKeyframes(a, 0.6, 0).kf;
          expect(String(down.at(-1)![a.prop])).toBe(cssValue(a.prop, a.values.map((_, f) => evalAt(a, f, 0))));
          expect(String(down[0][a.prop])).toBe(cssValue(a.prop, a.values.map((_, f) => evalAt(a, f, 0.6))));
          for (let k = 1; k < down.length; k++) expect(down[k].offset).toBeGreaterThan(down[k - 1].offset);
        }
      });
    }
  }
  it('the time tracks of the push from rest up are trimmed at 680 ms and linear; a reversal samples at 60 Hz', () => {
    const a = buildAnims({ w: 1280, h: 800 }, layout('chromium')).find((x) => x.ks === 'time')!;
    const exact = pushKeyframes(a, 0, 1);
    expect(exact.easing).toBe('linear');
    expect(exact.kf.at(-1)!.offset).toBe(1);
    const rev = pushKeyframes(a, 0.7, 0);
    expect(rev.kf.length).toBe(42);
    expect(rev.kf[0].offset).toBe(0);
  });
});
