// Tests of scripts/circleci-series.mjs (task circleci-series): the nearest-rank statistics pinned to the Lean #guard values of
// Fw.Obs.Timing.p50 (lean/Fw/Obs/Timing.lean:146-147), the row reduction, and the GitHub twin reduction.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadGolden } from './circleci.mjs';
import { ghRow, nearestRank, rowOf, spread, summarize } from './circleci-series.mjs';

test('p50 is the Lean nearest-rank median (lower median for even n)', () => {
  assert.equal(nearestRank([], 50), 0);
  assert.equal(nearestRank([7], 50), 7);
  assert.equal(nearestRank([3, 9, 1], 50), 3);
  assert.equal(nearestRank([4, 1, 3, 2], 50), 2);
  assert.equal(nearestRank([2000, 1000, 2000, 27000, 26000], 50), 2000);
});

test('p95 at n = 10 is the maximum, at n = 20 the 19th value', () => {
  const ten = [5, 1, 9, 3, 7, 2, 8, 4, 6, 10];
  assert.equal(nearestRank(ten, 95), 10);
  assert.deepEqual(spread(ten), { n: 10, p50: 5, p95: 10, max: 10, min: 1 });
  assert.equal(nearestRank(Array.from({ length: 20 }, (_, i) => i + 1), 95), 19);
});

const g = loadGolden();
const wf = { id: 'w', status: 'success', created_at: '2026-10-21T10:00:00Z', stopped_at: '2026-10-21T10:01:30Z' };
const run = (job, queueMs, durMs) => ({ provider: 'circleci', job, sha: 'a'.repeat(40), conclusion: 'pass', digest: null, class: 'arm.medium.gen2', queueMs, durMs });

test('rowOf: wall time, per-job credits from the Lean price list (rounded up per job)', () => {
  const r = rowOf({ g, number: 7, pipelineId: 'p', cls: 'arm.medium.gen2', workflow: wf, runs: [run('engine-chromium', 30000, 38800), run('verdict', 1000, 10100)], pipelineCreatedMs: 0 });
  assert.equal(r.workflowWallMs, 90000);
  assert.deepEqual(r.jobs.map((j) => j.credits), [4, 2]);
  assert.equal(r.jobCredits, 6);
  assert.equal(r.billedCredits, null);
});

test('summarize: counts only successful runs and keeps failed ones in `runs`', () => {
  const ok = rowOf({ g, number: 1, pipelineId: 'a', cls: 'arm.medium.gen2', workflow: wf, runs: [run('engine-chromium', 10, 40000), run('engine-playwright-webkit', 20, 50000), run('verdict', 5, 10000)], pipelineCreatedMs: 0 });
  const bad = { ...ok, number: 2, status: 'failed' };
  const s = summarize([ok, bad], null);
  const c = s.classes['arm.medium.gen2'];
  assert.equal(c.runs, 2);
  assert.equal(c.succeeded, 1);
  assert.deepEqual(c.pipelines, [1, 2]);
  assert.equal(c.jobs['engine-chromium'].dur.p50, 40000);
  assert.equal(c.queueEngine.max, 20);
});

test('ghRow: job duration is completed minus started, queue is run created to job started', () => {
  const r = ghRow({ databaseId: 1, createdAt: '2026-10-21T10:00:00Z', conclusion: 'success', jobs: [
    { name: 'engine (chromium)', conclusion: 'success', startedAt: '2026-10-21T10:00:30Z', completedAt: '2026-10-21T10:01:10Z' },
    { name: 'verdict', conclusion: 'success', startedAt: '2026-10-21T10:01:20Z', completedAt: '2026-10-21T10:01:30Z' }] });
  assert.equal(r.jobs['engine (chromium)'].durMs, 40000);
  assert.equal(r.jobs['engine (chromium)'].queueMs, 30000);
  assert.equal(r.wallMs, 90000);
});
