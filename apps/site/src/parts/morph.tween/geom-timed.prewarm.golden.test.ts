import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { Layout } from '../morph.geom/tracks';
import { createTimedGeom, type TimedAnim } from './geom-timed.driver';

type Ev = { e: 'warm' } | { e: 'cool' } | { e: 'dispose' } | { e: 'push'; f: number; t: number; allowed: boolean; stale: boolean } | { e: 'settle'; m: number };
type Step = { sets: number; enters: number; leaves: number; held: boolean; tree: boolean; refSets: number };
type Row = { fn: string; in: { name: string; events: Ev[] }; out: { steps: Step[]; sameLook: boolean } };
const rows = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/parts/morph-geom-prewarm.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);

const layout: Layout = { eng: 'webkit', a: 0, b: 1, inset: 24, logoW: 160, lw: 144, w0: 176, gL: 0, imgs: [[[0, 200]]] };

function build() {
  const c = { allowed: true, stale: false, enters: 0, leaves: 0, creates: 0, paused: 0, started: 0 };
  const timed = createTimedGeom({
    allowed: () => c.allowed,
    enter: () => (c.enters++, { vp: { w: 1280, h: 800 }, layout }),
    leave: () => void c.leaves++,
    fresh: () => !c.stale,
    animate: () => {
      c.creates++;
      const h: TimedAnim = {
        cancel: () => void 0,
        pause: () => void c.paused++,
        get startTime() {
          return null;
        },
        set startTime(_v: number | null) {
          c.started++;
        },
      };
      return h;
    },
    goal: () => void 0,
  });
  return { c, timed };
}

const perSet = (() => {
  const { c, timed } = build();
  timed.take(0, 1, 0);
  return c.creates;
})();

function run(events: Ev[]) {
  const { c, timed } = build();
  return events.map((ev) => {
    const before = { ...c };
    if (ev.e === 'warm') timed.warm();
    else if (ev.e === 'cool') timed.cool();
    else if (ev.e === 'dispose') timed.dispose();
    else if (ev.e === 'settle') timed.settle(ev.m);
    else {
      c.allowed = ev.allowed;
      c.stale = ev.stale;
      timed.take(ev.f, ev.t, 0);
    }
    return { sets: (c.creates - before.creates) / perSet, enters: c.enters - before.enters, leaves: c.leaves - before.leaves, held: timed.held(), tree: timed.live() };
  });
}

describe('createTimedGeom prewarm against the Lean lifecycle golden', () => {
  it('has the scenarios', () => expect(rows.length).toBe(10));
  it('a warm holds the 0 to 1 set paused and a push only starts it', () => {
    const { c, timed } = build();
    timed.warm();
    expect([c.creates, c.paused, c.started]).toEqual([perSet, perSet, 0]);
    timed.take(0, 1, 5);
    expect([c.creates, c.started]).toEqual([perSet, perSet]);
  });
  for (const r of rows) {
    it(`${r.in.name}: sets, enters, leaves, held and tree per event equal the Lean prewarm driver, whose look equals the landed driver's`, () => {
      expect(r.out.sameLook).toBe(true);
      expect(run(r.in.events)).toEqual(r.out.steps.map(({ sets, enters, leaves, held, tree }) => ({ sets, enters, leaves, held, tree })));
    });
  }
});
