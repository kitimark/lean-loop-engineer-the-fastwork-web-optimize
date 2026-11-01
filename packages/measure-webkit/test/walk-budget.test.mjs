import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { planSim } from '../src/profile/sim-cadence.mjs';
import { JOB, GAPS, MIN_KEPT, LIFE_WINDOWS, BODY_MS, TAIL_MS, TAIL_EVERY, MARGIN, MIN_SAMPLES, JOBS_NEEDED, blockMs, windowsPerRep, groupArms, groupsFor, repsFit, repsLife, planReps, outcome, endsDone, deadlineAt, cappedDeadline, stepMinutes, runsWalk, startsWindow, remaining, planWalk, untilDeadline, MIN_WALK_MINUTES, HARD_STOP_MS } from '../src/walk-budget.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/walk-budget.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('walk-budget: constants and every golden step and start line match Lean', () => {
  const c = golden.find((g) => g.op === 'constants');
  assert.equal(HARD_STOP_MS, c.hardStopMs);
  assert.deepEqual({ timeoutMs: c.timeoutMs, postMs: c.postMs, graceMs: c.graceMs, slackMs: c.slackMs }, JOB);
  assert.equal(deadlineAt(JOB), c.deadlineAt);
  assert.deepEqual(GAPS, { clockMs: c.clockMs, driftMs: c.driftMs, completeMs: c.completeMs, overrunMs: c.overrunMs });
  assert.equal(GAPS.clockMs + GAPS.driftMs + GAPS.completeMs + GAPS.overrunMs, JOB.slackMs);
  assert.equal(MIN_KEPT, c.minKept);
  assert.equal(LIFE_WINDOWS, c.lifeWindows);
  assert.deepEqual({ BODY_MS, TAIL_MS, TAIL_EVERY, MARGIN, MIN_SAMPLES, JOBS_NEEDED }, { BODY_MS: c.bodyMs, TAIL_MS: c.tailMs, TAIL_EVERY: c.tailEvery, MARGIN: c.margin, MIN_SAMPLES: c.minSamples, JOBS_NEEDED: c.jobsNeeded });
  assert.ok(c.jobsNeeded <= c.macSlots);
  assert.ok(c.windowSamples * c.meanMs <= blockMs(c.windowSamples));
  for (const g of golden.filter((x) => x.op === 'step')) {
    const dl = cappedDeadline(JOB, g.elapsedMs, g.capMs);
    assert.equal(dl, g.deadlineMs, g.case);
    assert.equal(stepMinutes(JOB, g.elapsedMs, dl), g.stepMinutes, g.case);
    assert.equal(runsWalk(JOB, g.elapsedMs, dl, MIN_WALK_MINUTES), g.runs, g.case);
    if (g.runs) assert.equal(dl + HARD_STOP_MS < g.elapsedMs + stepMinutes(JOB, g.elapsedMs, dl) * 60000, g.hardStopInside, g.case);
    else assert.equal('hardStopInside' in g, false, g.case);
  }
  for (const g of golden.filter((x) => x.op === 'plan')) {
    const dl = cappedDeadline(JOB, g.elapsedMs, g.capMs);
    assert.equal(dl, g.deadlineMs, g.case);
    assert.equal(repsFit(dl, g.elapsedMs, g.shape, g.arms), g.repsFit, g.case);
    assert.equal(repsLife(g.shape, g.arms), g.repsLife, g.case);
    assert.equal(planReps(dl, g.elapsedMs, g.shape, g.arms), g.reps, g.case);
    assert.equal(outcome(dl, g.elapsedMs, g.shape, g.arms), g.outcome, g.case);
  }
  for (const g of golden.filter((x) => x.op === 'ends')) assert.equal(endsDone(g.shape, g.windows, g.arms, g.pos), g.endsDone, `${g.shape}, ${g.arms} arms, ${g.windows} windows, position ${g.pos}`);
  for (const g of golden.filter((x) => x.op === 'block')) assert.equal(blockMs(g.windows), g.blockMs, `${g.windows} windows`);
  for (const g of golden.filter((x) => x.op === 'groups')) {
    const n = groupsFor(deadlineAt(JOB), g.elapsedMs, g.shape, g.controls, g.candidates);
    assert.equal(n, g.groups, g.case);
    assert.equal(n === null ? null : groupArms(g.controls, g.candidates, n), g.groupArms, g.case);
  }
  for (const g of golden.filter((x) => x.op === 'jobs')) {
    const decisive = g.verdicts.filter((v) => v !== 'insufficient').length;
    assert.equal(decisive, g.decisive);
    assert.equal(g.verdicts.length - decisive, g.lost);
    assert.equal(decisive >= MIN_SAMPLES, g.across !== 'insufficient');
  }
  for (const g of golden.filter((x) => x.op === 'start')) {
    assert.equal(startsWindow(g.deadlineMs, g.nowMs, g.reserveMs), g.starts, g.case);
    assert.equal(remaining(g.deadlineMs, g.nowMs), g.remainingMs, g.case);
  }
});

