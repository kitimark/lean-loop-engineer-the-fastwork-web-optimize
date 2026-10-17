import test from 'node:test';
import assert from 'node:assert/strict';
import { ANCHORS_PATH, expectFor, loadAnchors, loadGen, partJson, probeEnv, selectParts, sweepDefs } from '../src/spec.mjs';

test('the matrix is the 124 probes of the generated file, with an expectation for every condition', () => {
  const { gen } = loadGen();
  assert.equal(gen.matrix.probes.length, 124);
  assert.equal(gen.matrix.loadsPerEngine, 124);
  for (const p of gen.matrix.probes) {
    assert.equal(Object.keys(p.expect).length, gen.conditions.length, p.id);
    assert.ok(p.hover && p.pointer && p.dpr && p.width, p.id);
  }
});

test('anchors.json lists the same anchors as each part.json', () => {
  const anchors = loadAnchors();
  for (const [pid, spec] of Object.entries(anchors.parts)) {
    const part = partJson(pid);
    assert.ok(part, `${pid}: part.json exists (${ANCHORS_PATH})`);
    assert.deepEqual(spec.anchors, part.anchors, pid);
    if (spec.roles.length === 0) assert.ok(spec.notComparable, `${pid}: explains why it is not comparable`);
  }
});

test('every role names a box reference that exists, dims need a reference unless only w/h', () => {
  const anchors = loadAnchors();
  for (const [pid, spec] of Object.entries(anchors.parts)) {
    const names = spec.roles.map((r) => r.role);
    assert.equal(new Set(names).size, names.length, `${pid}: role names are unique`);
    for (const r of spec.roles) {
      assert.ok(r.orig && r.rewrite && r.why, `${pid}.${r.role}`);
      if (r.boxRel) assert.ok(names.includes(r.boxRel.role), `${pid}.${r.role}: reference exists`);
      else assert.ok(r.dims.every((d) => d === 'w' || d === 'h'), `${pid}.${r.role}: absolute position is not comparable across hosts`);
      for (const s of r.skipSets) assert.ok(anchors.style.skipSets[s], `${pid}.${r.role}: skip set ${s}`);
    }
  }
});

test('sweeps: stops stay on the matrix edge widths and the Lean vector is found where the matrix has one', () => {
  const { gen } = loadGen();
  const sweeps = sweepDefs(gen);
  assert.deepEqual(sweeps.map((s) => s.id), ['desktop-1512-320-1512', 'phone-rotation', 'touch-1024-1201', 'pain-1440-600-1440']);
  const desk = sweeps[0].stops.map((s) => s.width);
  assert.equal(desk[0], 1512);
  assert.equal(desk[desk.length - 1], 1512);
  assert.ok(desk.includes(320) && !desk.includes(319));
  assert.ok(expectFor(gen, sweeps[0].stops[0]), 'desk 1512 has a vector');
  assert.ok(expectFor(gen, sweeps[1].stops[1]), 'phone landscape has a vector');
  assert.equal(expectFor(gen, sweeps[2].stops[0]), undefined, 'touch 1024 has none');
  assert.equal(probeEnv(gen.matrix.probes[0]).width, 319);
});

test('selectParts: default is all, a subset keeps anchors order and names the skipped parts, typos throw', () => {
  const ids = Object.keys(loadAnchors().parts);
  assert.deepEqual(selectParts(ids, null), { covered: ids, skipped: [], narrowed: false });
  assert.deepEqual(selectParts(ids, [...ids].reverse()), { covered: ids, skipped: [], narrowed: false });
  const one = selectParts(ids, ['hero.exit']);
  assert.deepEqual(one, { covered: ['hero.exit'], skipped: ids.filter((i) => i !== 'hero.exit'), narrowed: true });
  assert.throws(() => selectParts(ids, ['hero.exti']), /unknown part hero.exti/);
  assert.throws(() => selectParts(ids, []), /empty list/);
});
