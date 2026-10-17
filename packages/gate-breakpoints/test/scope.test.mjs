// The Lean probe scope (src/scope.gen.json, lean/Fw/Gate/Scope.lean) against the package and the inventory: the file
// is Lean's bytes, its ids exist, its sweeps are the package's sweeps, and each part's conditions are the ones its CSS
// and media.ts use. These checks pin the inputs of Fw.Gate.scope_sound to the code the gate actually runs.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadAnchors, loadGen, loadScope, scopeFor, selectParts, sweepDefs } from '../src/spec.mjs';
import { PKG } from '../src/serve.mjs';
import { SCOPE_GEN, scopegen } from '../scripts/scopegen.mjs';

const ROOT = resolve(PKG, '../..');
const INVENTORY = resolve(ROOT, 'research/kickoff/11-breakpoints/breakpoints.json');
const ENV_KEYS = ['width', 'height', 'deviceWidth', 'deviceHeight', 'dpr', 'hover', 'pointer', 'reducedMotion', 'colorScheme'];

const { gen } = loadGen();
const scope = loadScope();
const pick = (e) => Object.fromEntries(ENV_KEYS.map((k) => [k, e[k]]));

/** MEDIA_IDS of a part's media.ts, or [] when the part has none. */
function mediaIds(pid) {
  const p = resolve(ROOT, 'apps/site/src/parts', pid, 'media.ts');
  if (!existsSync(p)) return [];
  const m = /MEDIA_IDS[^=]*=\s*\[([^\]]*)\]/.exec(readFileSync(p, 'utf8'));
  assert.ok(m, `${pid}: MEDIA_IDS not found`);
  return [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
}

test('scope.gen.json is the bytes Lean generates', { skip: !existsSync(resolve(ROOT, 'lean/.lake/build')) && 'lean not built' }, () => {
  const r = scopegen(['--check', SCOPE_GEN]);
  assert.equal(r.status, 0, r.stderr);
});

test('scope parts are the anchors parts, and every scoped id exists', () => {
  assert.equal(scope.schema, 'fw.gate-breakpoints.scope/1');
  assert.deepEqual(Object.keys(scope.parts).sort(), Object.keys(loadAnchors().parts).sort());
  assert.equal(scope.matrixProbes, gen.matrix.probes.length);
  const ids = gen.matrix.probes.map((p) => p.id);
  const sw = sweepDefs(gen).map((s) => s.id);
  for (const [pid, u] of Object.entries(scope.parts)) {
    assert.ok(u.probes.length > 0, pid);
    for (const id of u.probes) assert.ok(ids.includes(id), `${pid}: ${id}`);
    for (const id of u.sweeps) assert.ok(sw.includes(id), `${pid}: ${id}`);
    assert.deepEqual(u.probes, ids.filter((id) => u.probes.includes(id)), `${pid}: matrix order`);
  }
});

test('the Lean sweeps are the package sweeps, stop by stop', () => {
  const defs = sweepDefs(gen);
  assert.deepEqual(scope.sweeps.map((s) => s.id), defs.map((s) => s.id));
  for (let i = 0; i < defs.length; i++) {
    assert.deepEqual(scope.sweeps[i].stops.map(pick), defs[i].stops.map(pick), defs[i].id);
  }
});

test("a part's key starts with its conditions' CSS text as generated for the site", () => {
  const css = new Map(gen.conditions.map((c) => [c.id, c.css]));
  for (const [pid, u] of Object.entries(scope.parts)) {
    const ids = [...new Set([...u.conditions.orig, ...u.conditions.rewrite])];
    assert.deepEqual(u.key.slice(0, ids.length), ids.map((id) => css.get(id)), pid);
    assert.deepEqual(u.key.slice(ids.length), [...u.extra.map((x) => x.css), ...u.knees.map((k) => k.css)], pid);
  }
});

test("each part's conditions are its media.ts ids and its owners' inventory conditions", () => {
  const inv = JSON.parse(readFileSync(INVENTORY, 'utf8'));
  for (const [pid, u] of Object.entries(scope.parts)) {
    assert.deepEqual(u.conditions.rewrite, mediaIds(pid), `${pid}: rewrite = media.ts MEDIA_IDS`);
    const owners = new Set(u.owners);
    assert.ok(owners.has(pid), pid);
    const used = inv.conditions.filter((c) => (c.parts ?? []).some((x) => owners.has(x))).map((c) => c.id);
    assert.deepEqual(u.conditions.orig, used.filter((id) => id.startsWith('mq.')), `${pid}: orig = owners' mq.* conditions`);
    const accounted = [...u.conditions.orig, ...u.extra.map((x) => x.id), ...u.dismissed.map((x) => x.id)];
    assert.deepEqual([...accounted].sort(), [...used].sort(), `${pid}: every inventory condition kept, extra or dismissed`);
    for (const id of u.conditions.rewrite) assert.ok(u.conditions.orig.includes(id), `${pid}: ${id} in orig`);
    const conts = inv.continuous.filter((c) => (c.parts ?? []).some((x) => owners.has(x)));
    // a knee of a viewport-width value is the inventory's px; a knee of a container value (axis container-width) is stated
    // in the inventory in the container's px, and the part states it in viewport px where the layout puts the container there
    const wide = conts.filter((c) => c.axis === 'width').flatMap((c) => c.knees_px);
    const boxed = conts.filter((c) => c.axis === 'container-width' && (c.knees_px ?? []).length > 0).map((c) => c.expression);
    assert.deepEqual(u.knees.filter((k) => !boxed.includes(k.expression)).map((k) => k.px), wide, `${pid}: knees = owners' continuous knees`);
    for (const e of boxed) {
      const own = u.knees.filter((k) => k.expression === e);
      assert.ok(own.length > 0 && own.every((k) => Number.isInteger(k.px)), `${pid}: container knee "${e}" stated in viewport px`);
    }
    assert.ok(u.knees.every((k) => boxed.includes(k.expression) || wide.includes(k.px)), `${pid}: no knee without an inventory entry`);
  }
});

test('scopeFor: null unless narrowed; union of the covered parts in matrix and spec order', () => {
  const all = Object.keys(loadAnchors().parts);
  assert.equal(scopeFor(selectParts(all, null), gen, scope), null);
  assert.equal(scopeFor(selectParts(all, all), gen, scope), null);
  const miss = { ...scope, parts: { ...scope.parts } };
  delete miss.parts['hero.exit'];
  assert.equal(scopeFor(selectParts(all, ['hero.exit']), gen, miss), null);
  const one = scopeFor(selectParts(all, ['hero.exit']), gen, scope);
  assert.deepEqual(one, { probes: scope.parts['hero.exit'].probes, sweeps: scope.parts['hero.exit'].sweeps });
  const allButOne = all.filter((id) => id !== 'nav.hitTest');
  const u = scopeFor(selectParts(all, allButOne), gen, scope);
  const want = new Set(allButOne.flatMap((id) => scope.parts[id].probes));
  assert.deepEqual(u.probes, gen.matrix.probes.map((p) => p.id).filter((id) => want.has(id)));
  // the Lean union over every part equals the package union over every part
  const full = new Set(all.flatMap((id) => scope.parts[id].probes));
  assert.deepEqual(scope.union.probes, gen.matrix.probes.map((p) => p.id).filter((id) => full.has(id)));
  const fullSw = new Set(all.flatMap((id) => scope.parts[id].sweeps));
  assert.deepEqual(scope.union.sweeps, sweepDefs(gen).map((s) => s.id).filter((id) => fullSw.has(id)));
});
