// closegap-did.mjs (parser plus TS stand-in) against the vectors Lean generates (lean/Fw/Gate/RunPerm.lean, golden/gate/run-perm.jsonl).
// `run-perm-cells.jsonl` is the parser's output for the 10 runs of task scoped-gap-did; the golden's `real` lines are Lean's result on it.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { parseRun, identify, runNano, count, verdict, mde, WIDTHS } from '../src/trajectory/closegap-did.mjs';

const read = (f) => readFileSync(fileURLToPath(new URL(`../../contracts/golden/gate/${f}`, import.meta.url)), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const golden = read('run-perm.jsonl'), cells = read('run-perm-cells.jsonl');
const of = (kind) => golden.filter((l) => l.kind === kind);
const near = (a, b, tol = 1) => assert.ok(Math.abs(a - b) <= tol, `${a} vs ${b}`);

test('identify follows the Lean cases', () => {
  for (const l of of('ident')) assert.equal(identify(l.search, l.hash, l.baseHash), l.arm);
});

test('runNano follows the Lean cases, to one unit of 1e-9', () => {
  for (const l of of('stat')) {
    const d = runNano(l.cells);
    if (l.D === null) assert.equal(d, null, l.name);
    else near(d, l.D);
  }
});

test('count and verdict follow the Lean cases, including the 12 and 13 boundary', () => {
  for (const l of of('perm')) {
    const c = count(l.vals, l.labels);
    assert.equal(c.total, l.labelings, l.name);
    assert.equal(c.count, l.count, l.name);
    assert.equal(verdict(c.count, c.total), l.verdict, l.name);
  }
  assert.deepEqual(of('perm').filter((l) => l.name.startsWith('count-1')).map((l) => [l.count, l.verdict]), [[12, 'confirmed'], [13, 'not-shown']]);
});

test('mde follows the Lean cases', () => {
  for (const l of of('mde')) {
    const m = mde(l.a, l.b);
    near(Math.round(m.sd * 1e9), l.sdNano);
    near(Math.round(m.mde * 1e9), l.mdeNano);
  }
});

test('the 10 parsed runs: 5 and 5 by identity, and the same numbers as Lean on the real runs', () => {
  const arms = cells.map((r) => identify(r.search, r.hash, r.baseHash));
  assert.equal(arms.filter((a) => a === 'scoped').length, 5);
  assert.equal(arms.filter((a) => a === 'faithful').length, 5);
  const per = of('real-run'), real = of('real')[0];
  assert.deepEqual(per.map((l) => l.run), cells.map((r) => r.run));
  const ds = cells.map((r) => runNano(r.cells));
  per.forEach((l, i) => { near(ds[i], l.D); assert.equal(l.arm, arms[i]); assert.equal(l.cells, cells[i].cells.length); });
  const c = count(ds, arms);
  assert.equal(c.total, real.labelings);
  assert.equal(c.count, real.count);
  assert.equal(verdict(c.count, c.total), real.verdict);
  const sum = (a) => ds.filter((_, i) => arms[i] === a).reduce((x, y) => x + y, 0);
  near(sum('scoped'), real.sumScoped, 5);
  near(sum('faithful'), real.sumFaithful, 5);
  const m = mde(ds.filter((_, i) => arms[i] === 'scoped').map((d) => d / 1e9), ds.filter((_, i) => arms[i] === 'faithful').map((d) => d / 1e9));
  near(Math.round(m.sd * 1e9), real.sdNano, 5);
  near(Math.round(m.mde * 1e9), real.mdeNano, 5);
});

const row = (rep, t, on) => ({ rep, t, since: t, m: 0, nodes: { nav: [Object.assign([0, 0, on ? 'on' : 'off', 0, 0, 0, 0, 0, 0], { 9: [100000, 0, 0, 1000] })], earn: [[[-1000], 'true', [250], 'blur(#px)', [10000], [30000]]] } });

test('parseRun writes [width, role, g] of every close cell and the identity of the file', () => {
  const raw = {
    search: '?fw=hero.exit:scoped', hash: 'h1', baseHash: 'h0',
    runs: [
      { width: 390, role: 'orig', search: '', want: null, morph: { phases: { close: [row(0, 0, true), row(0, 40, false)] } } },
      { width: 390, role: 'base', search: '', want: null, morph: { phases: { close: [row(0, 0, true), row(0, 50, false)] } } },
      { width: 390, role: 'cand', search: '?fw=hero.exit:scoped', want: null, morph: { phases: { close: [row(0, 0, true), row(0, 60, false)] } } },
      { width: 777, role: 'cand', search: '?fw=hero.exit:scoped', want: null, morph: { phases: { close: [row(0, 0, true), row(0, 9, false)] } } },
    ],
  };
  const r = parseRun(raw, '7');
  assert.deepEqual(r, { run: '7', search: '?fw=hero.exit:scoped', hash: 'h1', baseHash: 'h0', cells: [[390, 0, 40], [390, 1, 50], [390, 2, 60]] });
  assert.equal(identify(r.search, r.hash, r.baseHash), 'scoped');
  assert.deepEqual(WIDTHS, [390, 640, 641, 1280]);
});
