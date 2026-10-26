import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  WKEYS, APPROACH, TOUCH_TAIL, WINDOW_NAMES, endFrame, lastFrame, pushWindows, finishWin, owner, sumRange, runWindows, armVerdicts,
  profileTail, runFromCounts, readArm, cellText, summarizeArm, markdown,
} from '../src/offscreen-windows.mjs';
import { MIN_RUNS, SLACK } from '../src/offscreen.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/offscreen-windows.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);
const profile = JSON.parse(readFileSync(new URL('../profiles/swipe-touch-v1.json', import.meta.url), 'utf8'));

test('offscreen-windows: constants match Lean and the profile', () => {
  const c = ops('constants')[0];
  assert.deepEqual(WKEYS, c.keys);
  assert.equal(APPROACH, c.approach);
  assert.equal(TOUCH_TAIL, c.tail);
  assert.equal(MIN_RUNS, c.minRuns);
  assert.equal(SLACK, c.slack);
  assert.deepEqual(WINDOW_NAMES, c.names);
  assert.equal(profile.id, 'swipe-touch-v1');
  assert.equal(profileTail(profile), c.tail, 'the tail segment of the profile is the Lean constant');
});

test('offscreen-windows: the end frame is the first frame at the largest scroll position', () => {
  assert.ok(ops('end').length >= 7);
  for (const g of ops('end')) assert.equal(endFrame(g.ys), g.end, g.case);
  for (const g of ops('end').filter((x) => x.end !== null)) {
    const e = g.end;
    assert.ok(g.ys.every((y) => y <= g.ys[e]), `${g.case}: nothing above the end frame`);
    assert.ok(g.ys.slice(0, e).every((y) => y < g.ys[e]), `${g.case}: everything before it is below`);
  }
});

test('offscreen-windows: window bounds and owners match Lean, and the push windows partition the finish window', () => {
  assert.ok(ops('windows').length >= 6);
  for (const g of ops('windows')) {
    assert.deepEqual(pushWindows(g.end, g.last), g.windows, g.case);
    assert.deepEqual(finishWin(g.end, g.last), g.finish, g.case);
    g.owners.forEach((o, i) => assert.equal(owner(g.end, g.last, g.ownersFrom + i), o, `${g.case}: frame ${g.ownersFrom + i}`));
    for (let f = g.ownersFrom; f < g.ownersFrom + g.owners.length; f++) {
      const n = g.windows.filter((w) => w.lo <= f && f < w.hi).length;
      assert.equal(n, f >= g.finish.lo && f < g.finish.hi ? 1 : 0, `${g.case}: frame ${f} has one window inside the finish window, none outside`);
    }
    for (let i = 0; i + 1 < g.windows.length; i++) assert.equal(g.windows[i].hi, g.windows[i + 1].lo, `${g.case}: window ${i} abuts the next`);
    assert.equal(g.windows[0].lo, g.finish.lo);
    assert.equal(g.windows.at(-1).hi, g.finish.hi);
    const xs = Array.from({ length: g.last + 10 }, (_, i) => (i * 7) % 11);
    assert.equal(g.windows.reduce((s, w) => s + sumRange(xs, w.lo, w.hi), 0), sumRange(xs, g.finish.lo, g.finish.hi), `${g.case}: window sums add up to the finish sum`);
  }
  const ref = ops('windows')[0];
  assert.deepEqual(ref.windows.map((w) => [w.lo, w.hi]), [[540, 574], [574, 594], [594, 634], [634, 694], [694, 741]]);
  assert.equal(lastFrame(771, TOUCH_TAIL), 741);
});

test('offscreen-windows: a run reduces to the golden end frame and window vectors', () => {
  assert.equal(ops('run').length, 4);
  for (const g of ops('run')) assert.deepEqual(runWindows(g.run), g.result, g.case);
});

const armOf = (rs) => rs.map((r) => ({ end: r.end, windows: r.windows }));