test('planWalk: the step timeout plus the post steps end inside the job timeout for any start before the deadline', () => {
  const jobStartMs = 1_000_000_000_000;
  for (const elapsed of [0, 60_000, 276_000, 900_000, 1_400_000, 1_500_000]) {
    const p = planWalk({ jobStartMs, nowMs: jobStartMs + elapsed });
    assert.equal(p.run, true);
    assert.ok(elapsed + p.stepMinutes * 60000 + JOB.postMs + JOB.slackMs <= JOB.timeoutMs);
    assert.equal(p.deadlineMs, jobStartMs + deadlineAt(JOB));
    assert.ok(elapsed + p.hardStopSeconds * 1000 <= elapsed + p.stepMinutes * 60000 + 1000);
  }
  assert.equal(planWalk({ jobStartMs, nowMs: jobStartMs + 1_800_000 }).run, false);
  const capped = planWalk({ jobStartMs, nowMs: jobStartMs + 276_000, capMin: 8 });
  assert.equal(capped.deadlineMs, jobStartMs + 756_000);
  assert.equal(capped.hardStopSeconds, 525);
});

test('the CLI prints the four step outputs', () => {
  const out = execFileSync(process.execPath, [fileURLToPath(new URL('../src/walk-budget.mjs', import.meta.url)), '--job-start-ms', '1000000000000', '--now-ms', '1000000276000', '--cap-min', '8'], { encoding: 'utf8' });
  assert.equal(out, 'run=true\nstep_minutes=10\ndeadline_ms=1000000756000\nhard_stop_seconds=525\n');
});

test('untilDeadline: a promise that never settles is abandoned at the deadline, a fast one wins, a rejection passes through', async () => {
  const dl = Date.now() + 60;
  assert.equal(await untilDeadline(new Promise(() => {}), dl), 'deadline');
  assert.ok(Date.now() >= dl - 5);
  assert.equal(await untilDeadline(Promise.resolve(1), Date.now() + 5000), 'done');
  await assert.rejects(untilDeadline(Promise.reject(new Error('boom')), Date.now() + 5000), /boom/);
  const late = new Promise((_, rej) => setTimeout(() => rej(new Error('late')), 100));
  assert.equal(await untilDeadline(late, Date.now() + 20), 'deadline');
  await new Promise((r) => setTimeout(r, 150));
});

