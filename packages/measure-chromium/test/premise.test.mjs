// Conformance of the TS port (src/premise-verdict.mjs, src/premise-fixture.mjs) to the Lean golden
// packages/contracts/golden/ops/engine-premises.jsonl (lean/Fw/Ops/EnginePremise.lean).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cell, verdict, evaluate, loadGolden, present, GROUPS, rowName, verdictLines } from '../src/premise-verdict.mjs';
import { pageHtml, stepTable } from '../src/premise-fixture.mjs';

const golden = loadGolden();

test('cell and verdict agree with the Lean vectors', () => {
  assert.ok(golden.cellVectors.length >= 8 && golden.verdictVectors.length >= 7);
  for (const v of golden.cellVectors) assert.equal(cell(v.expect, v.observed), v.cell, JSON.stringify(v));
  for (const v of golden.verdictVectors) assert.equal(verdict(v.cells), v.verdict, JSON.stringify(v));
});

test('the Chromium profile has one frame per golden step', () => {
  const profile = JSON.parse(readFileSync(new URL('../profiles/engine-premise-cr.json', import.meta.url), 'utf8'));
  const frames = profile.segments.filter((s) => s.name !== 'warm').reduce((a, s) => a + s.frames, 0);
  assert.equal(frames, golden.steps.chromium.length);
  assert.equal(profile.input.mode, 'page');
});

test('every step has an expectation for every observer; idle steps follow set steps', () => {
  for (const e of ['chromium', 'webkit']) {
    const stages = golden.observers[e].map((o) => o.stage).sort();
    for (const st of golden.steps[e]) assert.deepEqual(Object.keys(st.expect).sort(), stages, `${e} ${st.case}`);
    golden.steps[e].forEach((st, i) => assert.equal(st.step, i));
  }
  const cr = golden.steps.chromium;
  for (let i = 0; i < cr.length; i += 2) assert.equal(cr[i + 1].act, 'idle');
});

test('the fixture page has one box per set step and the step table mirrors the golden', () => {
  for (const e of ['chromium', 'webkit']) {
    const html = pageHtml(golden, e);
    const sets = golden.steps[e].filter((s) => s.act === 'set');
    assert.equal((html.match(/id="e\d+"/g) ?? []).length, sets.length);
    const table = stepTable(golden, e);
    assert.equal(table.length, golden.steps[e].length);
    for (const [i, s] of golden.steps[e].entries()) assert.equal(table[i].a, s.act);
  }
});

test('evaluate: an exact copy of the expectation holds, one flipped step fails, disagreeing passes are unstable', () => {
  const steps = golden.steps.chromium;
  const countsFor = (flipStep) => steps.map((st) => {
    const c = {};
    for (const o of golden.observers.chromium) {
      let on = st.expect[o.stage];
      if (st.step === flipStep && o.stage === 'layout') on = !on;
      c[o.counters[0]] = on ? 1 : 0;
    }
    return c;
  });
  const ok = evaluate(golden, 'chromium', [countsFor(-1), countsFor(-1), countsFor(-1)]);
  for (const g of GROUPS) for (const s of Object.values(ok.groups[g].stages)) assert.equal(s.verdict, 'holds');
  const bad = evaluate(golden, 'chromium', [countsFor(2), countsFor(2), countsFor(2)]);
  assert.equal(bad.groups.table.stages.layout.verdict, 'fails');
  assert.equal(bad.groups.table.stages.style.verdict, 'holds');
  assert.equal(bad.groups.table.stages.layout.offending[0].step, 2);
  assert.equal(bad.groups.extra.stages.layout.verdict, 'holds');
  const mixed = evaluate(golden, 'chromium', [countsFor(-1), countsFor(2), countsFor(-1)]);
  assert.equal(mixed.groups.table.stages.layout.verdict, 'inconclusive');
  assert.equal(mixed.groups.table.stages.layout.cells.unstable, 1);
  const firstExtra = golden.steps.chromium.find((st) => st.group === 'extra').step;
  const badExtra = evaluate(golden, 'chromium', [countsFor(firstExtra), countsFor(firstExtra), countsFor(firstExtra)]);
  assert.equal(badExtra.groups.extra.stages.layout.verdict, 'fails');
  assert.equal(badExtra.groups.table.stages.layout.verdict, 'holds');
});

test('step sets: every step row names a set of GROUPS, the table set comes first and has 65 + 30 cases', () => {
  for (const e of ['chromium', 'webkit']) {
    for (const st of golden.steps[e]) assert.ok(GROUPS.includes(st.group), `${e} ${st.step} ${st.group}`);
    const groups = golden.steps[e].map((st) => st.group);
    assert.deepEqual(groups, [...groups].sort((a, b) => GROUPS.indexOf(a) - GROUPS.indexOf(b)));
  }
  assert.equal(golden.steps.chromium.filter((st) => st.group === 'table').length, 2 * 65);
  assert.equal(golden.steps.chromium.filter((st) => st.group === 'extra').length, 2 * 7);
  assert.equal(golden.steps.webkit.filter((st) => st.group === 'table').length, 2 * 30);
  assert.equal(golden.steps.webkit.filter((st) => st.group === 'extra').length, 2 * 3);
  const g = { ...golden, steps: { ...golden.steps, chromium: golden.steps.chromium.map((st, i) => (i === 0 ? { ...st, group: undefined } : st)) } };
  assert.throws(() => evaluate(g, 'chromium', []), /group/);
});

test('verdict rows: the table set keeps the premise names, other sets carry the set name', () => {
  assert.equal(rowName('chromium', 'table', 'paint'), 'chromium.paint');
  assert.equal(rowName('chromium', 'extra', 'paint'), 'chromium.extra.paint');
  const r = { engine: 'webkit', groups: { table: { stages: { style: { verdict: 'holds', cells: { agree: 1, mismatch: 0, unstable: 0, missing: 0 } } } } } };
  assert.deepEqual(verdictLines(r), ['webkit.style: holds (agree 1, mismatch 0, unstable 0, missing 0)']);
});

test('present sums the counters of an observer', () => {
  const o = golden.observers.chromium.find((x) => x.stage === 'script');
  assert.equal(present(o, { 'trace.FunctionCall': 1 }), true);
  assert.equal(present(o, {}), false);
});
