// The exit code of `cli.mjs summary` is Lean's (lean/Fw/Gate/Exit.lean: runExit_zero_iff, exit_zero_iff_all_cells, universe_identity,
// narrowed_never_zero, exemptions_enumerated, rollup_pass_iff_all_readings, exit_ne_zero_of_cell). The TS stand-in in cli.mjs is
// checked against the Lean-generated golden vectors in packages/contracts/golden/gate/exit.jsonl, which also carry the exemption
// registry and the universe cli.mjs reads.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { engineVerdictCells, exitCode, runExit, engineOfSummary, loadRegistry, excuseReading, readingOk, readingsTable, tableCellOfWire, universeDiff, waitUnsettled, wireKeys } from '../src/cli.mjs';
import { staleComparable } from '../src/settle.mjs';
import { loadAnchors, loadGen, sweepDefs } from '../src/spec.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(resolve(here, '../../contracts/golden/gate/exit.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const engines = golden.filter((x) => x.kind === 'engine');
const readings = (g) => g.cells.flatMap((c) => c[2]);
const own = (cells) => wireKeys(cells);
const TRUTH_ROWS = ['matchMedia orig=rewrite', 'matchMedia =Lean', 'matchMedia legacy text'];

test('golden: the file has the registry, the universe, the narrowed excuse and every kind of case', () => {
  assert.equal(golden.filter((g) => g.kind === 'exemption').length, 9);
  assert.equal(golden.filter((g) => g.kind === 'universe').length, 1);
  assert.equal(golden.filter((g) => g.kind === 'narrowed').length, 1);
  assert.ok(engines.length >= 55);
  assert.ok(golden.filter((g) => g.kind === 'exit').length >= 15);
  assert.ok(golden.filter((g) => g.kind === 'stale').length >= 8);
  assert.ok(engines.every((g) => Array.isArray(g.universe)));
});

test('the universe is the table summary.mjs builds: the matchMedia rows and the anchors parts, the matrix blocks and the sweep stops', () => {
  const u = golden.find((g) => g.kind === 'universe');
  const { gen } = loadGen();
  assert.deepEqual([...u.rows].sort(), [...TRUTH_ROWS, ...Object.keys(loadAnchors().parts)].sort());
  assert.deepEqual(u.rows.slice(0, 3), TRUTH_ROWS);
  const cols = [...gen.matrix.blocks.map((b) => [b.id, gen.matrix.probes.filter((p) => p.block === b.id).map((p) => p.id)]),
    ...sweepDefs(gen).map((s) => [`sweep:${s.id}`, s.stops.map((_, i) => `${s.id}#${i}`)])];
  assert.deepEqual(u.cols, cols);
  assert.equal(u.size, 36 * 196);
  const reg = loadRegistry();
  assert.equal(reg.universe.length, u.size);
  assert.equal(new Set(reg.universe.map((k) => JSON.stringify(k))).size, u.size, 'no key twice');
});

