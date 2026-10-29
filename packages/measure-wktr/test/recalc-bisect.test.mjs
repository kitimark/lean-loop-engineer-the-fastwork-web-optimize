import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BS_ARMS, BS_C, band, bisectTally, carrier, cls, hi, holder, jobOfGolden, levelName, lo, overall, overall2, ready, reportToJob, res, resName, rpf100, valid } from '../src/recalc-bisect.mjs';
import { accelHarnessSource } from '../src/accel-page.mjs';
import { MODES, headerOf, isBisect, THREADED_OFF } from '../src/accel-cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/recalc-bisect.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const jobs = lines.filter((l) => l.kind === 'job');
const byName = new Map(jobs.map((l) => [l.name, l]));
const carries = lines.filter((l) => l.kind === 'carry');
const byName2 = new Map(carries.map((l) => [l.name, l]));

test('constants equal the Lean consts line', () => {
  const k = lines.find((l) => l.kind === 'consts');
  for (const key of Object.keys(BS_C)) assert.equal(BS_C[key], k[key], key);
});

test('job lines: rates, bands, classes, reason and path replay the Lean golden', () => {
  assert.ok(jobs.length >= 25);
  for (const l of jobs) {
    const j = jobOfGolden(l.job);
    assert.equal(hi(j), l.hi, `${l.name} hi`);
    assert.equal(lo(j), l.lo, `${l.name} lo`);
    assert.equal(band(j), l.band, `${l.name} band`);
    assert.deepEqual(j.parts.map((p) => cls(j, p.arm)), l.classes, `${l.name} classes`);
    const r = res(j);
    assert.equal(resName(r), l.why, `${l.name} why`);
    assert.equal(valid(r), l.valid, `${l.name} valid`);
    assert.deepEqual(r.t === 'found' ? r.path : null, l.path, `${l.name} path`);
  }
});

test('overall lines replay the Lean golden', () => {
  const combos = lines.filter((l) => l.kind === 'overall');
  assert.ok(combos.length >= 10);
  for (const l of combos) {
    const v = overall(l.jobs.map((n) => res(jobOfGolden(byName.get(n).job))));
    assert.equal(v.name, l.verdict, l.name);
    assert.equal(v.next, l.next, `${l.name} next`);
  }
});

test('carry lines: stage 2 classes, carrier and holder replay the Lean golden', () => {
  assert.ok(carries.length >= 10);
  for (const l of carries) {
    const j = jobOfGolden(l.job);
    assert.equal(ready(j), l.ready, `${l.name} ready`);
    assert.equal(hi(j), l.hi, `${l.name} hi`);
    assert.equal(lo(j), l.lo, `${l.name} lo`);
    assert.deepEqual(j.parts.map((p) => cls(j, p.arm)), l.classes, `${l.name} classes`);
    assert.equal(levelName(carrier(j)), l.carrier, `${l.name} carrier`);
    assert.equal(levelName(holder(j)), l.holder, `${l.name} holder`);
  }
});

test('overall2 lines replay the Lean golden', () => {
  const combos = lines.filter((l) => l.kind === 'overall2');
  assert.ok(combos.length >= 10);
  for (const l of combos) {
    const v = overall2(l.jobs.map((n) => { const j = jobOfGolden(byName2.get(n).job); return l.which === 'carrier' ? carrier(j) : holder(j); }));
    assert.equal(v.name, l.verdict, l.name);
    assert.equal(v.next, l.next, `${l.name} next`);
  }
});

test('the probe pins the thresholds the Lean decision uses', () => {
  const src = accelHarnessSource({ mode: 'timed', arms: BS_ARMS });
  assert.ok(src.includes('"minFrames":40') && src.includes('"bandDen":4'));
  for (const a of BS_ARMS) assert.ok(src.includes(a), a);
});

test('the mode runs with the threaded animations pref off', () => {
  assert.ok(MODES['bisect-thr-off']);
  assert.ok(isBisect('bisect-thr-off'));
  assert.ok(headerOf('bisect-thr-off', 'base').endsWith(THREADED_OFF));
  assert.equal(BS_ARMS.slice(0, 2).join(), 'bs-facts,bs-full-a');
});

const row = (arm, bs, extra = {}) => ({ arm, engaged: true, bs, ...extra });
const rd = (frames, recalcs) => ({ read: { frames, recalcs } });

test('reportToJob and the tally: a unit never read counts as unread, never as kept', () => {
  const report = {
    rows: [
      row('bs-facts', { parts: [{ path: 'nav', parent: '', kids: 0, feat: {} }, { path: 'page', parent: '', kids: 0, feat: { sticky: 2 } }, { path: 'late', parent: '', kids: 0, feat: {} }], body: {}, rules: {}, cn: {} }),
      row('bs-full-a', rd(100, 100)), row('bs-hidden-a', rd(100, 3)),
      row('bs-l1', { reads: [{ path: 'nav', parent: '', kids: 0, frames: 100, recalcs: 99 }, { path: 'page', parent: '', kids: 0, frames: 100, recalcs: 4 }] }),
      row('bs-full-b', rd(100, 98)), row('bs-hidden-b', rd(100, 6)),
      row('bs-obs', rd(100, 100), { rs: { kt: ['ev:scroll'], frames: [{ r: 1, k: [0] }, { r: 1, k: [] }] } }),
    ],
  };
  const j = reportToJob(report);
  assert.equal(j.parts.length, 3);
  assert.deepEqual(j.parts[2].arm, { frames: 0, recalcs: 0 });
  assert.equal(cls(j, j.parts[2].arm), 'unread');
  assert.equal(resName(res(j)), 'incomplete');
  const t = bisectTally(report).join('\n');
  assert.match(t, /why incomplete/);
  assert.match(t, /keys \[\["ev:scroll",1\]\]/);
  assert.equal(rpf100({ frames: 0, recalcs: 5 }), 0);
});
