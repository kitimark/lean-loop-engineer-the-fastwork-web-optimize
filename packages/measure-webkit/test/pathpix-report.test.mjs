import test from 'node:test';
import assert from 'node:assert/strict';
import { slimCell, slimLane, heroCopyTable, heroCopySummary, heroCopyWhere, heroCopyShared, pinTable, lSource, engineTable } from '../src/pathpix-exit-report.mjs';

const raw = (changed, maxDelta) => ({ changed, maxDelta });
const claim = { compA: true, compB: true };
const full = (key, i, kind, over) => ({
  key, i, y: 0, kind, grade: 'Q', why: null, ifAccepted: 'Q', absGrade: 'Q', live: true, accentPinned: true, invalidWhy: null,
  cell: { inside: raw(0, 0), out: raw(0, 0), p1: true, claim }, floor: null, where: null, ...over,
});
const OFFS = [0, 1, 300];
const lane = (label, cells, skipped = [], extra = {}) => slimLane(label, `art-${label}`, {
  run: '77', engine: 'webkit', lane: 'ios-simulator', flag: 'f', compositing: 'x', vw: 390, dpr: 3, exit: { T: 0 }, offsets: OFFS, cut: [], armsRun: ['A', 'A2', 'P'], driverMoved: true,
  liveness: [], skipped, frames: [], cells, ...extra,
}, {});

const jobs = () => [
  lane('webkit-1', [
    full('hero_copy', 0, 'A/A', { cell: { inside: raw(48, 1), out: raw(0, 0), p1: true, claim }, where: { bbox: [10, 20, 30, 40], parts: ['button.cta', 'span.face', 'span.face', 'p.note'] } }),
    full('hero_copy', 0, 'P', { grade: 'L', why: 'inside', ifAccepted: 'L', cell: { inside: raw(60, 2), out: raw(0, 0), p1: true, claim } }),
    full('hero_copy', 1, 'A/A', {}),
    full('hero_copy', 1, 'P', { grade: 'L', why: 'text', ifAccepted: 'Q' }),
    full('hero_copy', 2, 'P', { grade: 'invalid', invalidWhy: 'misplaced', ifAccepted: 'invalid', accentPinned: false }),
  ], [{ key: 'hero.cue_cue', i: 2, kind: 'all', why: 'off screen at this offset' }, { key: 'hero_copy', i: 2, kind: 'A/A', why: 'occluded by opaque foreign content in both arms' }], { clock: { values: [100], constant: true } }),
  lane('webkit-2', [
    full('hero_copy', 0, 'A/A', {}),
    full('hero_copy', 0, 'P', { grade: 'L', why: 'outside', ifAccepted: 'L', cell: { inside: raw(0, 0), out: raw(3, 9), p1: true, claim } }),
  ], [{ kind: 'all', i: 1, why: 'arm A not captured at this offset' }], { clock: { values: [100, 200], constant: false } }),
];

test('the L source: strips not accepted only when the grade would be Q with them, else outside the mask or inside above the floor', () => {
  assert.equal(lSource({ grade: 'Q', ifAccepted: 'Q', out: raw(0, 0) }), null);
  assert.equal(lSource({ grade: 'invalid', ifAccepted: 'invalid', out: raw(0, 0) }), null);
  assert.equal(lSource({ grade: 'L', ifAccepted: 'Q', out: raw(0, 0) }), 'strips not accepted');
  assert.equal(lSource({ grade: 'L', ifAccepted: 'L', out: raw(5, 1) }), 'outside the mask');
  assert.equal(lSource({ grade: 'L', ifAccepted: 'L', out: raw(0, 0) }), 'inside, above the floor');
  assert.equal(lSource({ grade: 'L', why: 'text', ifAccepted: 'L', out: raw(0, 0) }), 'inside, above the floor');
  assert.equal(lSource({ grade: 'L', why: 'inside', ifAccepted: 'Q', out: raw(0, 0) }), 'strips not accepted');
});

