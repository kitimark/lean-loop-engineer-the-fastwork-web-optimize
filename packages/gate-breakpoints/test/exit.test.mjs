// The exit code of `cli.mjs summary` is Lean's (lean/Fw/Gate/Exit.lean: exit_zero_iff, engine_pass_iff_all_cells,
// exit_ne_zero_of_cell). The TS stand-in in cli.mjs is checked against the Lean-generated golden vectors in
// packages/contracts/golden/gate/exit.jsonl, which also carry the exemption registry cli.mjs reads.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { engineVerdictCells, exitCode, engineOfSummary, loadRegistry, excuse, tableCellOfWire, waitUnsettled } from '../src/cli.mjs';
import { staleComparable } from '../src/settle.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(resolve(here, '../../contracts/golden/gate/exit.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const engines = golden.filter((x) => x.kind === 'engine');

test('golden: the file has the registry, the narrowed excuse and every kind of case', () => {
  assert.equal(golden.filter((g) => g.kind === 'exemption').length, 3);
  assert.equal(golden.filter((g) => g.kind === 'narrowed').length, 1);
  assert.ok(engines.length >= 30);
  assert.ok(golden.filter((g) => g.kind === 'exit').length >= 8);
  assert.ok(golden.filter((g) => g.kind === 'stale').length >= 8);
});

test('the registry cli.mjs reads is the one Lean generated: three exemptions, none for a pass or a fail', () => {
  const reg = loadRegistry();
  assert.deepEqual(reg.exemptions.map((x) => x.id), ['webkit-cross-primary-pair', 'webkit-fractional-whole-width', 'chromium-matchmedia-lean-fractional']);
  for (const x of reg.exemptions) {
    assert.ok(x.verdict !== 'pass' && x.verdict !== 'fail', x.id);
    assert.ok(x.reason.length > 20 && /^Fw\.Gate\.[A-Za-z_.]+$/.test(x.premise), x.id);
  }
  assert.equal(reg.narrowedId, 'narrowed-run');
});

test('golden: every engine case (per-cell verdict, unsettled count, excused cells, first error) matches Lean', () => {
  for (const g of engines) {
    const run = () => engineVerdictCells(g.engine, g.narrowed, g.cells, g.waits);
    if (g.error !== undefined) assert.throws(run, (e) => e.message === g.error, JSON.stringify(g));
    else {
      const r = run();
      assert.equal(r.verdict, g.verdict, JSON.stringify(g));
      assert.equal(r.unsettled, g.unsettled, JSON.stringify(g));
      assert.deepEqual(r.exempt, g.exempt, JSON.stringify(g));
    }
  }
});

test('golden: the cases cover the rule (a not-comparable or unreachable cell with no exemption is not a pass; a fail is never excused)', () => {
  const v = (f) => engines.filter(f).map((g) => g.verdict);
  assert.ok(v((g) => g.cells.some((c) => c[2] === 'not-comparable') && g.exempt.length === 0).every((x) => x !== 'pass'));
  assert.ok(v((g) => g.cells.some((c) => c[2].startsWith('unreachable') ) && g.exempt.length === 0).every((x) => x !== 'pass'));
  assert.ok(v((g) => g.cells.some((c) => c[2] === 'fail')).every((x) => x === 'fail'));
  assert.ok(v((g) => !g.narrowed && g.cells.some((c) => c[2] === 'not-run')).every((x) => x !== 'pass'));
  assert.ok(v((g) => g.narrowed && g.cells.some((c) => c[2] === 'not-run')).includes('pass'));
  assert.ok(engines.some((g) => g.exempt.length > 0 && g.verdict === 'pass'));
});

test('golden: a hysteresis pair is compared only when both waits settled (Lean staleComparable)', () => {
  const gs = golden.filter((x) => x.kind === 'stale');
  for (const g of gs) {
    if (g.error !== undefined) assert.throws(() => { waitUnsettled(g.after); waitUnsettled(g.fresh); }, /unknown outcome/, JSON.stringify(g));
    else assert.equal(staleComparable(g.after, g.fresh), g.comparable, JSON.stringify(g));
  }
});

test('golden: the exit code from the engine verdicts matches Lean', () => {
  for (const g of golden.filter((x) => x.kind === 'exit')) assert.equal(exitCode(g.engines), g.exit, JSON.stringify(g));
});

test('exit 0 exactly when every engine verdict is pass (exit_zero_iff), checked over all lists up to length 3', () => {
  const vs = ['pass', 'fail', 'unsettled', 'incomplete', 'notRendered'];
  const lists = [[]];
  for (let n = 1; n <= 3; n++) for (const l of lists.filter((x) => x.length === n - 1)) for (const v of vs) lists.push([...l, v]);
  for (const l of lists) assert.equal(exitCode(l) === 0, l.length > 0 && l.every((v) => v === 'pass'), JSON.stringify(l));
  for (const l of lists) if (l.some((v) => v !== 'pass')) assert.notEqual(exitCode(l), 0);
});

