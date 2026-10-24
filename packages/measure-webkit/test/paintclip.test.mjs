import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CLASSES, classify, seenArea, wasteArea, tally, per100, margin, coverage, rerasterArea, rectOf, classKey, dirty, DIRTY_CAP } from '../src/paintclip.mjs';

const G = readFileSync(new URL('../../contracts/golden/measure/paint-visible.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
const of = (fn) => G.filter((l) => l.fn === fn);
const factOf = (i) => ({ rect: rectOf(i.rect), visible: rectOf(i.visible), coverage: rectOf(i.coverage), hidden: i.hidden, covered: i.covered, clipped: i.clipped, pix: i.pix });

test('classify: class, seen and wasted pixels of every golden fact', () => {
  assert.ok(of('classify').length >= 10);
  for (const l of of('classify')) {
    const f = factOf(l.in);
    assert.equal(classify(f), l.out.class, JSON.stringify(l.in));
    assert.equal(seenArea(f), l.out.seen, JSON.stringify(l.in));
    assert.equal(wasteArea(f), l.out.waste, JSON.stringify(l.in));
  }
});

test('the golden exercises every class', () => {
  const seen = new Set(of('classify').map((l) => l.out.class));
  for (const c of CLASSES) assert.ok(seen.has(c), `no golden fact of class ${c}`);
});

test('tally: counts per class', () => {
  for (const l of of('tally')) {
    for (const c of CLASSES) assert.equal(tally(l.in.classes, c), l.out[c], c);
    assert.equal(CLASSES.reduce((s, c) => s + tally(l.in.classes, c), 0), l.in.classes.length);
  }
});

test('coverage: the tile coverage rect from the viewport, motion and margin', () => {
  assert.ok(of('coverage').length >= 4);
  for (const l of of('coverage')) assert.deepEqual(coverage(rectOf(l.in.visible), l.in.dir, margin(l.in.scale), l.in.contentH), rectOf(l.out), JSON.stringify(l.in));
});

test('rerasterArea: a non-tiled layer that changes size is painted whole', () => {
  for (const l of of('rerasterArea')) assert.equal(rerasterArea(l.in.tiled, l.in.old, l.in.new), l.out, JSON.stringify(l.in));
});

test('per100: rounded down, none for no frames', () => {
  for (const l of of('per100')) assert.equal(per100(l.in.total, l.in.frames), l.out);
});

test('dirty: the rects a layer keeps after its setNeedsDisplayInRect calls', () => {
  assert.ok(of('dirty').length >= 6);
  for (const l of of('dirty')) assert.deepEqual(dirty(l.in.calls.map(rectOf)), l.out.map(rectOf), JSON.stringify(l.in).slice(0, 120));
  assert.ok(of('dirty').some((l) => l.out.length === DIRTY_CAP), 'a golden case reaches the cap');
  assert.ok(of('dirty').every((l) => l.out.length <= DIRTY_CAP && l.out.length <= l.in.calls.length));
});

test('class keys carry no hyphen', () => {
  for (const c of CLASSES) assert.match(classKey(c), /^[a-z_]+$/);
});
