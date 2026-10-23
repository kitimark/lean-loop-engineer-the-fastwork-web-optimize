// The morph phase rule agrees with the Lean golden (Fw.Measure.WebKitLagPhase, golden/measure/webkit-lag.jsonl) and the report uses it.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MIN_FRAMES, phaseOf, framePhases, classify, rangesOf, phaseRanges } from '../src/lag/phase.mjs';
import { analyzeArm, MORPH_PHASES } from '../src/lag/report.mjs';
import { MORPH_FRAMES } from '../src/lag/probe.mjs';
import { reduceSteps } from '../src/reduce.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/measure/webkit-lag.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('the minimum frame counts are the Lean ones', () => {
  const [c] = of('phaseConst');
  assert.deepEqual({ ...MIN_FRAMES }, { idle: c.minIdle, open: c.minOpen, close: c.minClose });
});

test('classify and the per-frame phases agree with every golden case', () => {
  const cases = of('phase');
  assert.ok(cases.length >= 15);
  for (const g of cases) {
    const c = classify(g.marks, g.down, g.up);
    assert.equal(c.outcome, g.outcome, JSON.stringify([g.down, g.up, g.marks.length]));
    if (g.outcome === 'ok') {
      assert.deepEqual([c.idle, c.open, c.close], [g.idle, g.open, g.close]);
      assert.deepEqual(framePhases(g.marks, g.down, g.up), g.phases);
    }
  }
  for (const o of ['ok', 'noUp', 'noDown', 'order', 'openShort', 'idleShort', 'closeShort', 'unsorted']) assert.ok(cases.some((g) => g.outcome === o), o);
});

test('a push time between two frames splits at the first frame after it', () => {
  assert.equal(phaseOf(19, 139, 18), 'idle');
  assert.equal(phaseOf(19, 139, 19), 'open');
  assert.equal(phaseOf(19, 139, 139), 'close');
});

test('ranges are consecutive blocks over all frames', () => {
  assert.deepEqual(rangesOf({ idle: 11, open: 59, close: 60 }), { idle: [0, 11], open: [11, 70], close: [70, 130] });
});

test('phaseRanges: marks and pushes decide, a run without phase marks keeps the fixed schedule, a refused run is dropped', () => {
  const marks = Array.from({ length: 130 }, (_, i) => 2 * i);
  assert.deepEqual(phaseRanges({ marks, phases: { down: 21, up: 139 } }, MORPH_PHASES), { idle: [0, 11], open: [11, 70], close: [70, 130] });
  assert.equal(phaseRanges({ marks, phases: { down: null, up: 139 } }, MORPH_PHASES), null);
  assert.equal(phaseRanges({ marks, phases: { down: 7, up: 139 } }, MORPH_PHASES), null);
  assert.equal(phaseRanges({ marks }, MORPH_PHASES), MORPH_PHASES);
});

const quad = (x0, y0, x1, y1) => [x0, y0, x1, y0, x1, y1, x0, y1];

/** A 130-frame morph run (frames 1 s apart) whose pushes fall after `idle` frames and `idle + open` frames; Layout rows only in the open phase. */
function morphOf(idle, open) {
  const n = MORPH_FRAMES.idle + MORPH_FRAMES.open + MORPH_FRAMES.close, rows = [], marks = [];
  for (let k = 0; k < n; k++) {
    marks.push(k);
    rows.push(['TimeStamp', k, null, `wk:s${k}`]);
    if (k >= idle && k < idle + open) { rows.push(['Layout', k + 0.5, null, null]); rows.push(['Paint', k + 0.6, null, quad(0, 500, 12, 515)]); }
  }
  rows.push(['TimeStamp', n, null, 'wk:end']);
  return { info: { vw: 100, vh: 100, maxY: 1000 }, marks, endTime: n, records: rows, reduced: reduceSteps(rows, marks, n), phases: { down: idle - 0.5, up: idle + open - 0.5 }, taken: [true, true], scrollTo: 0, before: { morph: '0' }, after: { morph: '0' } };
}

test('the report takes the phase lengths of each run from its marks', () => {
  const ys = [0, 50, 100, 150, 300, 500, 800, 900, 1000];
  const info = { vw: 100, vh: 100, maxY: 1000 };
  const rows = ys.map((_, k) => ['TimeStamp', k, null, `wk:s${k}`]).concat([['TimeStamp', ys.length, null, 'wk:end']]);
  const m = ys.map((_, k) => k);
  const scroll = { info, ys, marks: m, endTime: ys.length, records: rows, reduced: reduceSteps(rows, m, ys.length) };
  const boxes = [{ name: 'platform', rect: [0, 400, 400, 4000] }];
  const geometry = {
    info, ys, census: [{ scrollY: 0, layerCount: 1, memoryBytes: 1, filterLayers: [] }], scroll: ys.map(() => ({ boxes, filters: [] })),
    morph: { before: { morph: '0' }, after: { morph: '0' }, samples: Array.from({ length: 130 }, () => ({ boxes, filters: [] })) },
  };
  const a = analyzeArm([{ geometry, passes: [{ scroll, morph: morphOf(12, 58) }, { scroll, morph: morphOf(10, 60) }, { scroll, morph: morphOf(10, 20) }] }]).morph;
  assert.equal(a.passes, 2);
  assert.equal(a.refused, 1);
  assert.equal(a.idle.frames, 11);
  assert.equal(a.phases.open.frames, 59);
  assert.equal(a.phases.close.frames, 60);
  assert.equal(a.phases.open.table.rows.find((r) => r.name === 'Layout').perFrame, 1);
  assert.equal(a.phases.close.table.rows.find((r) => r.name === 'Layout').perFrame, 0);
});