test('one cell decides (engine_pass_iff_all_cells): every single-cell change of a passing table that is not excused stops the pass', () => {
  const base = [['engine.scroll', 'desk', 'pass'], ['hero.exit', 'mobile', 'pass']];
  const w = [['settled@1', 'settled@2']];
  assert.equal(engineVerdictCells('chromium', false, base, w).verdict, 'pass');
  const names = ['fail', 'not-comparable', 'unreachable:primary-pair', 'unreachable:whole-width', 'unreachable:width-dpr', 'not-run'];
  for (const eng of ['chromium', 'playwright-webkit']) for (const narrowed of [false, true]) for (const name of names) for (const col of ['desk', 'fractional-gaps', 'hover-pointer-cross']) for (const row of ['hero.exit', 'matchMedia =Lean']) {
    const cells = [...base, [row, col, name]];
    const r = engineVerdictCells(eng, narrowed, cells, w);
    const c = tableCellOfWire(row, col, name);
    const excused = excuse(eng, narrowed, c) !== null;
    assert.equal(r.verdict === 'pass', excused, `${eng} ${narrowed} ${row} ${col} ${name} -> ${r.verdict}`);
    if (name === 'fail') assert.equal(r.verdict, 'fail');
  }
});

test('a summary.json engine: a failing cell, an unregistered not-comparable or unreachable cell, a missing cell, or an unsettled wait is not a pass', () => {
  const w = (orig, rewrite) => ({ orig, rewrite });
  const ok = {
    table: { 'matchMedia orig=rewrite': { a: { verdict: 'pass' }, b: { verdict: 'pass' } } },
    probes: [{ verdict: 'pass', wait: w('settled@3', 'settled@4') }],
    sweeps: [{ id: 's', stops: [{ wait: w('settled@2', 'settled@2') }] }],
  };
  const judge = (e, name = 'chromium') => engineOfSummary(name, e);
  assert.equal(judge(ok).verdict, 'pass');
  const withCell = (row, col, verdict) => ({ ...ok, table: { ...ok.table, [row]: { ...(ok.table[row] ?? {}), [col]: { verdict } } } });
  assert.equal(judge(withCell('platform.stageBg', 'a', 'fail')).verdict, 'fail');
  assert.equal(judge(withCell('hero.exit', 'a', 'not-comparable')).verdict, 'incomplete');
  assert.equal(judge(withCell('hero.exit', 'a', 'unreachable:whole-width')).verdict, 'incomplete');
  assert.equal(judge(withCell('hero.exit', 'fractional-gaps', 'unreachable:whole-width')).verdict, 'incomplete');
  assert.equal(judge(withCell('hero.exit', 'fractional-gaps', 'unreachable:whole-width'), 'playwright-webkit').verdict, 'pass');
  assert.deepEqual(judge(withCell('hero.exit', 'fractional-gaps', 'unreachable:whole-width'), 'playwright-webkit').exempt, [['webkit-fractional-whole-width', 'hero.exit|fractional-gaps']]);
  assert.equal(judge(withCell('matchMedia =Lean', 'fractional-gaps', 'not-comparable')).verdict, 'pass');
  assert.equal(judge(withCell('matchMedia =Lean', 'fractional-gaps', 'not-comparable'), 'playwright-webkit').verdict, 'incomplete');
  assert.equal(judge(withCell('nav.hitTest', 'fractional-gaps', 'not-comparable')).verdict, 'incomplete');
  // a block with no verdicts: incomplete in a full run, excused in a run narrowed to parts
  assert.equal(judge(withCell('morph.panel', 'a', 'not-run')).verdict, 'incomplete');
  assert.equal(judge({ ...withCell('morph.panel', 'a', 'not-run'), parts: { covered: ['hero.exit'] } }).verdict, 'pass');
  // a pass table with a probe whose wait ended unsettled on one arm
  const unsettled = { ...ok, probes: [{ verdict: 'pass', wait: w('settled@3', 'unsettled') }] };
  assert.equal(judge(unsettled).verdict, 'unsettled');
  assert.equal(judge(unsettled).unsettled, 1);
  // a pass table with a sweep stop whose wait ended unsettled
  const stopUnsettled = { ...ok, sweeps: [{ id: 's', stops: [{ wait: w('settled@2', 'settled@2') }, { wait: w('unsettled', 'settled@1') }] }] };
  assert.equal(judge(stopUnsettled).verdict, 'unsettled');
  assert.notEqual(exitCode([judge(stopUnsettled).verdict]), 0);
  // the old ready flag says settled, the wait says unsettled: the wait decides
  const flagLies = { ...ok, probes: [{ verdict: 'pass', settled: { orig: true, rewrite: true }, wait: w('unsettled', 'unsettled') }] };
  assert.equal(judge(flagLies).verdict, 'unsettled');
  // a row with no wait recorded is not a pass
  const noWait = { ...ok, probes: [{ verdict: 'pass', settled: { orig: true, rewrite: true } }] };
  assert.equal(judge(noWait).verdict, 'unsettled');
  // an unreachable PROBE row (not a table cell) with settled waits changes nothing; the table decides
  const unreach = { ...ok, probes: [...ok.probes, { verdict: 'unreachable:whole-width', wait: w('settled@0', 'settled@0') }] };
  assert.equal(judge(unreach).verdict, 'pass');
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
