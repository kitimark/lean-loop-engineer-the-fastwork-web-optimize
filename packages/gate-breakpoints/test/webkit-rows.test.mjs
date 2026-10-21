// The node twin of the nav-recorder classifier (src/trajectory/debug.mjs) against the golden that Lean generates
// (lean/Fw/Parts/MorphTweenWebkit.lean, packages/contracts/golden/parts/morph-tween-webkit-rows.jsonl).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { classifyRaw, classifyRep, holdRep, normalizeRows, windowVerdict } from '../src/trajectory/debug.mjs';

const dir = fileURLToPath(new URL('../../contracts/golden/parts/', import.meta.url));
const lines = readFileSync(dir + 'morph-tween-webkit-rows.jsonl', 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const cases = JSON.parse(readFileSync(dir + 'morph-tween-webkit-rows.cases.json', 'utf8'));
const reps = lines.filter((l) => l.kind === 'rep');
const verdicts = lines.filter((l) => l.kind === 'verdict');

test('golden: one rep line per case, every class of the module appears', () => {
  assert.equal(reps.length, cases.length);
  const seen = new Set(reps.map((r) => r.class));
  for (const c of ['noFlip', 'noBase', 'cProbe', 'c3', 'c4', 'c1', 'c2', 'c0']) assert.ok(seen.has(c), c);
  assert.ok(reps.some((r) => r.hold === 'held') && reps.some((r) => r.hold === 'jumped') && reps.some((r) => r.hold === 'unseen'));
});

test('rep lines: rows, class and hold of the twin equal the Lean golden', () => {
  cases.forEach((c, i) => {
    const rs = normalizeRows(c.raw);
    assert.deepEqual(rs, reps[i].rows, c.name);
    assert.equal(classifyRep(rs), reps[i].class, c.name);
    assert.equal(holdRep(rs), reps[i].hold, c.name);
  });
});

test('verdict lines: the twin equals the Lean golden', () => {
  assert.ok(verdicts.length >= 8);
  for (const v of verdicts) assert.equal(windowVerdict(v.runs, v.holds), v.verdict, JSON.stringify(v));
});

test('classifyRaw: reads runs[].morph.debugReps and keeps role and rep', () => {
  const raw = { runs: [{ role: 'cand', morph: { debugReps: [{ rep: 3, rows: { rows: cases[2].raw } }] } }, { role: 'orig', morph: {} }] };
  assert.deepEqual(classifyRaw(raw), [{ role: 'cand', rep: 3, cls: 'c0', hold: 'jumped' }]);
  assert.deepEqual(classifyRaw({}), []);
});

test('normalizeRows: unknown kinds and negative numbers are dropped, times round half up', () => {
  const rs = normalizeRows([{ k: 'nope', t: 1 }, { k: 'read', t: -1 }, { k: 'read', t: 1.5 }, { k: 'size', t: 2, w: 984.0786 }, { k: 'tr', t: 3, type: 'transitioncancel', prop: 'width' }]);
  assert.deepEqual(rs, [['read', 2], ['size', 2, 984079], ['tr', 3, 'cancel', true]]);
});