test('the registry cli.mjs reads is the one Lean generated: nine exemptions, each listing its rows and ids (no wildcard), all in the universe', () => {
  const reg = loadRegistry();
  const u = golden.find((g) => g.kind === 'universe');
  const keys = new Set(reg.universe.map((k) => JSON.stringify(k)));
  assert.deepEqual(reg.exemptions.map((x) => x.id), ['webkit-cross-primary-pair', 'webkit-fractional-whole-width', 'chromium-matchmedia-lean-fractional',
    'chromium-touch-1024-no-vector', 'webkit-touch-1024-no-vector', 'chromium-commission-resize-desktop', 'chromium-commission-resize-touch',
    'chromium-commission-resize-pain', 'chromium-commission-typing-resize-desktop']);
  const resizeKeys = reg.exemptions.filter((x) => x.verdict === 'fail').flatMap((x) => x.rows.flatMap((row) => x.ids.map((id) => [x.engine, row, x.col, id].join('|'))));
  const stops = (w, is) => is.map((i) => `${w}#${i}`);
  const want = [...stops('desktop-1512-320-1512', Array.from({ length: 45 }, (_, i) => i + 7)).map((id) => `chromium|commission|sweep:desktop-1512-320-1512|${id}`),
    ...stops('touch-1024-1201', [2, 4]).map((id) => `chromium|commission|sweep:touch-1024-1201|${id}`),
    ...stops('pain-1440-600-1440', [0, 2, 4]).map((id) => `chromium|commission|sweep:pain-1440-600-1440|${id}`),
    ...stops('desktop-1512-320-1512', [17, 18, 19, 29, 39, 40, 41]).map((id) => `chromium|commission.typing|sweep:desktop-1512-320-1512|${id}`)];
  assert.deepEqual(resizeKeys, want, 'the fail exemptions are exactly the 57 Chromium commission readings of run 39139490674');
  for (const x of reg.exemptions) {
    assert.ok(x.verdict !== 'pass', x.id);
    if (x.verdict === 'fail') assert.ok(x.engine === 'chromium' && x.premise === 'Fw.Gate.Exit.commission_resize_scope' && x.reason.startsWith('commission port unfaithful under live resize'), x.id);
    assert.ok(x.reason.length > 20 && /^Fw\.Gate\.[A-Za-z0-9_.]+$/.test(x.premise), x.id);
    assert.ok(Array.isArray(x.rows) && x.rows.length > 0 && Array.isArray(x.ids) && x.ids.length > 0, x.id);
    assert.ok(!('row' in x), x.id);
    for (const row of x.rows) for (const id of x.ids) assert.ok(keys.has(JSON.stringify([row, x.col, id])), `${x.id} ${row} ${id}`);
  }
  const byId = Object.fromEntries(reg.exemptions.map((x) => [x.id, x]));
  assert.deepEqual(byId['webkit-cross-primary-pair'].rows, u.rows);
  assert.deepEqual(byId['webkit-fractional-whole-width'].rows, u.rows);
  assert.deepEqual(byId['chromium-matchmedia-lean-fractional'].rows, ['matchMedia =Lean']);
  assert.deepEqual(byId['chromium-matchmedia-lean-fractional'].ids, ['fractional-gaps-600.5', 'fractional-gaps-640.5', 'fractional-gaps-860.5', 'fractional-gaps-1000.5']);
  assert.equal(byId['chromium-matchmedia-lean-fractional'].premise, 'Fw.Gate.Exit.fractional_chromium_lean_na');
  for (const x of reg.exemptions.filter((y) => y.id.endsWith('touch-1024-no-vector'))) {
    assert.deepEqual(x.ids, ['touch-1024-1201#0', 'touch-1024-1201#2', 'touch-1024-1201#4']);
    assert.deepEqual(x.rows, ['matchMedia =Lean']);
    assert.equal(x.premise, 'Fw.Gate.touch1024_lean_na');
  }
  assert.equal(reg.narrowedId, 'narrowed-run');
});

test('golden: every engine case (verdict, unsettled count, excused readings, first error) matches Lean', () => {
  for (const g of engines) {
    const run = () => engineVerdictCells(g.engine, g.narrowed, g.cells, g.waits, g.universe);
    if (g.error !== undefined) assert.throws(run, (e) => e.message === g.error, JSON.stringify(g));
    else {
      const r = run();
      assert.equal(r.verdict, g.verdict, JSON.stringify(g));
      assert.equal(r.unsettled, g.unsettled, JSON.stringify(g));
      assert.deepEqual(r.exempt, g.exempt, JSON.stringify(g));
    }
  }
});

test('golden: the universe cases (a missing, extra, doubled or misplaced reading is refused; a permutation is not; a narrowed run is not)', () => {
  const ok = engines.filter((g) => g.error === undefined);
  const perm = (g) => universeDiff(wireKeys(g.cells), g.universe).identical;
  assert.ok(ok.filter((g) => !g.narrowed && !perm(g)).length >= 5);
  assert.ok(ok.filter((g) => !g.narrowed && !perm(g)).every((g) => g.verdict === 'refused'));
  assert.ok(ok.filter((g) => perm(g) || g.narrowed).every((g) => g.verdict !== 'refused'));
  assert.ok(ok.some((g) => g.narrowed && !perm(g) && g.verdict === 'pass'));
  assert.ok(ok.some((g) => perm(g) && JSON.stringify(wireKeys(g.cells)) !== JSON.stringify(g.universe) && g.verdict === 'pass'));
});

