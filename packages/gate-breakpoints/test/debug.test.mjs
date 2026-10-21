// The page-recorder request of the trajectory probe (src/trajectory/debug.mjs): off unless asked, one named recorder, the search for
// the config lookup never carries the debug param.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { DEBUGS, debugFor, fieldOf, readDebug, withDebug } from '../src/trajectory/debug.mjs';
import { mergeRaws } from '../src/trajectory/plan.mjs';

const requests = [{ search: '?fw=morph.tween:waapi', debug: 'nav-transition' }];

test('debugFor: no recorder by default, whatever the search', () => {
  for (const search of ['', '?fw=morph.tween:waapi', '?preset=v2-proved', '?fw=hero.exit:scoped']) assert.equal(debugFor(search, {}, []), '');
  assert.equal(debugFor('?fw=hero.exit:scoped', {}, requests), '');
  assert.equal(debugFor('', { FW_DEBUG: '' }, requests), '');
});

test('debugFor: a request row matches its search exactly; FW_DEBUG overrides for a local run', () => {
  assert.equal(debugFor('?fw=morph.tween:waapi', {}, requests), 'nav-transition');
  assert.equal(debugFor('?fw=morph.tween:waapi-scoped', {}, requests), '');
  assert.equal(debugFor('?fw=morph.tween:waapi,nav:earn-no-transition', {}, requests), '');
  assert.equal(debugFor('', { FW_DEBUG: 'nav-transition' }, []), 'nav-transition');
  assert.throws(() => debugFor('', { FW_DEBUG: 'nope' }, []), /unknown recorder "nope"/);
  assert.throws(() => debugFor('?fw=a:b', {}, [{ search: '?fw=a:b', debug: 'nope' }]), /unknown recorder/);
});

test('withDebug: appends fw-debug after the search; nothing for no recorder', () => {
  assert.equal(withDebug('?fw=morph.tween:waapi', ''), '?fw=morph.tween:waapi');
  assert.equal(withDebug('', ''), '');
  assert.equal(withDebug('?fw=morph.tween:waapi', 'nav-transition'), '?fw=morph.tween:waapi&fw-debug=nav-transition');
  assert.equal(withDebug('', 'nav-transition'), '?fw-debug=nav-transition');
});

test('the committed requests name known recorders and plain fw searches', () => {
  const rows = JSON.parse(readFileSync(fileURLToPath(new URL('../src/trajectory/debug.requests.json', import.meta.url)), 'utf8'));
  for (const r of rows) {
    assert.ok(DEBUGS.some((d) => d.name === r.debug), `known recorder: ${r.debug}`);
    assert.match(r.search, /^\?fw=[A-Za-z0-9.:,\-_@]+$/);
  }
});

test('readDebug: the field of the recorder, or null when the page did not install it', () => {
  assert.equal(fieldOf('nav-transition'), 'navTransition');
  const had = globalThis.window;
  try {
    globalThis.window = {};
    assert.equal(readDebug('navTransition'), null);
    globalThis.window = { __fwDebug: {} };
    assert.equal(readDebug('navTransition'), null);
    const log = { rows: [{ k: 'cls' }], dropped: 0 };
    globalThis.window = { __fwDebug: { navTransition: log } };
    assert.equal(readDebug('navTransition'), log);
  } finally {
    if (had === undefined) delete globalThis.window;
    else globalThis.window = had;
  }
});

test('mergeRaws keeps the recorder rows of a leg and refuses legs that disagree on the recorder', () => {
  const leg = (width, extra = {}) => ({
    engine: 'playwright-webkit',
    search: '?fw=morph.tween:waapi',
    hash: 'h',
    baseHash: 'b',
    reads: 'full',
    reps: 5,
    version: 'v',
    paths: ['morph'],
    debug: 'nav-transition',
    refused: false,
    runs: [{ width, role: 'cand', morph: { debugReps: [{ rep: 0, name: 'nav-transition', rows: { rows: [], dropped: 0 } }] } }],
    ...extra,
  });
  const m = mergeRaws([leg(1280), leg(390)]);
  assert.equal(m.debug, 'nav-transition');
  assert.deepEqual(m.runs.map((r) => r.width), [390, 1280]);
  assert.equal(m.runs[0].morph.debugReps[0].name, 'nav-transition');
  assert.throws(() => mergeRaws([leg(390), leg(640, { debug: '' })]), /disagree on debug/);
});
