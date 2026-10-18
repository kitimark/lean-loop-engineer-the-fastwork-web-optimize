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
import { GRID_MS, HOLD_LOAD_MS, POST_RESIZE_MS, READY_TO_MS, STEP_MS, alignTarget, freezeTime, frozenWait } from '../src/freeze.mjs';
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

test('the harness grid: a stop plus the settle span fits one grid cell, and the align target is the next multiple', () => {
  assert.ok(POST_RESIZE_MS + (GATE_POLICY.maxFrames + 1) * STEP_MS < GRID_MS);
  assert.ok(HOLD_LOAD_MS < READY_TO_MS && READY_TO_MS < GRID_MS * 6);
  for (const e of [0, 1, 1999, 2000, 10000, 10976, 11999]) {
    const t = alignTarget(e);
    assert.equal(t % GRID_MS, 0);
    assert.ok(t > e && t - e <= GRID_MS);
  }
  // two arms anywhere inside the same cell go to the same instant (Lean alignTarget_eq)
  assert.equal(alignTarget(10000), alignTarget(11975));
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
