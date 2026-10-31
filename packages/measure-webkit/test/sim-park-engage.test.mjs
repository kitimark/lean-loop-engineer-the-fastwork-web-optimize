import test from 'node:test';
import assert from 'node:assert/strict';
import { ARMS, BUILD_SEARCHES, PARK_ARMS, endFloorJs } from '../src/sim-end-floor.mjs';
import { firstScrollJs, parkLines, parkState, took, viewDriven } from '../src/sim-park-engage.mjs';
import { armTrees } from '../src/sim-end-floor-run.mjs';

const probe = (o = {}) => ({ variant: 'threaded-park', live: true, styled: true, parked: false, y: 5000, ...o });

test('parkState names where the park stood', () => {
  assert.equal(parkState(null), 'noHero');
  assert.equal(parkState(probe({ live: false })), 'notLive');
  assert.equal(parkState(probe({ styled: false })), 'noStyle');
  assert.equal(parkState(probe()), 'live');
  assert.equal(parkState(probe({ parked: true })), 'parked');
});

test('took needs a parked track and no view-driven animation', () => {
  assert.equal(viewDriven({ by: { 'view:finished': 13, 'document:running': 4 } }), 13);
  assert.equal(took({ by: { 'view:finished': 13 }, park: probe({ parked: true }) }), false);
  assert.equal(took({ by: { 'document:running': 4 }, park: probe() }), false);
  assert.equal(took({ by: { 'document:running': 4 }, park: probe({ parked: true }) }), true);
});

test('the park arms stay out of the default arm set and its build searches', () => {
  assert.ok(PARK_ARMS.every((a) => a.set === 'park'));
  assert.ok(PARK_ARMS.every((a) => !ARMS.some((b) => b.id === a.id)));
  assert.ok(PARK_ARMS.every((a) => !BUILD_SEARCHES.includes(a.search)));
  assert.deepEqual(PARK_ARMS.map((a) => a.act ?? null), [null, 'walk']);
  assert.deepEqual(Object.keys(armTrees('/s', PARK_ARMS)), ['park', 'parkWalk']);
});

test('the page script jumps for the default act and walks in steps for walk; both read the park probe', () => {
  assert.match(firstScrollJs(null), /behavior: 'instant'/);
  assert.doesNotMatch(firstScrollJs(null), /for \(/);
  assert.match(firstScrollJs('walk'), /y \+ 100/);
  const jump = endFloorJs({});
  const walk = endFloorJs({ act: 'walk' });
  for (const js of [jump, walk]) {
    assert.match(js, /const parkProbe = /);
    assert.match(js, /park: parkProbe\(\)/);
    assert.doesNotThrow(() => new Function(`return ${js}`));
  }
  assert.doesNotMatch(jump, /y \+ 100/);
  assert.match(walk, /y \+ 100/);
});

test('parkLines reports each round and arm and the overall count', () => {
  const ok = { anims: { by: { 'document:running': 4 }, park: probe({ parked: true }) } };
  const bad = { anims: { by: { 'view:finished': 13 }, park: probe() } };
  const raw = { meta: { runtime: 'iOS' }, rounds: [{ round: 1, arms: { park: ok, parkWalk: bad } }, { round: 2, arms: { park: ok } }] };
  const lines = parkLines(raw);
  assert.match(lines[1], /round 1 park: park parked .*view-driven 0; took true/);
  assert.match(lines[2], /round 1 parkWalk: park live .*view-driven 13; took false/);
  assert.match(lines[3], /round 2 park: park parked/);
  assert.match(lines[4], /round 2 parkWalk: unread/);
  assert.equal(lines.at(-2), 'overall park: took in 2 of 2 rounds');
  assert.equal(lines.at(-1), 'overall parkWalk: took in 0 of 1 rounds');
});
