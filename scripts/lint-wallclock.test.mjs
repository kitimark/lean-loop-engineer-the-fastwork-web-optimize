// Tests of scripts/lint-wallclock.mjs: the decision equals the Lean golden (Fw.Console.WallClock), the lexing finds each
// kind of site, a new bound is refused, a reason or a sleep or an env knob is not, and the repo is clean.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { isBound, lintText, refuse, run, sites, staleAllow } from './lint-wallclock.mjs';

const root = join(dirname(new URL(import.meta.url).pathname), '..');
const golden = readFileSync(join(root, 'packages/contracts/golden/console/wallclock.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('the golden has cases of every outcome', () => {
  assert.ok(golden.some((c) => c.response.refuse) && golden.some((c) => !c.response.refuse));
});
for (const c of golden) {
  test(`golden: ${c.name}`, () => {
    const { site, ms, reason } = c.request;
    assert.equal(refuse(site, ms, reason), c.response.refuse);
    assert.equal(isBound(site, ms), c.response.bound);
  });
}

test('sites: each kind of literal', () => {
  const one = (l) => sites(l).map((s) => `${s.site}:${s.ms}`);
  assert.deepEqual(one('expect(replayMs).toBeLessThan(5000);'), ['assertLt:5000']);
  assert.deepEqual(one('expect(Date.now() - t0).toBeLessThan(3_000);'), ['assertLt:3000']);
  assert.deepEqual(one('expect(out.split("\\n").length).toBeLessThanOrEqual(40);'), []);
  assert.deepEqual(one('  }, 60_000);'), ['timeoutOpt:60000']);
  assert.deepEqual(one('spawnSync(bin, [], { timeout: 120_000 });'), ['timeoutOpt:120000']);
  assert.deepEqual(one('vi.setConfig({ testTimeout: 35_000 });'), ['timeoutOpt:35000']);
  assert.deepEqual(one('core.callTimeoutForTest(100);'), ['deadlineArg:100']);
  assert.deepEqual(one('const r = ask(bin, q, 30_000);'), ['deadlineArg:30000']);
  assert.deepEqual(one('while (!done && Date.now() - t0 < 80_000) await x;'), ['elapsedCmp:80000']);
  assert.deepEqual(one('await new Promise((r) => setTimeout(r, 300));'), ['sleep:300']);
  assert.deepEqual(one('const wait = (ms) => new Promise((r) => setTimeout(r, ms));'), []);
  assert.deepEqual(one('const D = Number(process.env.FW_TEST_DEADLINE_MS ?? 1500);'), []);
  assert.deepEqual(one('// toBeLessThan(5000) was the old bound'), []);
});

test('a new absolute bound is refused; a reason, a sleep or an env knob is not', () => {
  const f = 'apps/runner/test/x.test.ts';
  const bad = lintText(f, 'it("a", () => {\n  expect(Date.now() - t0).toBeLessThan(2000);\n});', []);
  assert.equal(bad.length, 1);
  assert.equal(bad[0].line, 2);
  const allow = [{ file: f, text: 'toBeLessThan(2000)', reason: 'hang catcher' }];
  assert.deepEqual(lintText(f, 'expect(Date.now() - t0).toBeLessThan(2000);', allow), []);
  assert.equal(lintText(f, 'expect(Date.now() - t0).toBeLessThan(2000);', [{ ...allow[0], reason: '  ' }]).length, 1);
  assert.equal(lintText(f, 'expect(Date.now() - t0).toBeLessThan(2000);', [{ ...allow[0], file: 'other.test.ts' }]).length, 1);
  assert.deepEqual(lintText(f, 'await new Promise((r) => setTimeout(r, 2000));', []), []);
  assert.deepEqual(lintText(f, 'expect(elapsedMs).toBeLessThan(Number(process.env.K ?? 2000));', []), []);
});

test('a stale allow entry is reported', () => {
  const texts = new Map([['a.test.ts', 'expect(x).toBe(1);']]);
  assert.equal(staleAllow([{ file: 'a.test.ts', text: 'toBeLessThan(5)', reason: 'r' }], texts).length, 1);
});

test('the repo has no refused bound', () => {
  assert.deepEqual(run(root), []);
});
