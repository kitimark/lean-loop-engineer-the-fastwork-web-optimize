import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readGolden, num, microPx, tolMicro, leanRun, clock, check, checkFile, hasPaddingReads, summarize } from '../src/trajectory/earn-curve.mjs';

const g = readGolden();
const run = (width, seq, engine = 'webkit', arm = 'variant') => leanRun(g, { width, seq, engine, arm, prop: 'padding-left' });

const S = 100;
const FRAME = 50 / 3;

function trace(width, seq, { at = run(width, seq), jitter = 0.3, bump = null } = {}) {
  const pad = { 390: 16, 1280: 24 }[width];
  const from = seq === 'entry' ? pad : 0;
  const rows = [{ t: S - FRAME, nav: '000', cs: { pl: `${from}px`, pr: `${from}px` } }];
  for (let i = 0; i < 48; i++) {
    const t = S + i * FRAME;
    const ct = i === 0 ? 0 : Math.round(i * FRAME + (i % 2 ? jitter : -jitter));
    let px = Math.round(microPx(g, num(g, at, seq === 'entry' ? 0 : pad, (t - S) * 1000))) / 1e6;
    if (bump && bump.i === i + 1) px += bump.px;
    rows.push({ t, nav: '100', cs: { pl: `${px}px`, pr: `${px}px` }, an: [['earn', 'padding-left', 1, ct, 'running']] });
  }
  return rows;
}

test('the BigInt port gives every Lean curve sample exactly', () => {
  const rows = g.rows.filter((r) => r.fn === 'sample');
  assert.equal(rows.length, 176);
  for (const r of rows) {
    const v = num(g, run(r.in.width, r.in.seq), 0, r.in.tUs);
    assert.equal(v.toString(), r.out.num, JSON.stringify(r.in));
  }
});

test('the tolerance port gives every Lean tol row', () => {
  const rows = g.rows.filter((r) => r.fn === 'tol');
  assert.ok(rows.length > 0);
  for (const r of rows) assert.equal(tolMicro(g, r.in.deltaPx, r.in.jUs, r.in.eUs, r.in.durUs), r.out.tolMicro, JSON.stringify(r.in));
});

test('the clock takes the median start over running rows and its spread plus 0.5 ms rounding as jitter', () => {
  const rows = trace(390, 'entry');
  const c = clock(rows, 1);
  assert.ok(Math.abs(c.startMs - S) < 0.5);
  assert.ok(c.jitterUs >= 500 && c.jitterUs <= 1500, String(c.jitterUs));
  assert.equal(c.live, 47);
  assert.deepEqual(clock([{ t: 3 }, { t: 7 }], 1), { startMs: 7, jitterUs: 500, live: 0 });
});

test('a trace drawn from the curve with frame jitter passes in both widths and both directions', () => {
  for (const width of [390, 1280]) {
    for (const seq of ['entry', 'exit']) {
      const v = check(g, trace(width, seq), { width, toPx: seq === 'entry' ? 0 : { 390: 16, 1280: 24 }[width], run: run(width, seq), engine: 'webkit' });
      assert.equal(v.pass, true, `${width} ${seq} ${JSON.stringify(v.worst)}`);
      assert.ok(v.worst.diffMicro < v.tolMicro);
    }
  }
});

test('one frame off the curve by more than the tolerance fails at that frame', () => {
  const v = check(g, trace(1280, 'entry', { bump: { i: 12, px: 0.25 } }), { width: 1280, toPx: 0, run: run(1280, 'entry'), engine: 'chromium' });
  assert.equal(v.pass, false);
  assert.equal(v.worst.i, 12);
  assert.ok(v.worst.diffMicro > v.tolMicro);
});

test('a snap fails the curve and passes the snap model', () => {
  const snap = trace(390, 'entry', { at: null });
  const curve = check(g, snap, { width: 390, toPx: 0, run: run(390, 'entry', 'chromium', 'faithful'), engine: 'webkit' });
  assert.equal(curve.pass, false);
  assert.equal(curve.worst.diffMicro, 16000000);
  assert.equal(run(390, 'entry', 'webkit', 'faithful'), null);
  assert.equal(check(g, snap, { width: 390, toPx: 0, run: null, engine: 'webkit' }).pass, true);
});

test('a trace without a flip fails with its reason', () => {
  const rows = trace(390, 'exit').map((x) => ({ ...x, nav: '000' }));
  assert.deepEqual(check(g, rows, { width: 390, toPx: 16, run: run(390, 'exit'), engine: 'webkit' }), { pass: false, why: 'no flip', frames: 0 });
});

test('geometry-only traces are skipped and the rest are checked per arm against the own run and the curve', () => {
  const json = {
    runs: [
      { width: 390, role: 'flag', mode: 'full', rep: 0, sequences: { 'hero-entry': { rows: trace(390, 'entry') } } },
      { width: 390, role: 'faithful', mode: 'full', rep: 0, sequences: { 'hero-entry': { rows: trace(390, 'entry', { at: null }) } } },
      { width: 390, role: 'flag', mode: 'light', rep: 1, sequences: { 'hero-entry': { rows: [{ t: 1, earn: [0, 0, 1, 1] }] } } },
      { width: 390, role: 'orig', mode: 'full', rep: 0, sequences: { 'hero-entry': { rows: trace(390, 'entry') } } },
    ],
  };
  assert.equal(hasPaddingReads(json.runs[2].sequences['hero-entry'].rows), false);
  const out = checkFile(g, json, 'playwright-webkit');
  assert.equal(out.length, 3);
  assert.deepEqual(out.map((t) => [t.arm, t.skipped ?? null, t.own?.pass ?? null, t.curve?.pass ?? null]), [
    ['variant', null, true, true],
    ['faithful', null, true, false],
    ['variant', 'no padding reads', null, null],
  ]);
  const s = summarize(out);
  assert.deepEqual(s.map((x) => [x.arm, x.traces, x.ownPass, x.curvePass]), [['variant', 1, 1, 1], ['faithful', 1, 1, 0]]);
});
