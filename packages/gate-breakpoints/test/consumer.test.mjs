import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { keptIdx, consumerRows } from '../src/trajectory/consumer.mjs';
import { reduceWidth } from '../src/trajectory/reduce.mjs';

const lines = readFileSync(fileURLToPath(new URL('../../contracts/golden/gate/consumer.jsonl', import.meta.url)), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l));

test('consumer: keptIdx replays the Lean golden', () => {
  assert.ok(lines.length >= 8);
  for (const l of lines) assert.deepEqual(keptIdx(l.in.n, l.in.boxOrig, l.in.boxCand), l.out.kept, l.in.name);
});

const registries = { hero: [{ id: 'card', props: [{ id: 'opacity', kind: 'unit', r: 'num' }] }], morph: [], page: [] };
const row = (step, vals, box, y = 100) => ({ step, tag: step, frame: 'rest', y, nodes: { card: vals.map((v) => [[v]]) }, box: { card: box }, page: [] });
const arm = (rows) => ({ hero: { rows, ready: { ready: true } } });
const run = (o, w) => reduceWidth({ width: 390, orig: arm(o), rewrite: arm(w), registries }).map((u) => u.verdict);

test('consumer: a node with no box in both arms is not compared', () => {
  assert.deepEqual(run([row('s25', [900], [false])], [row('s25', [500], [false])]), ['skip:noSample']);
});

test('consumer: a node with a box in either arm is compared', () => {
  assert.deepEqual(run([row('s25', [900], [true])], [row('s25', [500], [false])]), ['fail:apart']);
  assert.deepEqual(run([row('s25', [900], [false])], [row('s25', [500], [true])]), ['fail:apart']);
  assert.deepEqual(run([row('s25', [900], [true])], [row('s25', [900], [true])]), ['pass']);
});

test('consumer: hidden elements are dropped, the rendered one is judged on its own', () => {
  const [o, w] = consumerRows([row('s25', [900, 200], [false, true])], [row('s25', [500, 200], [false, true])], ['card']);
  assert.deepEqual(o[0].nodes.card, [[[200]]]);
  assert.deepEqual(w[0].nodes.card, [[[200]]]);
  assert.deepEqual(run([row('s25', [900, 200], [false, true])], [row('s25', [500, 200], [false, true])]), ['pass']);
  assert.deepEqual(run([row('s25', [900, 200], [false, true])], [row('s25', [500, 700], [false, true])]), ['fail:apart']);
});

test('consumer: rows without box bits are compared whole', () => {
  const bare = (v) => ({ ...row('s25', [v], [false]), box: undefined });
  assert.deepEqual(run([bare(900)], [bare(500)]), ['fail:apart']);
});

test('consumer: a missing rendered element still fails on count', () => {
  assert.deepEqual(run([row('s25', [900, 200], [true, true])], [row('s25', [900], [true])]), ['fail:count']);
});

test('judgedEqual: a rest row pair at different scroll offsets is skipped', () => {
  assert.deepEqual(run([row('s25', [900], [true], 100)], [row('s25', [500], [true], 99)]), ['skip:noSample']);
});
