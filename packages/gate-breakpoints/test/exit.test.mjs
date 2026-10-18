// The exit code of `cli.mjs summary` is Lean's (lean/Fw/Gate/Exit.lean: exit_zero_iff, engine_pass_iff_all_cells,
// rollup_pass_iff_all_readings, exit_ne_zero_of_cell). The TS stand-in in cli.mjs is checked against the Lean-generated golden vectors in
// packages/contracts/golden/gate/exit.jsonl, which also carry the exemption registry cli.mjs reads.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { engineVerdictCells, exitCode, engineOfSummary, loadRegistry, excuseReading, readingOk, tableCellOfWire, waitUnsettled } from '../src/cli.mjs';
import { staleComparable } from '../src/settle.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(resolve(here, '../../contracts/golden/gate/exit.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const engines = golden.filter((x) => x.kind === 'engine');
const readings = (g) => g.cells.flatMap((c) => c[2]);

test('golden: the file has the registry, the narrowed excuse and every kind of case', () => {
  assert.equal(golden.filter((g) => g.kind === 'exemption').length, 5);
  assert.equal(golden.filter((g) => g.kind === 'narrowed').length, 1);
  assert.ok(engines.length >= 45);
  assert.ok(golden.filter((g) => g.kind === 'exit').length >= 8);
  assert.ok(golden.filter((g) => g.kind === 'stale').length >= 8);
});

test('the registry cli.mjs reads is the one Lean generated: five exemptions, none for a pass or a fail, the touch ones name three readings', () => {
  const reg = loadRegistry();
  assert.deepEqual(reg.exemptions.map((x) => x.id), ['webkit-cross-primary-pair', 'webkit-fractional-whole-width', 'chromium-matchmedia-lean-fractional',
    'chromium-touch-1024-no-vector', 'webkit-touch-1024-no-vector']);
  for (const x of reg.exemptions) {
    assert.ok(x.verdict !== 'pass' && x.verdict !== 'fail', x.id);
    assert.ok(x.reason.length > 20 && /^Fw\.Gate\.[A-Za-z0-9_.]+$/.test(x.premise), x.id);
  }
  for (const x of reg.exemptions.filter((y) => y.id.includes('touch'))) {
    assert.deepEqual(x.ids, ['touch-1024-1201#0', 'touch-1024-1201#2', 'touch-1024-1201#4']);
    assert.equal(x.row, 'matchMedia =Lean');
    assert.equal(x.premise, 'Fw.Gate.touch1024_lean_na');
  }
  assert.equal(reg.narrowedId, 'narrowed-run');
});