test('golden: the cases cover the rule (an unexcused not-comparable or unreachable reading is not a pass, even beside passes; a fail is excused only as a listed commission-resize reading)', () => {
  const ok = engines.filter((g) => g.error === undefined && g.verdict !== 'refused');
  const unexcused = (g, name) => g.cells.some(([row, col, rs]) => rs.some(([id, n]) => (name instanceof RegExp ? name.test(n) : n === name)
    && excuseReading(g.engine, row, col, { id, v: n }) === null));
  assert.ok(ok.filter((g) => unexcused(g, 'not-comparable')).every((g) => g.verdict !== 'pass'));
  assert.ok(ok.filter((g) => unexcused(g, /^unreachable/)).every((g) => g.verdict !== 'pass'));
  assert.ok(ok.filter((g) => unexcused(g, 'fail')).every((g) => g.verdict === 'fail'));
  assert.ok(ok.some((g) => readings(g).some((r) => r[1] === 'fail') && !unexcused(g, 'fail') && g.verdict === 'pass'));
  assert.ok(ok.filter((g) => !g.narrowed && g.cells.some((c) => c[2].length === 0)).every((g) => g.verdict !== 'pass'));
  assert.ok(ok.filter((g) => g.narrowed && g.cells.some((c) => c[2].length === 0)).some((g) => g.verdict === 'pass'));
  assert.ok(ok.some((g) => g.exempt.length > 0 && g.verdict === 'pass'));
  const mixed = ok.filter((g) => g.cells.some(([, , rs]) => rs.some((r) => r[1] === 'pass') && rs.some((r) => r[1] === 'not-comparable')));
  assert.ok(mixed.some((g) => g.verdict === 'incomplete'));
  assert.ok(mixed.some((g) => g.verdict === 'pass'));
});

test('golden: pass iff the keys are the universe (or the run is narrowed), no wait unsettled, every reading ok and some reading passed', () => {
  const reg = loadRegistry();
  for (const g of engines.filter((x) => x.error === undefined)) {
    const cs = g.cells.map(([row, col, rs]) => tableCellOfWire(row, col, rs));
    const allOk = cs.every((c) => (c.readings.length === 0 ? g.narrowed : c.readings.every((r) => readingOk(g.engine, c.row, c.col, r, reg))));
    const somePass = cs.some((c) => c.readings.some((r) => r.v === 'pass'));
    const ident = g.narrowed || universeDiff(wireKeys(g.cells), g.universe).identical;
    assert.equal(g.verdict === 'pass', ident && g.unsettled === 0 && allOk && somePass, JSON.stringify(g));
  }
});

test('golden: a hysteresis pair is compared only when both waits settled (Lean staleComparable)', () => {
  const gs = golden.filter((x) => x.kind === 'stale');
  for (const g of gs) {
    if (g.error !== undefined) assert.throws(() => { waitUnsettled(g.after); waitUnsettled(g.fresh); }, /unknown outcome/, JSON.stringify(g));
    else assert.equal(staleComparable(g.after, g.fresh), g.comparable, JSON.stringify(g));
  }
});

test('golden: the run exit code from the narrowed flag and the engine verdicts matches Lean', () => {
  const gs = golden.filter((x) => x.kind === 'exit');
  assert.ok(gs.some((g) => g.narrowed) && gs.some((g) => !g.narrowed));
  for (const g of gs) assert.equal(runExit(g.narrowed, g.engines), g.exit, JSON.stringify(g));
});

test('exit 0 exactly when not narrowed and every engine verdict is pass (runExit_zero_iff, narrowed_never_zero), all lists up to length 3', () => {
  const vs = ['pass', 'fail', 'unsettled', 'incomplete', 'notRendered', 'refused'];
  const lists = [[]];
  for (let n = 1; n <= 3; n++) for (const l of lists.filter((x) => x.length === n - 1)) for (const v of vs) lists.push([...l, v]);
  for (const l of lists) {
    assert.equal(exitCode(l) === 0, l.length > 0 && l.every((v) => v === 'pass'), JSON.stringify(l));
    assert.equal(runExit(false, l), exitCode(l));
    assert.equal(runExit(true, l), 1);
  }
});

