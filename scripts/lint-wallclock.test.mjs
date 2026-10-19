// Tests of scripts/lint-wallclock.mjs: the decision equals the Lean golden (Fw.Console.WallClock), the lexing finds each
// kind of site, a new bound is refused, a reason or a sleep or an env knob is not, and the repo is clean. The code lines
// the lint must classify are fixtures in scripts/lint-wallclock-cases/*.txt (outside the lint's scope, read here).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { SCOPE, isBound, lintText, reasonOk, refuse, run, sites, staleAllow } from './lint-wallclock.mjs';

const root = join(dirname(new URL(import.meta.url).pathname), '..');
const golden = readFileSync(join(root, 'packages/contracts/golden/console/wallclock.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const fixture = (n) => readFileSync(join(root, 'scripts/lint-wallclock-cases', n), 'utf8');
const f = 'apps/runner/test/x.test.ts';

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

test('reasonOk: exactly the Lean whitespace set (space, tab, cr, lf) is blank', () => {
  for (const ch of [' ', '\t', '\r', '\n']) assert.equal(reasonOk(ch), false);
  for (const ch of ['\v', '\f', ' ', 'x']) assert.equal(reasonOk(ch), true);
});

test('sites: each kind of literal (fixture sites.txt: expected, tab, line)', () => {
  const rows = fixture('sites.txt').split('\n').filter((l) => l.includes('\t'));
  assert.ok(rows.length >= 13);
  for (const row of rows) {
    const [want, line] = row.split('\t');
    assert.deepEqual(sites(line).map((s) => `${s.site}:${s.ms}`), want ? [want] : [], line);
  }
});

test('a counted loop around a sleep is a bound; an uncapped poll and a counted loop without a sleep are not', () => {
  assert.equal(lintText(f, fixture('loop-capped.txt'), []).map((x) => x.site).join(), 'loopCap');
  assert.deepEqual(lintText(f, fixture('loop-uncapped.txt'), []), []);
});

test('a new absolute bound is refused; a reason, a sleep or an env knob is not', () => {
  const bad = lintText(f, fixture('bound.txt'), []);
  assert.equal(bad.length, 1);
  assert.equal(bad[0].line, 2);
  const line = fixture('bound-line.txt');
  const allow = [{ file: f, text: line.trim().slice(line.indexOf('toBeLessThan') ), reason: 'hang catcher' }];
  assert.deepEqual(lintText(f, line, allow), []);
  assert.equal(lintText(f, line, [{ ...allow[0], reason: '  ' }]).length, 1);
  assert.equal(lintText(f, line, [{ ...allow[0], file: 'other.test.ts' }]).length, 1);
  assert.deepEqual(lintText(f, fixture('sleep.txt'), []), []);
  assert.deepEqual(lintText(f, fixture('env-knob.txt'), []), []);
});

test('a stale allow entry is reported', () => {
  const texts = new Map([['a.test.ts', fixture('stale-text.txt')]]);
  assert.equal(staleAllow([{ file: 'a.test.ts', text: fixture('stale-key.txt').trim(), reason: 'r' }], texts).length, 1);
});

test('scope covers every land-selected test dir', () => {
  const inScope = (p) => SCOPE.some((re) => re.test(p));
  for (const p of ['apps/runner/test/a.test.ts', 'apps/console-web/test/a.test.tsx', 'packages/difftest/test/a.test.mjs', 'packages/premise-tests/test/a.test.mjs',
    'packages/gh-budget/test/util.ts', '.github/scripts/gate-jobs.test.mjs', 'scripts/ci-paths.test.mjs', 'apps/site/src/parts/hero/x.test.ts']) assert.ok(inScope(p), p);
  assert.ok(!inScope('scripts/lint-wallclock-cases/bound.txt'));
});

test('the repo has no refused bound', () => {
  assert.deepEqual(run(root), []);
});
