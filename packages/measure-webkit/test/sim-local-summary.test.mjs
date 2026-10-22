import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readPasses, table } from '../src/sim-local-summary.mjs';
import { summarize } from '../src/safari-local-run.mjs';

test('readPasses and table: per-pass files become the verdict table', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-sum-'));
  try {
    mkdirSync(join(dir, 'passes'));
    const row = (arm, round, long, decision = 'accept') => ({ engine: 'safari', window: 'hero', arm, round, decision, ...(decision === 'accept' ? { stat: { long, skipped: long, p50: 83, p95: 90, mx: 120 } } : { phase: 'before', why: ['load'] }) });
    const rows = [...[0, 1, 2].map((r) => row('base', r, 4)), ...[0, 1, 2].map((r) => row('hx', r, 1)), row('hx', 3, 0, 'refuse')];
    rows.forEach((r, i) => writeFileSync(join(dir, 'passes', `p${i}.json`), JSON.stringify(r)));
    const got = readPasses(dir);
    assert.equal(got.length, 7);
    const t = table(summarize(got));
    assert.match(t, /\| safari \| hero \| hx \| 3 \| 1\/0\/0 \| 0 \| 1 \| 1 \| 8\.3 \| 9\.0 \| 12\.0 \| - \| - \| better \| better \|/);
    assert.match(t, /\| safari \| hero \| base \| 3 \| 0\/0\/0 \|/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