test('one reading decides (rollup_pass_iff_all_readings): a pass beside any reading that is not excused never passes', () => {
  const base = [['engine.scroll', 'desk', [['p', 'pass']]], ['hero.exit', 'mobile', [['q', 'pass']]]];
  const w = [['settled@1', 'settled@2']];
  assert.equal(engineVerdictCells('chromium', false, base, w, own(base)).verdict, 'pass');
  const names = ['fail', 'not-comparable', 'unreachable:primary-pair', 'unreachable:whole-width', 'unreachable:width-dpr'];
  const touch = (i) => `touch-1024-1201#${i}`;
  const frac = 'fractional-gaps-600.5';
  const cross = 'hover-pointer-cross-1200x900-none-fine';
  const places = [['hero.exit', 'desk', 'a'], ['hero.exit', 'fractional-gaps', 'a'], ['hero.exit', 'fractional-gaps', frac], ['hero.exit', 'hover-pointer-cross', 'a'],
    ['hero.exit', 'hover-pointer-cross', cross], ['hero.exit', 'desk', cross], ['matchMedia =Lean', 'fractional-gaps', 'a'], ['matchMedia =Lean', 'fractional-gaps', frac],
    ['matchMedia orig=rewrite', 'fractional-gaps', frac], ['nobody', 'hover-pointer-cross', cross],
    ['matchMedia =Lean', 'sweep:touch-1024-1201', touch(0)], ['matchMedia =Lean', 'sweep:touch-1024-1201', touch(1)], ['matchMedia =Lean', 'sweep:touch-1024-1201', touch(4)],
    ['hero.exit', 'sweep:touch-1024-1201', touch(0)], ['matchMedia =Lean', 'sweep:phone-rotation', 'phone-rotation#1'],
    ['commission', 'sweep:touch-1024-1201', touch(2)], ['commission', 'sweep:touch-1024-1201', touch(1)], ['commission.typing', 'sweep:touch-1024-1201', touch(2)]];
  const reg = loadRegistry();
  for (const eng of ['chromium', 'playwright-webkit', 'firefox']) for (const narrowed of [false, true]) for (const name of names) for (const [row, col, id] of places) for (const before of [true, false]) {
    const rs = before ? [[id, name], ['z', 'pass']] : [['z', 'pass'], [id, name]];
    const cells = [...base, [row, col, rs]];
    const r = engineVerdictCells(eng, narrowed, cells, w, own(cells));
    const listed = reg.exemptions.some((x) => x.engine === eng && x.col === col && x.verdict === name && x.rows.includes(row) && x.ids.includes(id));
    assert.equal(excuseReading(eng, row, col, { id, v: name }) !== null, listed);
    assert.equal(r.verdict === 'pass', listed, `${eng} ${narrowed} ${row} ${col} ${id} ${name} -> ${r.verdict}`);
    if (name === 'fail') assert.equal(r.verdict, listed ? 'pass' : 'fail');
    if (name === 'fail' && listed) assert.ok(eng === 'chromium' && row === 'commission' && id === touch(2));
  }
  for (const narrowed of [false, true]) {
    const cells = [...base, ['morph.panel', 'desk', []]];
    assert.equal(engineVerdictCells('chromium', narrowed, cells, w, own(cells)).verdict === 'pass', narrowed);
  }
});

test('the touch exemption excuses exactly the three 1024 stops of the Lean row, in both engines, and nothing else', () => {
  const stops = (names) => ['matchMedia =Lean', 'sweep:touch-1024-1201', names.map((n, i) => [`touch-1024-1201#${i}`, n])];
  const base = [['engine.scroll', 'desk', [['p', 'pass']]]];
  const nc = 'not-comparable';
  const judge = (eng, cells) => engineVerdictCells(eng, false, cells, [], own(cells));
  for (const eng of ['chromium', 'playwright-webkit']) {
    assert.equal(judge(eng, [...base, stops([nc, 'pass', nc, 'pass', nc])]).verdict, 'pass');
    assert.deepEqual(judge(eng, [...base, stops([nc, 'pass', nc, 'pass', nc])]).exempt.map((x) => x[2]),
      ['touch-1024-1201#0', 'touch-1024-1201#2', 'touch-1024-1201#4']);
    for (const bad of [[nc, nc, nc, 'pass', nc], [nc, 'pass', nc, nc, nc], ['pass', 'pass', 'pass', 'pass', nc]]) {
      assert.equal(judge(eng, [...base, stops(bad)]).verdict === 'pass', bad.every((n, i) => n === 'pass' || (i % 2 === 0 && n === nc)));
    }
  }
  const rot = ['matchMedia =Lean', 'sweep:phone-rotation', ['pass', nc, 'pass', nc, 'pass'].map((n, i) => [`phone-rotation#${i}`, n])];
  assert.equal(judge('playwright-webkit', [...base, rot]).verdict, 'incomplete');
  assert.equal(judge('chromium', [...base, rot]).verdict, 'incomplete');
});

