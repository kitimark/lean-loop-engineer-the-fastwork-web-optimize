// The exit code of `cli.mjs summary` is Lean's (lean/Fw/Gate/Exit.lean: exit_zero_iff, exit_ne_zero_of_*). The TS stand-in
// in cli.mjs is checked against the Lean-generated golden vectors in packages/contracts/golden/gate/exit.jsonl.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { engineVerdict, exitCode, engineOfSummary } from '../src/cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(resolve(here, '../../contracts/golden/gate/exit.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('golden: the golden file has both kinds of case', () => {
  assert.ok(golden.filter((g) => g.kind === 'engine').length >= 8);
  assert.ok(golden.filter((g) => g.kind === 'exit').length >= 8);
});

test('golden: engine verdicts from table cells and the unsettled count match Lean', () => {
  for (const g of golden.filter((x) => x.kind === 'engine')) {
    if (g.error !== undefined) assert.throws(() => engineVerdict(g.cells, g.unsettled), /unknown verdict/, JSON.stringify(g));
    else assert.equal(engineVerdict(g.cells, g.unsettled), g.verdict, JSON.stringify(g));
  }
});

test('golden: the exit code from the engine verdicts matches Lean', () => {
  for (const g of golden.filter((x) => x.kind === 'exit')) assert.equal(exitCode(g.engines), g.exit, JSON.stringify(g));
});

test('exit 0 exactly when every engine verdict is pass (exit_zero_iff), checked over all lists up to length 3', () => {
  const vs = ['pass', 'fail', 'unsettled', 'notRendered'];
  const lists = [[]];
  for (let n = 1; n <= 3; n++) for (const l of lists.filter((x) => x.length === n - 1)) for (const v of vs) lists.push([...l, v]);
  for (const l of lists) assert.equal(exitCode(l) === 0, l.length > 0 && l.every((v) => v === 'pass'), JSON.stringify(l));
  for (const l of lists) if (l.includes('unsettled') || l.includes('notRendered')) assert.notEqual(exitCode(l), 0);
});

test('a summary.json engine with a failing cell, or a probe that did not settle, is not a pass', () => {
  const ok = { table: { 'matchMedia orig=rewrite': { a: { verdict: 'pass' }, b: { verdict: 'not-run' } } }, probes: [{ verdict: 'pass', settled: { orig: true, rewrite: true } }] };
  assert.equal(engineOfSummary(ok).verdict, 'pass');
  const failing = { ...ok, table: { ...ok.table, 'platform.stageBg': { a: { verdict: 'fail' } } } };
  assert.equal(engineOfSummary(failing).verdict, 'fail');
  const unsettled = { ...ok, probes: [{ verdict: 'pass', settled: { orig: true, rewrite: false } }] };
  assert.equal(engineOfSummary(unsettled).verdict, 'unsettled');
  const unreach = { ...ok, probes: [...ok.probes, { verdict: 'unreachable:whole-width', settled: { orig: false, rewrite: false } }] };
  assert.equal(engineOfSummary(unreach).verdict, 'pass');
});

test('`cli.mjs summary` exits non-zero when it judged no engine (the process exit code is wired)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gate-exit-'));
  try {
    const r = spawnSync(process.execPath, [resolve(here, '../src/cli.mjs'), 'summary', '--out', dir], { encoding: 'utf8' });
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stdout, /nothing judged/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
