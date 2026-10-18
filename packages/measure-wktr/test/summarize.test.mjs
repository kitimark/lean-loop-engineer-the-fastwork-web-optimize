// summarize.mjs --assert is a port of Lean Fw.Ops.Premise.laneFailures: checked against the Lean golden
// packages/contracts/golden/ops/wktr-lane.jsonl (regenerate: cd lean && lake env lean --run scripts/PremiseGolden.lean).
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { WKTR_EXPECTED, laneFailures, fixtureOf } from '../fixtures/summarize.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const rows = readFileSync(join(here, '..', '..', 'contracts', 'golden', 'ops', 'wktr-lane.jsonl'), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));

test('expected rates equal Lean wktrExpected', () => {
  const exp = rows.find((r) => r.kind === 'expected');
  assert.deepEqual(WKTR_EXPECTED, exp.rates.map((r) => [r.fixture, r.perUpdate]));
});

test('laneFailures equals the Lean golden on every case', () => {
  const cases = rows.filter((r) => r.kind === 'case');
  assert.ok(cases.length >= 8);
  for (const c of cases) assert.deepEqual(laneFailures(WKTR_EXPECTED, c.passes), c.failures, c.name);
});

test('fixtureOf drops the frames suffix', () => {
  assert.equal(fixtureOf('scroll-timeline-f3'), 'scroll-timeline');
  assert.equal(fixtureOf('control-f1'), 'control');
});

// one job directory with one pass per asserted arm; timeline = style recalcs per step of the scroll-timeline arm
function job(timeline) {
  const d = mkdtempSync(join(tmpdir(), 'wktr-sum-'));
  const meta = { page: { innerWidth: 402, docH: 100, endY: 80 } };
  for (const [arm, sr] of [['control-f1', 0], ['scroll-timeline-f1', timeline], ['time-accel-f1', 0]]) {
    mkdirSync(join(d, arm));
    const frames = Array.from({ length: 4 }, () => ({ counts: { styleRecalcs: sr, renderingUpdates: 1 } }));
    writeFileSync(join(d, arm, 'counts-live-1.json'), JSON.stringify({ meta, frames }));
  }
  return d;
}

test('--assert exits 0 on the premise rates and 1 on the old claim', () => {
  const cli = join(here, '..', 'fixtures', 'summarize.mjs');
  for (const [timeline, code] of [[1, 0], [0, 1]]) {
    const d = job(timeline);
    try {
      const r = spawnSync(process.execPath, [cli, d, '--assert'], { encoding: 'utf8' });
      assert.equal(r.status, code, r.stdout + r.stderr);
    } finally { rmSync(d, { recursive: true, force: true }); }
  }
});