test('the full universe (identity): every reading of the Lean table passing is a pass; one reading dropped, added, doubled or not comparable is not', () => {
  const reg = loadRegistry();
  const full = new Map();
  for (const [row, col, id] of reg.universe) full.set(`${row}\u0000${col}`, [...(full.get(`${row}\u0000${col}`) ?? []), [id, 'pass']]);
  const cellsOf = (m) => [...m].map(([k, rs]) => [...k.split('\u0000'), rs]);
  const cells = cellsOf(full);
  const judge = (cs, narrowed = false) => engineVerdictCells('chromium', narrowed, cs, [], reg.universe).verdict;
  assert.equal(judge(cells), 'pass');
  const drop = cells.map((c, i) => (i === 7 ? [c[0], c[1], c[2].slice(1)] : c));
  assert.equal(judge(drop), 'refused');
  assert.equal(judge(drop, true), 'pass');
  assert.equal(runExit(true, [judge(drop, true)]), 1);
  assert.equal(judge(cells.slice(1)), 'refused');
  assert.equal(judge([...cells, ['hero.exit', 'desk', [['desk-9999', 'pass']]]]), 'refused');
  assert.equal(judge([...cells, ['hero.exit', 'desk', [['desk-319', 'pass']]]]), 'refused');
  assert.equal(judge([...cells].reverse()), 'pass');
  const nc = cells.map((c) => (c[0] === 'hero.exit' && c[1] === 'desk' ? [c[0], c[1], c[2].map(([id], n) => [id, n === 0 ? 'not-comparable' : 'pass'])] : c));
  assert.equal(judge(nc), 'incomplete');
  assert.notEqual(runExit(false, [judge(nc)]), 0);
  const t = readingsTable('chromium', nc, reg);
  assert.deepEqual([t.total, t.pass, t.excused, t.bad], [7056, 7055, 0, 1]);
  const wk = cells.map((c) => (c[1] === 'fractional-gaps' ? [c[0], c[1], c[2].map(([id]) => [id, 'unreachable:whole-width'])] : c));
  assert.equal(engineVerdictCells('playwright-webkit', false, wk, [], reg.universe).verdict, 'pass');
  const tw = readingsTable('playwright-webkit', wk, reg);
  assert.deepEqual([tw.total, tw.pass, tw.excused, tw.bad], [7056, 7056 - 144, 144, 0]);
});

