import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  WK_KEYS, END_CUT, ZONES, MIN_VMS, windowSteps, windowVec, sameSteps, verdict, passVerdict, undecided, vmCount, zoneVerdicts, passOf,
} from '../src/offscreen-webkit.mjs';
import { MIN_RUNS, SLACK } from '../../measure-chromium/src/offscreen.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/offscreen-webkit.jsonl', import.meta.url), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);

test('offscreen-webkit: constants match Lean', () => {
  const c = ops('constants')[0];
  assert.deepEqual(WK_KEYS, c.keys);
  assert.equal(END_CUT, c.endCut);
  assert.equal(MIN_RUNS, c.minRuns);
  assert.equal(MIN_VMS, c.minVms);
  assert.equal(SLACK, c.slack);
  assert.deepEqual(ZONES, c.zones);
});

test('offscreen-webkit: windows hold the steps and sums of the golden pass', () => {
  assert.equal(ops('window').length, 4);
  for (const g of ops('window')) {
    assert.deepEqual(windowSteps(g.lo, g.hi, g.pass), g.steps, `${g.lo}-${g.hi}`);
    const v = windowVec(g.lo, g.hi, g.pass);
    assert.equal(v.n, g.vec.n);
    assert.deepEqual(v.vals, g.vec.vals);
  }
});

test('offscreen-webkit: every golden verdict, and its step-set flag, matches Lean', () => {
  const vs = ops('verdict');
  assert.ok(vs.length >= 11);
  assert.deepEqual([...new Set(vs.map((g) => g.verdict))].sort(), ['gain', 'noData', 'noGain']);
  for (const g of vs) {
    assert.equal(sameSteps(g.lo, g.hi, [...g.base, ...g.flag]), g.sameSteps, `${g.case}: step sets`);
    assert.deepEqual([vmCount(g.base), vmCount(g.flag)], g.vms, `${g.case}: VMs`);
    assert.equal(undecided(g.base, g.flag), g.undecided, `${g.case}: undecided`);
    assert.equal(passVerdict(g.lo, g.hi, g.base, g.flag), g.passVerdict, `${g.case}: pass rule`);
    assert.equal(verdict(g.lo, g.hi, g.base, g.flag), g.verdict, g.case);
  }
});

test('offscreen-webkit: equal counts on different steps get no verdict', () => {
  const g = ops('verdict').find((x) => x.case === 'same count, different steps');
  assert.equal(g.sameSteps, false);
  assert.equal(g.verdict, 'noData');
});

test('offscreen-webkit: an arm with fewer than 3 VMs is undecided even when its passes would gain', () => {
  const short = ops('verdict').filter((g) => g.undecided);
  assert.ok(short.some((g) => g.passVerdict === 'gain' && g.vms.includes(2)));
  for (const g of short) assert.equal(g.verdict, 'noData', g.case);
  for (const g of ops('verdict').filter((x) => !x.undecided)) assert.equal(g.verdict, g.passVerdict, g.case);
});

test('offscreen-webkit: an empty or short side is no data in the verdict and the pass rule', () => {
  for (const name of ['no base passes', 'no flag passes', 'flag one pass short', 'one pass short']) {
    const g = ops('verdict').find((x) => x.case === name);
    assert.equal(verdict(g.lo, g.hi, g.base, g.flag), 'noData', name);
    assert.equal(passVerdict(g.lo, g.hi, g.base, g.flag), 'noData', name);
  }
});

test('offscreen-webkit: zones are judged one by one', () => {
  assert.equal(ops('zones').length, 5);
  for (const g of ops('zones')) {
    assert.deepEqual([vmCount(g.base), vmCount(g.flag)], g.vms, `${g.case}: VMs`);
    assert.equal(undecided(g.base, g.flag), g.undecided, `${g.case}: undecided`);
    assert.deepEqual(zoneVerdicts(g.base, g.flag), g.zones.map((z) => [z.zone, z.verdict]), g.case);
  }
});

test('offscreen-webkit: no zone reaches the page-end steps of either pass shape', () => {
  for (const z of ZONES) assert.ok(z.hi <= END_CUT && END_CUT < 5231);
});

test('offscreen-webkit: passOf reads a session pass', () => {
  const p = passOf({ scroll: { ys: [0, 50], reduced: { perStep: [[1], [2]] } } }, 2);
  assert.deepEqual(p, { vm: 2, ys: [0, 50], rows: [[1], [2]] });
});

test('offscreen-webkit-cli: the report row of each zone is the Lean zone verdict', async () => {
  const { report, markdown } = await import('../src/offscreen-webkit-cli.mjs');
  for (const g of ops('zones')) {
    const rows = report([{ name: 'base', passes: g.base }, { name: 'arm', passes: g.flag }]);
    assert.deepEqual(rows.map((r) => [r.zone, r.verdict]), g.zones.map((z) => [z.zone, z.verdict]), g.case);
    assert.deepEqual(rows.map((r) => [r.undecided, r.vms]), rows.map(() => [g.undecided, g.vms]), g.case);
    const md = markdown(rows);
    assert.ok(md.includes('| z4500 |'));
    assert.equal(md.includes(`undecided (n=${g.vms.join('+')} VMs)`), g.undecided, g.case);
  }
});

test('offscreen-webkit-cli: the VM id is the k of the webkit-sim-r<k> artifact dir', async () => {
  const { passesOfDir, vmOfDir } = await import('../src/offscreen-webkit-cli.mjs');
  const root = mkdtempSync(join(tmpdir(), 'owk-'));
  const pass = { scroll: { ys: [4500], reduced: { perStep: [[1]] } } };
  const dir = join(root, 'webkit-sim-r7');
  mkdirSync(dir);
  writeFileSync(join(dir, 'r7-session-1.json'), JSON.stringify({ passes: [pass, pass] }));
  assert.equal(vmOfDir(dir), 7);
  assert.deepEqual(passesOfDir(dir).map((p) => p.vm), [7, 7]);
  const other = join(root, 'run-1');
  mkdirSync(other);
  assert.throws(() => passesOfDir(other), /no VM id/);
  rmSync(root, { recursive: true, force: true });
});