test('hero_copy table: one row per offset, every job side by side, skips named, nothing typed by hand', () => {
  const lanes = jobs();
  const rows = heroCopyTable('webkit', lanes).split('\n');
  assert.match(rows[0], /webkit: hero_copy per job and offset/);
  const body = rows.slice(4);
  assert.equal(body.length, OFFS.length);
  assert.ok(body[0].startsWith('| 0 | 0 |'));
  assert.ok(body[0].includes('48-1/0-0'), 'A/A floor inside/outside of job 1');
  assert.ok(body[0].includes('L (inside, above the floor) [L]'));
  assert.ok(body[1].includes('L (strips not accepted) [Q]'));
  assert.ok(body[2].includes('skipped: occluded by opaque foreign content in both arms'));
  assert.ok(body[2].includes('invalid (misplaced)'));
  assert.ok(body[0].includes('L (outside the mask) [L]'), 'job 2');
  assert.ok(body[1].includes('skipped: arm A not captured at this offset'), 'a missing arm shows as a skip with its reason');
  assert.equal(body[0].split('|').length, rows[2].split('|').length, 'the header and the rows have the same columns');
});

test('hero_copy summary counts grades and L sources from the cells', () => {
  const md = heroCopySummary('webkit', jobs()).split('\n');
  const cells = md[4].split('|').map((x) => x.trim()).filter(Boolean);
  assert.deepEqual(cells.slice(0, 9), ['4', '0', '0', '0', '3', '1', '1', '1', '1']);
  assert.equal(cells[9], '3', 'A/A cells');
  assert.equal(cells[10], '1', 'A/A with a change inside');
  assert.ok(cells[12].includes('occluded by opaque foreign content in both arms x1'));
});

test('the changed-box list names the parts, only for cells with a change inside', () => {
  const md = heroCopyWhere(jobs()).split('\n');
  assert.equal(md.length, 3);
  assert.ok(md[2].includes('webkit-1 | 0 | A/A | 48-1 | 10,20,30,40 | button.cta, span.face x2, p.note'));
});

test('the shared-pixel list prints the reason, the pixels hero_copy left to other layers and where the outside changes are', () => {
  const l = lane('webkit-1', [
    full('hero_copy', 0, 'A/A', { shared: raw(48, 1), sharedWith: 3 }),
    full('hero_copy', 1, 'A/A', { shared: raw(0, 0), sharedWith: 3 }),
    full('hero_copy', 2, 'A/A', { shared: raw(0, 0), sharedWith: 3, cell: { inside: raw(0, 0), out: raw(2, 1), p1: true, claim }, where: { bbox: null, parts: [], outBbox: [5, 6, 9, 10] } }),
    full('hero_copy', 0, 'P', {}),
  ]);
  const md = heroCopyShared([l]).split('\n');
  assert.ok(md[0].startsWith('Reason: pixels inside another graded layer'));
  assert.equal(md.length, 6, 'reason, blank, header, rule and two rows; the offset with nothing is left out');
  assert.ok(md[4].includes('| webkit-1 | 0 | A/A | 48-1 | 3 | - |'));
  assert.ok(md[5].includes('| webkit-1 | 2 | A/A | 0-0 | 3 | 2-1 at 5,6,9,10 |'));
});

test('the pin table reads the page clock, unpinned, misplaced and occluded counts', () => {
  const md = pinTable(jobs()).split('\n');
  assert.ok(md[2].includes('constant (100)') && md[2].endsWith('| 5 | 0 | 1 | 1 |'));
  assert.ok(md[3].includes('moves (100,200)'));
  assert.ok(pinTable([lane('x', [])]).includes('not recorded'));
});

test('slim cells keep where, and the engine table still renders', () => {
  const c = full('hero_copy', 0, 'A/A', { where: { bbox: [1, 2, 3, 4], parts: [] } });
  assert.deepEqual(slimCell(c).where, { bbox: [1, 2, 3, 4], parts: [] });
  const l = jobs();
  assert.equal(l[0].clock.constant, true);
  assert.match(engineTable('webkit', l), /hero_copy/);
});
