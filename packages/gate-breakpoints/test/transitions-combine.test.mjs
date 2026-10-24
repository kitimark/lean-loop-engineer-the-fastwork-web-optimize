// transitions-combine.mjs: per-run medians laid side by side (TS stand-in reduction).
import test from 'node:test';
import assert from 'node:assert/strict';
import { combine, combinedText } from '../src/trajectory/transitions-combine.mjs';

const cell = (jump, between) => ({ role: 'faithful', seq: 'hero-entry', series: { padL: { maxJump: { median: jump }, between: { median: between } } }, cadence: { median: 17 } });
const run = (id, jump, between) => ({ run: id, summaries: { '1280|playwright-webkit': { cells: [cell(jump, between)] } } });

test('combine: one row per cell with the per-run values and their spread', () => {
  const rows = combine([run('a', 24, 0), run('b', 24, 0), run('c', 22, 1)]);
  assert.equal(rows.length, 1);
  const m = rows[0].metrics['padL.maxJump'];
  assert.deepEqual([m.n, m.min, m.median, m.max, m.perRun], [3, 22, 24, 24, [24, 24, 22]]);
  assert.equal(rows[0].metrics['padL.between'].max, 1);
  assert.equal(rows[0].metrics['cadence.ms'].median, 17);
  assert.deepEqual(rows[0].runs, ['a', 'b', 'c']);
});

test('combine: a metric missing in a run is left out of that run only', () => {
  const noSeries = { run: 'x', summaries: { '1280|playwright-webkit': { cells: [{ role: 'faithful', seq: 'hero-entry', series: {}, cadence: null }] } } };
  const rows = combine([run('a', 24, 0), noSeries]);
  assert.equal(rows[0].metrics['padL.maxJump'].n, 1);
  assert.equal(rows[0].runs.length, 2);
});

test('combinedText: hero rows only, one line each', () => {
  const rows = combine([run('a', 24, 0)]);
  rows.push({ ...rows[0], seq: 'morph-open' });
  const t = combinedText(rows).trim().split('\n');
  assert.equal(t.length, 3);
  assert.match(t[2], /padL jump 24 \[24\.\.24\], between 0/);
});
