import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { reduceWidth } from '../src/trajectory/reduce.mjs';

const lines = readFileSync(fileURLToPath(new URL('../../contracts/golden/parts/hero-exit-offset.jsonl', import.meta.url)), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l));
const judged = lines.filter((l) => l.fn === 'judged');
const causes = lines.filter((l) => l.fn === 'cause');

const registries = { hero: [{ id: 'hero.orbit.card', props: [{ id: 'opacity', kind: 'unit', r: 'num' }] }], morph: [], page: [] };
const rowOf = (s, y) => ({ step: s.in.step, tag: s.in.step, frame: s.in.frame, y, nodes: { 'hero.orbit.card': [[1]] }, page: [] });
const armOf = (key) => ({ hero: { rows: judged.map((s) => rowOf(s, s.in[key])), ready: { ready: true } } });

test('hero-exit-offset: the reducer judges exactly the rows Lean judgedEqual names and skips the other rest rows', () => {
  assert.ok(judged.length > 0);
  const units = reduceWidth({ width: 390, orig: armOf('yOrig'), rewrite: armOf('yCand'), registries });
  assert.deepEqual(units.map((u) => u.step), judged.filter((s) => s.out.now).map((s) => s.in.step));
  for (const u of units) {
    const s = judged.find((x) => x.in.step === u.step);
    assert.equal(u.verdict === 'skip:noSample', !s.out.equal, u.step);
  }
});

test('hero-exit-offset: judgedEqual drops only the rest rows read at unequal offsets', () => {
  for (const s of judged) {
    assert.equal(s.out.equal, s.out.now && s.in.yOrig === s.in.yCand, s.in.step);
  }
});

test('hero-exit-offset: every new unit of run 40156078840 is at equal offsets on a node that paints no box', () => {
  const byLane = Object.groupBy(causes, (c) => c.in.lane);
  assert.deepEqual(Object.fromEntries(Object.entries(byLane).map(([k, v]) => [k, v.length])), { chromium: 25, 'linux-webkit': 40, 'mac-webkit': 40 });
  for (const c of causes) {
    assert.equal(c.out.cause, 'hidden');
    assert.equal(c.in.yOrig, c.in.yCand);
    assert.equal(c.in.paintedOrig + c.in.paintedCand, 0);
  }
});