test('golden: every engine case (verdict, unsettled count, excused readings, first error) matches Lean', () => {
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

test('golden: the cases cover the rule (an unexcused not-comparable or unreachable reading is not a pass, even beside passes; a fail is never excused)', () => {
  const ok = engines.filter((g) => g.error === undefined);
  const unexcused = (g, name) => g.cells.some(([row, col, rs]) => rs.some(([id, n]) => (name instanceof RegExp ? name.test(n) : n === name)
    && excuseReading(g.engine, row, col, { id, v: n }) === null));
  assert.ok(ok.filter((g) => unexcused(g, 'not-comparable')).every((g) => g.verdict !== 'pass'));
  assert.ok(ok.filter((g) => unexcused(g, /^unreachable/)).every((g) => g.verdict !== 'pass'));
  assert.ok(ok.filter((g) => readings(g).some((r) => r[1] === 'fail')).every((g) => g.verdict === 'fail'));
  assert.ok(ok.filter((g) => !g.narrowed && g.cells.some((c) => c[2].length === 0)).every((g) => g.verdict !== 'pass'));
  assert.ok(ok.filter((g) => g.narrowed && g.cells.some((c) => c[2].length === 0)).some((g) => g.verdict === 'pass'));
  assert.ok(ok.some((g) => g.exempt.length > 0 && g.verdict === 'pass'));
  // the rollup that used to pass "some pass and none fail" is gone: a cell with a pass and an unexcused reading is incomplete
  const mixed = ok.filter((g) => g.cells.some(([, , rs]) => rs.some((r) => r[1] === 'pass') && rs.some((r) => r[1] === 'not-comparable')));
  assert.ok(mixed.some((g) => g.verdict === 'incomplete'));
  assert.ok(mixed.some((g) => g.verdict === 'pass'));
});

test('golden: pass iff no wait unsettled, every reading ok, no missing cell outside a narrowed run, and some reading passed (engine_pass_iff_all_readings)', () => {
  const reg = loadRegistry();
  for (const g of engines.filter((x) => x.error === undefined)) {
    const cs = g.cells.map(([row, col, rs]) => tableCellOfWire(row, col, rs));
    const allOk = cs.every((c) => (c.readings.length === 0 ? g.narrowed : c.readings.every((r) => readingOk(g.engine, c.row, c.col, r, reg))));
    const somePass = cs.some((c) => c.readings.some((r) => r.v === 'pass'));
    assert.equal(g.verdict === 'pass', g.unsettled === 0 && allOk && somePass, JSON.stringify(g));
  }
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

test('one reading decides (rollup_pass_iff_all_readings): a pass beside any reading that is not excused never passes', () => {
  const base = [['engine.scroll', 'desk', [['p', 'pass']]], ['hero.exit', 'mobile', [['q', 'pass']]]];
  const w = [['settled@1', 'settled@2']];
  assert.equal(engineVerdictCells('chromium', false, base, w).verdict, 'pass');
  const names = ['fail', 'not-comparable', 'unreachable:primary-pair', 'unreachable:whole-width', 'unreachable:width-dpr'];
  const touch = (i) => `touch-1024-1201#${i}`;
  const places = [['hero.exit', 'desk', 'a'], ['hero.exit', 'fractional-gaps', 'a'], ['hero.exit', 'hover-pointer-cross', 'a'], ['matchMedia =Lean', 'fractional-gaps', 'a'],
    ['matchMedia =Lean', 'sweep:touch-1024-1201', touch(0)], ['matchMedia =Lean', 'sweep:touch-1024-1201', touch(1)], ['matchMedia =Lean', 'sweep:touch-1024-1201', touch(4)],
    ['hero.exit', 'sweep:touch-1024-1201', touch(0)], ['matchMedia =Lean', 'sweep:phone-rotation', 'phone-rotation#1']];
  for (const eng of ['chromium', 'playwright-webkit', 'firefox']) for (const narrowed of [false, true]) for (const name of names) for (const [row, col, id] of places) for (const before of [true, false]) {
    const rs = before ? [[id, name], ['z', 'pass']] : [['z', 'pass'], [id, name]];
    const r = engineVerdictCells(eng, narrowed, [...base, [row, col, rs]], w);
    const excused = excuseReading(eng, row, col, { id, v: name }) !== null;
    assert.equal(r.verdict === 'pass', excused, `${eng} ${narrowed} ${row} ${col} ${id} ${name} -> ${r.verdict}`);
    if (name === 'fail') assert.equal(r.verdict, 'fail');
  }
  // a cell with no reading is excused only by a narrowed run
  for (const narrowed of [false, true]) assert.equal(engineVerdictCells('chromium', narrowed, [...base, ['morph.panel', 'desk', []]], w).verdict === 'pass', narrowed);
});

test('the touch exemption excuses exactly the three 1024 stops of the Lean row, in both engines, and nothing else', () => {
  const stops = (names) => ['matchMedia =Lean', 'sweep:touch-1024-1201', names.map((n, i) => [`touch-1024-1201#${i}`, n])];
  const base = [['engine.scroll', 'desk', [['p', 'pass']]]];
  const nc = 'not-comparable';
  for (const eng of ['chromium', 'playwright-webkit']) {
    assert.equal(engineVerdictCells(eng, false, [...base, stops([nc, 'pass', nc, 'pass', nc])], []).verdict, 'pass');
    assert.deepEqual(engineVerdictCells(eng, false, [...base, stops([nc, 'pass', nc, 'pass', nc])], []).exempt.map((x) => x[2]),
      ['touch-1024-1201#0', 'touch-1024-1201#2', 'touch-1024-1201#4']);
    for (const bad of [[nc, nc, nc, 'pass', nc], [nc, 'pass', nc, nc, nc], ['pass', 'pass', 'pass', 'pass', nc]]) {
      assert.equal(engineVerdictCells(eng, false, [...base, stops(bad)], []).verdict === 'pass', bad.every((n, i) => n === 'pass' || (i % 2 === 0 && n === nc)));
    }
  }
  // WebKit's phone rotation is not excused: its 932 stops are not achieved there
  const rot = ['matchMedia =Lean', 'sweep:phone-rotation', ['pass', nc, 'pass', nc, 'pass'].map((n, i) => [`phone-rotation#${i}`, n])];
  assert.equal(engineVerdictCells('playwright-webkit', false, [...base, rot], []).verdict, 'incomplete');
  assert.equal(engineVerdictCells('chromium', false, [...base, rot], []).verdict, 'incomplete');
});

test('a summary.json engine: a failing reading, an unregistered not-comparable or unreachable reading, a missing cell, or an unsettled wait is not a pass', () => {
  const w = (orig, rewrite) => ({ orig, rewrite });
  const cellOf = (...vs) => ({ verdict: vs[0], readings: vs.map((v, i) => ({ id: `r${i}`, verdict: v })) });
  const ok = {
    table: { 'matchMedia orig=rewrite': { a: cellOf('pass'), b: cellOf('pass') } },
    probes: [{ verdict: 'pass', wait: w('settled@3', 'settled@4') }],
    sweeps: [{ id: 's', stops: [{ wait: w('settled@2', 'settled@2') }] }],
  };
  const judge = (e, name = 'chromium') => engineOfSummary(name, e);
  assert.equal(judge(ok).verdict, 'pass');
  const withCell = (row, col, ...vs) => ({ ...ok, table: { ...ok.table, [row]: { ...(ok.table[row] ?? {}), [col]: cellOf(...vs) } } });
  assert.equal(judge(withCell('platform.stageBg', 'a', 'fail')).verdict, 'fail');
  assert.equal(judge(withCell('platform.stageBg', 'a', 'pass', 'fail', 'pass')).verdict, 'fail');
  assert.equal(judge(withCell('hero.exit', 'a', 'not-comparable')).verdict, 'incomplete');
  assert.equal(judge(withCell('hero.exit', 'a', 'pass', 'not-comparable')).verdict, 'incomplete');
  assert.equal(judge(withCell('hero.exit', 'a', 'unreachable:whole-width')).verdict, 'incomplete');
  assert.equal(judge(withCell('hero.exit', 'fractional-gaps', 'unreachable:whole-width')).verdict, 'incomplete');
  assert.equal(judge(withCell('hero.exit', 'fractional-gaps', 'unreachable:whole-width'), 'playwright-webkit').verdict, 'pass');
  assert.deepEqual(judge(withCell('hero.exit', 'fractional-gaps', 'unreachable:whole-width'), 'playwright-webkit').exempt, [['webkit-fractional-whole-width', 'hero.exit|fractional-gaps', 'r0']]);
  assert.equal(judge(withCell('hero.exit', 'fractional-gaps', 'unreachable:whole-width', 'pass'), 'playwright-webkit').verdict, 'pass');
  assert.equal(judge(withCell('hero.exit', 'fractional-gaps', 'unreachable:whole-width', 'not-comparable'), 'playwright-webkit').verdict, 'incomplete');
  assert.equal(judge(withCell('matchMedia =Lean', 'fractional-gaps', 'not-comparable')).verdict, 'pass');
  assert.equal(judge(withCell('matchMedia =Lean', 'fractional-gaps', 'not-comparable'), 'playwright-webkit').verdict, 'incomplete');
  assert.equal(judge(withCell('nav.hitTest', 'fractional-gaps', 'not-comparable')).verdict, 'incomplete');
  // a block with no verdicts: incomplete in a full run, excused in a run narrowed to parts
  const notRun = (row, col) => ({ ...ok, table: { ...ok.table, [row]: { [col]: { verdict: 'not-run', readings: [] } } } });
  assert.equal(judge(notRun('morph.panel', 'a')).verdict, 'incomplete');
  assert.equal(judge({ ...notRun('morph.panel', 'a'), parts: { covered: ['hero.exit'] } }).verdict, 'pass');
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
  // a table cell without readings (a summary from before the readings) is an error, never a pass
  assert.throws(() => judge({ ...ok, table: { r: { a: { verdict: 'pass' } } } }));
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