test('a summary.json engine: narrowed is the --parts flag, never the record; a failing, unregistered or missing reading or an unsettled wait is not a pass', () => {
  const w = (orig, rewrite) => ({ orig, rewrite });
  const cellOf = (...vs) => ({ verdict: vs[0], readings: vs.map((v, i) => ({ id: `r${i}`, verdict: v })) });
  const ok = {
    table: { 'matchMedia orig=rewrite': { a: cellOf('pass'), b: cellOf('pass') } },
    probes: [{ verdict: 'pass', wait: w('settled@3', 'settled@4') }],
    sweeps: [{ id: 's', stops: [{ wait: w('settled@2', 'settled@2') }] }],
  };
  const reg = loadRegistry();
  const keysOf = (e) => Object.entries(e.table).flatMap(([row, cols]) => Object.entries(cols).flatMap(([col, t]) => (t.readings ?? []).map((r) => [row, col, r.id])));
  const judge = (e, name = 'chromium', narrowed = false) => engineOfSummary(name, e, narrowed, { ...reg, universe: keysOf(e) });
  assert.equal(judge(ok).verdict, 'pass');
  assert.equal(engineOfSummary('chromium', ok, false, reg).verdict, 'refused');
  assert.throws(() => engineOfSummary('chromium', ok, undefined, reg));
  const withCell = (row, col, ...vs) => ({ ...ok, table: { ...ok.table, [row]: { ...(ok.table[row] ?? {}), [col]: cellOf(...vs) } } });
  assert.equal(judge(withCell('platform.stageBg', 'a', 'fail')).verdict, 'fail');
  assert.equal(judge(withCell('platform.stageBg', 'a', 'pass', 'fail', 'pass')).verdict, 'fail');
  assert.equal(judge(withCell('hero.exit', 'a', 'not-comparable')).verdict, 'incomplete');
  assert.equal(judge(withCell('hero.exit', 'a', 'pass', 'not-comparable')).verdict, 'incomplete');
  assert.equal(judge(withCell('hero.exit', 'fractional-gaps', 'unreachable:whole-width'), 'playwright-webkit').verdict, 'incomplete');
  const fracCell = (row, ...vs) => ({ ...ok, table: { ...ok.table, [row]: { 'fractional-gaps': { verdict: vs[0], readings: vs.map((v, i) => ({ id: ['fractional-gaps-600.5', 'fractional-gaps-640.5'][i], verdict: v })) } } } });
  assert.equal(judge(fracCell('hero.exit', 'unreachable:whole-width')).verdict, 'incomplete');
  assert.equal(judge(fracCell('hero.exit', 'unreachable:whole-width'), 'playwright-webkit').verdict, 'pass');
  assert.deepEqual(judge(fracCell('hero.exit', 'unreachable:whole-width'), 'playwright-webkit').exempt, [['webkit-fractional-whole-width', 'hero.exit|fractional-gaps', 'fractional-gaps-600.5']]);
  assert.equal(judge(fracCell('hero.exit', 'unreachable:whole-width', 'not-comparable'), 'playwright-webkit').verdict, 'incomplete');
  assert.equal(judge(fracCell('matchMedia =Lean', 'not-comparable')).verdict, 'pass');
  assert.equal(judge(fracCell('matchMedia =Lean', 'not-comparable'), 'playwright-webkit').verdict, 'incomplete');
  assert.equal(judge(fracCell('nav.hitTest', 'not-comparable')).verdict, 'incomplete');
  const notRun = (row, col) => ({ ...ok, table: { ...ok.table, [row]: { [col]: { verdict: 'not-run', readings: [] } } } });
  assert.equal(judge(notRun('morph.panel', 'a')).verdict, 'incomplete');
  assert.equal(judge({ ...notRun('morph.panel', 'a'), parts: { covered: ['hero.exit'] } }).verdict, 'incomplete');
  assert.equal(judge({ ...notRun('morph.panel', 'a'), parts: { covered: ['hero.exit'] } }, 'chromium', true).verdict, 'pass');
  const unsettled = { ...ok, probes: [{ verdict: 'pass', wait: w('settled@3', 'unsettled') }] };
  assert.equal(judge(unsettled).verdict, 'unsettled');
  assert.equal(judge(unsettled).unsettled, 1);
  const stopUnsettled = { ...ok, sweeps: [{ id: 's', stops: [{ wait: w('settled@2', 'settled@2') }, { wait: w('unsettled', 'settled@1') }] }] };
  assert.equal(judge(stopUnsettled).verdict, 'unsettled');
  assert.notEqual(exitCode([judge(stopUnsettled).verdict]), 0);
  const flagLies = { ...ok, probes: [{ verdict: 'pass', settled: { orig: true, rewrite: true }, wait: w('unsettled', 'unsettled') }] };
  assert.equal(judge(flagLies).verdict, 'unsettled');
  const noWait = { ...ok, probes: [{ verdict: 'pass', settled: { orig: true, rewrite: true } }] };
  assert.equal(judge(noWait).verdict, 'unsettled');
  const unreach = { ...ok, probes: [...ok.probes, { verdict: 'unreachable:whole-width', wait: w('settled@0', 'settled@0') }] };
  assert.equal(judge(unreach).verdict, 'pass');
  assert.throws(() => judge({ ...ok, table: { r: { a: { verdict: 'pass' } } } }));
});

test('`cli.mjs summary` exits non-zero when it judged no engine, and a --parts run never exits 0 (the process exit code is wired)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gate-exit-'));
  try {
    const r = spawnSync(process.execPath, [resolve(here, '../src/cli.mjs'), 'summary', '--out', dir], { encoding: 'utf8' });
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stdout, /nothing judged/);
    const n = spawnSync(process.execPath, [resolve(here, '../src/cli.mjs'), 'summary', '--out', dir, '--parts', 'hero.exit'], { encoding: 'utf8' });
    assert.equal(n.status, 1, n.stderr);
    assert.match(n.stdout, /never exits 0/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
