import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { JOB, deadlineAt, cappedDeadline, stepMinutes, runsWalk, startsWindow, remaining, planWalk, untilDeadline, MIN_WALK_MINUTES } from '../src/walk-budget.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/walk-budget.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('walk-budget: constants and every golden step and start line match Lean', () => {
  const c = golden.find((g) => g.op === 'constants');
  assert.deepEqual({ timeoutMs: c.timeoutMs, postMs: c.postMs, graceMs: c.graceMs, slackMs: c.slackMs }, JOB);
  assert.equal(deadlineAt(JOB), c.deadlineAt);
  for (const g of golden.filter((x) => x.op === 'step')) {
    const dl = cappedDeadline(JOB, g.elapsedMs, g.capMs);
    assert.equal(dl, g.deadlineMs, g.case);
    assert.equal(stepMinutes(JOB, g.elapsedMs, dl), g.stepMinutes, g.case);
    assert.equal(runsWalk(JOB, g.elapsedMs, dl, MIN_WALK_MINUTES), g.runs, g.case);
  }
  for (const g of golden.filter((x) => x.op === 'start')) {
    assert.equal(startsWindow(g.deadlineMs, g.nowMs, g.reserveMs), g.starts, g.case);
    assert.equal(remaining(g.deadlineMs, g.nowMs), g.remainingMs, g.case);
  }
});

test('planWalk: the step timeout plus the post steps end inside the job timeout for any start before the deadline', () => {
  const jobStartMs = 1_000_000_000_000;
  for (const elapsed of [0, 60_000, 276_000, 900_000, 1_800_000, 1_980_000]) {
    const p = planWalk({ jobStartMs, nowMs: jobStartMs + elapsed });
    assert.equal(p.run, true);
    assert.ok(elapsed + p.stepMinutes * 60000 + JOB.postMs + JOB.slackMs <= JOB.timeoutMs);
    assert.equal(p.deadlineMs, jobStartMs + deadlineAt(JOB));
  }
  assert.equal(planWalk({ jobStartMs, nowMs: jobStartMs + 2_100_000 }).run, false);
  const capped = planWalk({ jobStartMs, nowMs: jobStartMs + 276_000, capMin: 8 });
  assert.equal(capped.deadlineMs, jobStartMs + 756_000);
});

test('the CLI prints the three step outputs', () => {
  const out = execFileSync(process.execPath, [fileURLToPath(new URL('../src/walk-budget.mjs', import.meta.url)), '--job-start-ms', '1000000000000', '--now-ms', '1000000276000', '--cap-min', '8'], { encoding: 'utf8' });
  assert.equal(out, 'run=true\nstep_minutes=10\ndeadline_ms=1000000756000\n');
});

test('untilDeadline: a promise that never settles is abandoned at the deadline, a fast one wins, a rejection passes through', async () => {
  const t0 = Date.now();
  assert.equal(await untilDeadline(new Promise(() => {}), t0 + 60), 'deadline');
  assert.ok(Date.now() - t0 >= 50 && Date.now() - t0 < 1000);
  assert.equal(await untilDeadline(Promise.resolve(1), Date.now() + 5000), 'done');
  await assert.rejects(untilDeadline(Promise.reject(new Error('boom')), Date.now() + 5000), /boom/);
  const late = new Promise((_, rej) => setTimeout(() => rej(new Error('late')), 100));
  assert.equal(await untilDeadline(late, Date.now() + 20), 'deadline');
  await new Promise((r) => setTimeout(r, 150));
});