test('rep plan: windows done in rep-major order give every arm the Lean count, and an ok plan reaches the kept minimum', () => {
  for (const shape of ['full', 'endOnly']) {
    const per = shape === 'full' ? 2 : 1;
    for (const arms of [1, 2, 3, 4]) {
      for (let n = 0; n <= per * arms * 6; n++) {
        const counts = Array.from({ length: arms }, (_, pos) => endsDone(shape, n, arms, pos));
        const walked = Array.from({ length: arms }, () => 0);
        for (let i = 0; i < n; i++) if (i % per === per - 1) walked[Math.floor((i % (per * arms)) / per)]++;
        assert.deepEqual(counts, walked, `${shape}, ${arms} arms, ${n} windows`);
        assert.ok(Math.max(...counts) - Math.min(...counts) <= 1);
      }
    }
  }
  const dl = cappedDeadline(JOB, 276000, null);
  assert.equal(outcome(dl, 276000, 'endOnly', 3), 'ok');
  for (let pos = 0; pos < 3; pos++) assert.ok(endsDone('endOnly', planReps(dl, 276000, 'endOnly', 3) * 3, 3, pos) >= MIN_KEPT);
  assert.equal(outcome(dl, 276000, 'full', 4), 'lifeShort');
  assert.equal(outcome(dl, 276000, 'full', 3), 'budgetShort');
  assert.equal(outcome(dl, 700000, 'endOnly', 3), 'budgetShort');
});

test('plan: an ok plan reserves its block budget inside the deadline, and the jobs fit the free slots', () => {
  const dl = deadlineAt(JOB);
  for (const shape of ['full', 'endOnly']) for (let arms = 1; arms <= 6; arms++) for (let now = 0; now <= dl; now += 25_000) {
    assert.ok(blockMs(planReps(dl, now, shape, arms) * windowsPerRep(shape, arms)) <= dl - now, `${shape} ${arms} ${now}`);
    if (outcome(dl, now, shape, arms) === 'ok') assert.ok(now + blockMs(MIN_KEPT * windowsPerRep(shape, arms)) <= dl);
  }
  assert.ok(JOBS_NEEDED <= 5);
});

test('planSim: the plan clock reads the time it is given, the driver picks end-only windows, a short plan names the jobs that would fit', () => {
  const dl = 1_000_000_000_000 + deadlineAt(JOB);
  const at = (sec, over = {}) => planSim({ deadlineMs: dl, nowMs: 1_000_000_000_000 + sec * 1000, touchOn: true, armIds: ['orig', 'base', 'aa'], ...over });
  assert.deepEqual(at(276), { shape: 'endOnly', wins: ['end'], repPlan: { shape: 'endOnly', outcome: 'ok', reps: 6, groups: 1 }, reps: 6 });
  assert.equal(at(696).reps, 5);
  assert.equal(at(697).repPlan.outcome, 'budgetShort');
  assert.equal(at(276, { repsArg: '2' }).reps, 2);
  const five = at(276, { armIds: ['orig', 'base', 'aa', 'look', 'v2'] });
  assert.deepEqual([five.repPlan.outcome, five.repPlan.groups], ['budgetShort', 2]);
  const full = at(276, { touchOn: false });
  assert.deepEqual([full.shape, full.wins, full.repPlan.outcome], ['full', ['hero', 'end'], 'budgetShort']);
  assert.deepEqual(at(276, { deadlineMs: null }).repPlan, null);
  assert.equal(at(276, { deadlineMs: null }).reps, 12);
});

test('smoothness.yml: the simulator matrix has the Lean job count, the control job comes after them, and max-parallel is the free macOS slots', () => {
  const c = golden.find((g) => g.op === 'constants');
  const yml = readFileSync(new URL('../../../.github/workflows/smoothness.yml', import.meta.url), 'utf8');
  const sim = yml.slice(yml.indexOf('  webkit-sim:'));
  const lists = [...sim.slice(0, sim.indexOf('    env:')).matchAll(/'\[([\d,]+)\]'/g)].map((m) => m[1].split(',').map(Number));
  assert.deepEqual(lists, [[1, 2], Array.from({ length: c.jobsNeeded + 1 }, (_, i) => i + 1), Array.from({ length: c.jobsNeeded }, (_, i) => i + 1)]);
  assert.match(sim, new RegExp(`max-parallel: ${c.macSlots}\\n`));
  assert.match(sim, new RegExp(`matrix.job == ${c.jobsNeeded + 1} && 'safari'`));
  assert.match(yml.slice(yml.indexOf('Morph runs')), /FW_MATRIX_JOB: \$\{\{ matrix.job \}\}/);
});