test('offscreen-windows: every arm case gets the golden verdict, usability and cells per window', () => {
  const arms = ops('arm');
  assert.ok(arms.length >= 8);
  assert.deepEqual([...new Set(arms.flatMap((g) => g.verdicts.map((v) => v.verdict)))].sort(), ['gain', 'noData', 'noGain']);
  for (const g of arms) {
    const got = armVerdicts(armOf(g.base), armOf(g.flag));
    assert.deepEqual(got.map((v) => v.window), g.verdicts.map((v) => v.window), g.case);
    for (const [i, v] of g.verdicts.entries()) {
      assert.equal(got[i].verdict, v.verdict, `${g.case}: ${v.window}`);
      assert.equal(got[i].usable, v.usable, `${g.case}: ${v.window} usable`);
      assert.deepEqual(got[i].cells, v.cells, `${g.case}: ${v.window} cells`);
      assert.equal(v.verdict === 'noData', !v.usable, `${g.case}: ${v.window}: no data exactly when not usable`);
    }
  }
});

const frame = (n, scrollY, counts, phase = 'swipe') => ({ n, phase, scrollY, counts });
function fakeCounts(total, e, tail, over = {}) {
  const frames = [];
  for (let n = 0; n < total; n++) {
    const counts = {};
    for (const [j, k] of WKEYS.entries()) if (!(k in over)) counts[k] = (n + j) % 3;
    frames.push(frame(n, Math.min(n, e) * 10, counts, n >= total - tail ? 'tail' : 'swipe'));
  }
  return { profile: { id: 'swipe-touch-v1' }, meta: { search: '?fw=x' }, frames };
}

test('offscreen-windows: counts.json becomes a run, with the failures named', () => {
  const c = fakeCounts(200, 60, 30);
  const run = runFromCounts(c, 30);
  assert.equal(run.ys.length, 200);
  assert.equal(run.ys[60], 600000);
  assert.equal(runWindows(run).end, 60);
  assert.throws(() => runFromCounts(c, 29), /tail/);
  assert.throws(() => runFromCounts({ ...c, profile: { id: 'swipe-v1' } }, 30), /only swipe-touch-v1/);
  assert.throws(() => runFromCounts(fakeCounts(200, 60, 30, { 'trace.Paint': 1 }), 30), /trace\.Paint is in no frame/);
  assert.throws(() => profileTail({ id: 'x', segments: [] }), /no tail/);
});

test('offscreen-windows: readArm reads counts.json at any depth and the table names the changed counters', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ow-'));
  try {
    for (const [arm, drop] of [['b', 0], ['f', 1]]) {
      for (const r of [1, 2, 3]) {
        const d = join(dir, arm, `r${r}`);
        mkdirSync(d, { recursive: true });
        const c = fakeCounts(200, 40, 30);
        if (drop) for (const fr of c.frames.slice(10, 30)) fr.counts['trace.RasterTask'] = 0;
        writeFileSync(join(d, 'counts.json'), JSON.stringify(c));
      }
    }
    const base = readArm(join(dir, 'b'), 30), flag = readArm(join(dir, 'f'), 30);
    assert.equal(base.length, 3);
    assert.deepEqual(base.map((r) => r.end), [40, 40, 40]);
    const s = summarizeArm(base, flag);
    const approach = s.find((w) => w.window === 'approach');
    assert.equal(approach.verdict, 'gain');
    assert.ok(approach.less.some((t) => t.startsWith('RasterTask ')));
    assert.deepEqual(approach.more, []);
    const md = markdown({ f: s }, base);
    assert.match(md, /\| approach \| gain; less: RasterTask/);
    assert.match(md, /End frame per run: 40/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  assert.equal(cellText({ key: 'trace.RasterTask', cmp: 'less', base: [236, 240], flag: [60, 61] }), 'RasterTask 236 to 61');
  assert.equal(cellText({ key: 'trace.FireAnimationFrame', cmp: 'more', base: [400, 401], flag: [402, 403] }), 'FireAnimationFrame 401 to 402');
});
