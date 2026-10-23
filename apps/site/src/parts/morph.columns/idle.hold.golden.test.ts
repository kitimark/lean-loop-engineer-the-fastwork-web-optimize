import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { IdleHold } from './idle';

type Anim = [number | null, number | null];
type Op = { op: 'keep' | 'restore'; anims: Anim[] };
interface HoldLine { kind: string; ops: Op[]; out: Anim[][] }

const url = new URL('../../../../../packages/contracts/golden/measure/wkcost.jsonl', import.meta.url);
const lines = readFileSync(url, 'utf8').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l) as HoldLine);
const cases = lines.filter((l) => l.kind === 'idleHold');

function fake(els: Map<number, object>, [target, time]: Anim) {
  let el: object | null = null;
  if (target !== null) {
    el = els.get(target) ?? {};
    els.set(target, el);
  }
  return { effect: { target: el }, currentTime: time };
}

describe('morph.columns:idle-none IdleHold against the Lean model (wkcost golden, kind idleHold)', () => {
  it('has recorded sequences', () => {
    expect(cases.length).toBeGreaterThan(5);
  });

  it.each(cases.map((c, i) => [i, c] as const))('sequence %i: the times each restore hands back', (_i, c) => {
    const hold = new IdleHold();
    const els = new Map<number, object>();
    const got: Anim[][] = [];
    for (const step of c.ops) {
      const anims = step.anims.map((a) => fake(els, a));
      if (step.op === 'keep') {
        hold.keep(anims as unknown as Animation[]);
      } else {
        hold.restore(anims as unknown as Animation[]);
        got.push(anims.map((a, k) => [step.anims[k]![0], a.currentTime as number | null]));
      }
    }
    expect(got).toEqual(c.out);
  });
});
