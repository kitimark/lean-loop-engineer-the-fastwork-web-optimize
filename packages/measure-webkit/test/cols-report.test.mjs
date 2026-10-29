import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { armJob, colsMd, reduceJobs } from '../src/throttle/cols-report.mjs';
import { MORPH_ARMS, searchOf } from '../src/throttle/push-cycle.mjs';
import { COLS_LOG_JS, COLS_LOG_FETCH_JS } from '../src/throttle/push-cycle-page.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(join(HERE, '../../contracts/golden/device/cols-probe.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const arms = golden.filter((g) => g.kind === 'arm');

test('the Simulator arms are the Lean rows: names and pages', () => {
  assert.equal(arms.length, 4);
  for (const g of arms) {
    assert.ok(g.wkArm in MORPH_ARMS, g.wkArm);
    assert.equal(searchOf(g.wkArm), g.search);
  }
});

test('the page hook logs push and take with is-on-dark at the push', () => {
  assert.match(COLS_LOG_JS, /window\.__fwTakeTrace = /);
  assert.match(COLS_LOG_JS, /nav\.is-on-dark/);
  const win = { __fwColsLog: undefined };
  const doc = { querySelector: (s) => (s === 'nav.is-on-dark' ? {} : null) };
  new Function('window', 'document', `return ${COLS_LOG_JS}`)(win, doc);
  win.__fwTakeTrace({ kind: 'push' });
  win.__fwTakeTrace({ kind: 'take' });
  assert.deepEqual(win.__fwColsLog, [{ kind: 'push', dark: true }, { kind: 'take', dark: null }]);
  assert.equal(new Function('window', `return ${COLS_LOG_FETCH_JS}`)(win), JSON.stringify(win.__fwColsLog));
});

const pass = (arm, { layers, bytes, paints, took }) => {
  const starts = [1000, 3000, 5000, 7000];
  const rows = starts.flatMap((t0, i) => Array.from({ length: paints[i] }, (_, k) => ['Paint', t0 + 100 + k]));
  return {
    arm, profile: 'push', drag: { code: 0 }, rec: { nav: true, frames: 100000, y: [0, 5000], start: { scale: 1 }, t: [900, 1000, 9000] },
    push: { starts, endMs: 12000, rows, rafs: [], drift: 0 },
    census: [{ layers: 1, bytes: 1 }, { layers, bytes }],
    takeLog: arm.includes('timed') ? starts.flatMap(() => [{ kind: 'push', dark: true }, ...(took ? [{ kind: 'take' }] : [])]) : [],
  };
};

test('a job file reduces to layers, bytes, paint rate and the flip log', () => {
  const job = { vm: 1, passes: [pass('morph-timed', { layers: 40, bytes: 4000, paints: [2, 2, 2, 2], took: true })] };
  const r = armJob(job, 'morph-timed');
  assert.deepEqual(r.metrics, { layerCount: 40, backingBytes: 4000, Paint: 2000 });
  assert.deepEqual(r.log, { pushes: 4, took: 4, dark: 4 });
  assert.equal(armJob(job, 'morph-base').metrics, null);
});

test('three jobs with fewer pictures give pictures cost on base; a flip that never took makes the flip contrast undecided', () => {
  const jobs = [1, 2, 3].map((vm) => ({
    vm,
    passes: [
      pass('morph-base', { layers: 40 + vm, bytes: 4000 + vm, paints: [6, 6, 6, 6] }),
      pass('morph-base-off', { layers: 20, bytes: 2000, paints: [2, 2, 2, 2] }),
      pass('morph-timed', { layers: 40, bytes: 4000, paints: [3, 3, 3, 3], took: false }),
      pass('morph-timed-off', { layers: 20, bytes: 2000, paints: [1, 1, 1, 1], took: false }),
    ],
  }));
  const r = reduceJobs(jobs);
  assert.equal(r.contrasts.base.reading, 'pictures cost');
  assert.equal(r.contrasts.flip.valid, false);
  assert.equal(r.contrasts.flip.reading, 'undecided (few jobs)');
  assert.match(colsMd(r), /pictures cost/);
});
