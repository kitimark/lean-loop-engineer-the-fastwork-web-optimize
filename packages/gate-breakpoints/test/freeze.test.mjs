// The frozen-clock decisions (src/freeze.mjs, and the freeze pass inside page.mjs) against the golden file Lean generates
// (packages/contracts/golden/gate/freeze.jsonl, lean/Fw/Gate/Freeze.lean). Nothing is decided here.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { GATE_POLICY } from '../src/settle.mjs';
import { HOLD_LOAD_MS, MAIN_OFF_MS, POST_RESIZE_MS, READY_TO_MS, SLOT_MS, STEP_MS, fits, freezeTime, frozenWait, instant, lateWait, mountRank, newRec, observeAt, ovRank, pageOf, readings, stopBase, viewRank } from '../src/freeze.mjs';
import { KIT_SRC, freezeAnimations } from '../src/page.mjs';
import { PKG } from '../src/serve.mjs';
import { FREEZE_GOLDEN, freezegen } from '../scripts/freezegen.mjs';

const ROOT = resolve(PKG, '../..');
const lines = readFileSync(FREEZE_GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

/** The target function between the markers in freezeAnimations, rebuilt: the very text that runs in the page. */
function pageTarget() {
  const m = /\/\/ <freeze>\s*([\s\S]*?)\s*\/\/ <\/freeze>/.exec(freezeAnimations.toString());
  assert.ok(m, 'marker freeze not found in freezeAnimations');
  return (0, eval)(`(${m[1].replace(/^const \w+ = /, '').replace(/;\s*$/, '')})`);
}

test('freeze.jsonl is the bytes Lean generates', { skip: !existsSync(resolve(ROOT, 'lean/.lake/build')) && 'lean not built' }, () => {
  const r = freezegen(['--check', FREEZE_GOLDEN]);
  assert.equal(r.status, 0, r.stderr);
});

test('the golden file is written with the gate policy and the step the harness uses', () => {
  assert.ok(of('frozenWait').length >= 6);
  for (const l of of('frozenWait')) {
    assert.deepEqual(l.policy, GATE_POLICY, l.name);
    assert.equal(l.stepMs, STEP_MS, l.name);
  }
  assert.match(KIT_SRC, /clock\('step', 16\)/, 'the page kit steps one frame of STEP_MS');
  assert.equal(STEP_MS, 16);
});

test('frozen wait: every golden trace gives the Lean outcome', () => {
  for (const l of of('frozenWait')) {
    const w = frozenWait(l.policy, l.run, l.stable, l.hover);
    assert.equal(w, l.outcome, l.name);
  }
});

test('freeze: the Lean target time, in node and in the page function', () => {
  const target = pageTarget();
  assert.ok(of('freeze').length >= 6);
  for (const l of of('freeze')) {
    const a = l.anim;
    assert.equal(freezeTime(a), l.freezeTime, l.name);
    const timing = { delay: a.delay, duration: a.dur, iterations: a.iterations === null ? Infinity : a.iterations };
    assert.equal(target(timing), l.freezeTime, l.name);
    assert.equal(l.running, false, l.name);
  }
});

test('freeze: a finite animation was running before exactly while its elapsed time is short of its end', () => {
  for (const l of of('freeze')) {
    const a = l.anim;
    const before = a.iterations !== null && a.elapsed < a.delay + a.iterations * a.dur;
    assert.equal(before, l.runningBefore, l.name);
  }
});

/** A fake frozen session: the same contract as engines.mjs freezeClock (advance moves the clock, holdTo never moves it back). */
function mockSession() {
  let elapsed = 0;
  return {
    advance: async (ms) => { elapsed += ms; },
    holdTo: async (abs) => { elapsed += Math.max(0, abs - elapsed); },
    clockMs: () => elapsed,
    evaluate: async () => true,
  };
}
const freezeNoop = () => true;

test('clock constants and the instants are the Lean ones', () => {
  const [c] = of('clock');
  assert.deepEqual({ stepMs: STEP_MS, readyTo: READY_TO_MS, postResize: POST_RESIZE_MS, mainOff: MAIN_OFF_MS, slotMs: SLOT_MS }, { stepMs: c.stepMs, readyTo: c.readyTo, postResize: c.postResize, mainOff: c.mainOff, slotMs: c.slotMs });
  assert.ok(of('instant').length >= 8);
  for (const l of of('instant')) {
    assert.equal(stopBase(l.stop, l.readings), l.base, JSON.stringify(l));
    assert.equal(instant(stopBase(l.stop, l.readings), l.rank), l.value, JSON.stringify(l));
  }
  // Lean mainOff_fits, stopBase_succ, instant_before_next, rank_order
  assert.ok(POST_RESIZE_MS + (GATE_POLICY.maxFrames + 1) * STEP_MS <= MAIN_OFF_MS);
  assert.ok(HOLD_LOAD_MS < READY_TO_MS);
  for (const n of [0, 1, 2, 5]) for (const i of [0, 1, 7]) {
    assert.equal(stopBase(i + 1, n), instant(stopBase(i, n), n + 2));
    assert.ok(instant(stopBase(i, n), n + 1) + SLOT_MS <= stopBase(i + 1, n));
    for (let j = 0; j < n; j++) assert.ok(0 < ovRank(j) && ovRank(j) < mountRank(n) && mountRank(n) < viewRank(n, 0));
  }
});

test('readings and fits: the node twins and the mock session both give the Lean readings', async () => {
  assert.ok(of('readings').length >= 8);
  for (const l of of('readings')) {
    assert.deepEqual(readings(l.start, l.stages), l.readings, l.name);
    assert.equal(fits(l.start, l.stages), l.fits, l.name);
    // the harness path: do the arm's work, hold to the instant, read the clock (observeAt), on a clock that starts at `start`
    const s = mockSession();
    await s.holdTo(l.start);
    const rec = newRec();
    const got = [];
    for (const { work, at } of l.stages) {
      for (const [k, v] of work) await (k === 'rel' ? s.advance(v) : s.holdTo(v));
      await observeAt(s, at, freezeNoop, rec, 'x');
      got.push(s.clockMs());
    }
    assert.deepEqual(got, l.readings, l.name);
    assert.equal(rec.misses.length === 0, l.fits, l.name);
    assert.equal(lateWait(rec) === null, l.fits, l.name);
  }
});

test('pageOf: every golden pair of mount flags gives the Lean page, and only the mounted page runs the mount stage', () => {
  assert.equal(of('page').length, 4);
  for (const l of of('page')) {
    assert.equal(pageOf(l.mountOrig, l.mountRewrite), l.page);
    assert.equal(l.runsMount, l.page === 'mounted');
  }
});

test('both arms are read at the same instants, whatever the original did before (an orig-only mount step)', async () => {
  const base = stopBase(0, 0);
  const run = async (mountMs) => {
    const s = mockSession();
    await s.holdTo(READY_TO_MS);
    const rec = newRec();
    await s.advance(16 * 23);
    const seen = [];
    await observeAt(s, instant(base, 0), freezeNoop, rec, 'main');
    seen.push(s.clockMs());
    await s.advance(mountMs);
    await observeAt(s, instant(base, mountRank(0)), freezeNoop, rec, 'mount');
    seen.push(s.clockMs());
    return { seen, rec };
  };
  const rewrite = await run(0);
  const orig = await run(48 + 150 + 48 + 300 + 16 * 5);
  assert.ok(orig.rec.misses.length === 0 && rewrite.rec.misses.length === 0);
  assert.deepEqual(orig.seen, rewrite.seen);
  assert.deepEqual(orig.seen, [instant(base, 0), instant(base, 1)]);
  // a mount stage longer than one slot is read late: the sample is flagged and unsettled, never read as if it were on time
  const late = await run(SLOT_MS + 1);
  assert.equal(late.rec.misses.length, 1);
  assert.deepEqual(lateWait(late.rec), { outcome: 'unsettled', observations: 0, waitedMs: 0, parked: true });
  assert.notDeepEqual(late.seen, rewrite.seen);
});

test('exit.jsonl is the bytes Lean generates (Fw.Gate.Exit.goldenLines)', { skip: !existsSync(resolve(ROOT, 'lean/.lake/build')) && 'lean not built' }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'exitgen-'));
  try {
    const driver = join(dir, 'ExitGenDriver.lean');
    writeFileSync(driver, 'import Fw.Gate.Exit\ndef main : IO Unit := IO.print (String.intercalate "" (Fw.Gate.Exit.goldenLines.map (· ++ "\\n")))\n');
    const r = spawnSync('lake', ['env', 'lean', '--run', driver], { cwd: resolve(ROOT, 'lean'), encoding: 'utf8', maxBuffer: 1 << 26 });
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stdout, readFileSync(resolve(ROOT, 'packages/contracts/golden/gate/exit.jsonl'), 'utf8'));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
