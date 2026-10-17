import test from 'node:test';
import assert from 'node:assert/strict';
import { stepCounts, framesOf, parseOutput, buildRun } from '../src/reduce.mjs';
import { schedule, harnessSource } from '../src/harness.mjs';
import { injectHarness, SCRIPT_TAG } from '../src/server.mjs';
import { childEnv } from '../src/wktr.mjs';

const S = (rc, sr, ls, extra = {}) => ({ rc, sr, ls, si: 0, lf: rc, lu: 0, cu: 0, ...extra });

test('stepCounts: sums the size only for intervals where a recalc happened', () => {
  const c = stepCounts([S(10, 5, 7), S(11, 5, 7), S(12, 6, 40)]);
  assert.equal(c.styleUpdateSizeSum, 40);
  assert.equal(c.styleRecalcs, 1);
  assert.equal(c.renderingUpdates, 2);
  assert.equal(c.undercountedRecalcs, 0);
  assert.equal(c.lastStyleUpdateSize, 40);
});

test('stepCounts: several recalcs in one interval are flagged as undercounted', () => {
  const c = stepCounts([S(1, 0, 0), S(2, 3, 9)]);
  assert.equal(c.styleUpdateSizeSum, 9);
  assert.equal(c.styleRecalcs, 3);
  assert.equal(c.undercountedRecalcs, 2);
});

test('stepCounts: needs two samples; missing counters count as zero', () => {
  assert.throws(() => stepCounts([S(1, 1, 1)]));
  const c = stepCounts([{ rc: 1 }, { rc: 2 }]);
  assert.equal(c.styleRecalcs, 0);
  assert.equal(c.renderingUpdates, 1);
});

test('framesOf: the next step closes the window, the end sample closes the last', () => {
  const steps = [
    { k: 0, y: 0, b: S(0, 0, 0), mids: [S(1, 1, 5)] },
    { k: 1, y: 50, b: S(2, 1, 5), mids: [] },
  ];
  const f = framesOf(steps, S(3, 2, 8));
  assert.equal(f.length, 2);
  assert.equal(f[0].counts.styleRecalcs, 1);
  assert.equal(f[0].counts.renderingUpdates, 2);
  assert.equal(f[1].counts.styleUpdateSizeSum, 8);
  assert.equal(f[1].phase, 'scroll');
  assert.equal(f[1].scrollY, 50);
});

test('parseOutput + buildRun: round trip, console prefix tolerated', () => {
  const lines = [
    'CONSOLE MESSAGE: FWWKTR meta {"innerWidth":402}',
    'CONSOLE MESSAGE: FWWKTR params {"step":50}',
    `CONSOLE MESSAGE: FWWKTR step ${JSON.stringify({ k: 0, y: 0, b: S(0, 0, 0), mids: [] })}`,
    `CONSOLE MESSAGE: FWWKTR end ${JSON.stringify({ b: S(1, 1, 3) })}`,
    'CONSOLE MESSAGE: FWWKTR done {}',
    'CONSOLE MESSAGE: something else',
  ].join('\n');
  const p = parseOutput(lines);
  assert.equal(p.steps.length, 1);
  assert.equal(p.done, true);
  const run = buildRun(p, { label: 'j1' });
  assert.equal(run.schema, 'fw.wktr.scroll/1');
  assert.equal(run.frames[0].counts.styleUpdateSizeSum, 3);
});

test('buildRun: incomplete output and page errors throw', () => {
  assert.throws(() => buildRun(parseOutput('CONSOLE MESSAGE: FWWKTR meta {}'), {}), /incomplete/);
  assert.throws(() => buildRun(parseOutput('FWWKTR error {"m":"x"}'), {}), /page reported/);
});

test('schedule: step multiples below maxY, then maxY', () => {
  assert.deepEqual(schedule(120, 50), [0, 50, 100, 120]);
  assert.deepEqual(schedule(100, 50), [0, 50, 100]);
  assert.deepEqual(schedule(0, 50), [0]);
});

test('harnessSource: has the parameters substituted and no placeholder left', () => {
  const s = harnessSource({ step: 25, frames: 3, settleMs: 100 });
  assert.ok(!s.includes('__PARAMS__'));
  assert.ok(s.includes('"step":25'));
  assert.ok(s.includes('"frames":3'));
});

test('injectHarness: first child of head; throws without head', () => {
  const out = injectHarness('<!doctype html><html><head lang="x"><meta charset="utf-8"></head><body></body></html>');
  assert.ok(out.includes(`<head lang="x">${SCRIPT_TAG}<meta`));
  assert.throws(() => injectHarness('<html></html>'));
});

test('childEnv: every variable carries the SIMCTL_CHILD_ prefix and the build root', () => {
  const e = childEnv({ port: 1234, root: '/r', tempDir: '/t' });
  assert.ok(Object.keys(e).every((k) => k.startsWith('SIMCTL_CHILD_')));
  assert.equal(e.SIMCTL_CHILD_PORT, '1234');
  assert.equal(e.SIMCTL_CHILD_DYLD_FRAMEWORK_PATH, '/r');
});
