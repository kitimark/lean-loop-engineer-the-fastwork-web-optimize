// The page-recorder request of the trajectory probe (src/trajectory/debug.mjs): off unless asked, one named recorder, the search for
// the config lookup never carries the debug param. The request is the env var FW_DEBUG, set by the workflow from the push commit line.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { DEBUGS, debugFor, fieldOf, readDebug, withDebug } from '../src/trajectory/debug.mjs';
import { mergeRaws } from '../src/trajectory/plan.mjs';
import { installKit } from '../src/trajectory/kit.mjs';

test('debugFor: no recorder unless FW_DEBUG names one', () => {
  assert.equal(debugFor({}), '');
  assert.equal(debugFor({ FW_DEBUG: '' }), '');
  assert.equal(debugFor({ FW_SEARCH: '?fw=morph.tween:waapi' }), '');
  assert.equal(debugFor({ FW_DEBUG: 'nav-transition' }), 'nav-transition');
  assert.throws(() => debugFor({ FW_DEBUG: 'nope' }), /unknown recorder "nope"/);
  assert.throws(() => debugFor({ FW_DEBUG: 'Nav-Transition' }), /unknown recorder/);
});

test('no file of the package requests a recorder: debug.requests.json is gone and debug.mjs reads no file', () => {
  const dir = fileURLToPath(new URL('../src/trajectory/', import.meta.url));
  assert.equal(existsSync(dir + 'debug.requests.json'), false);
  const src = readFileSync(dir + 'debug.mjs', 'utf8');
  assert.doesNotMatch(src, /readFileSync|requests\.json|node:fs/);
});

test('withDebug: appends fw-debug after the search; nothing for no recorder', () => {
  assert.equal(withDebug('?fw=morph.tween:waapi', ''), '?fw=morph.tween:waapi');
  assert.equal(withDebug('', ''), '');
  assert.equal(withDebug('?fw=morph.tween:waapi', 'nav-transition'), '?fw=morph.tween:waapi&fw-debug=nav-transition');
  assert.equal(withDebug('', 'nav-transition'), '?fw-debug=nav-transition');
});

test('readDebug: the field of the recorder, or null when the page did not install it', () => {
  assert.equal(fieldOf('nav-transition'), 'navTransition');
  assert.equal(fieldOf('root-events'), 'rootEvents');
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

/** The kit as the probe runs it (its source text, in a bare window), with the globals a sample touches stubbed. */
async function sampleWith(win) {
  const g = globalThis;
  const had = ['window', 'requestAnimationFrame'].map((k) => [k, Object.getOwnPropertyDescriptor(g, k)]);
  g.window = win;
  const queue = [];
  g.requestAnimationFrame = (cb) => { queue.push(cb); return queue.length; };
  try {
    (0, eval)(`(${installKit.toString()})()`);
    const arg = { navSel: '', nodes: [], pageProps: [], arm: 'rewrite', lean: false, stride: 1, phase: 'open' };
    win.__traj.startSampler(arg);
    // Five frames, run by hand: the sample count does not depend on the wall clock. Each frame ends in the kit's sleep(0);
    // two timer turns let it resolve (same-delay timers run in order), so the loop records and asks for the next frame.
    const turn = () => new Promise((r) => setTimeout(r, 0));
    for (let f = 1; f <= 5; f++) {
      for (const cb of queue.splice(0)) cb(f * 16);
      await turn();
      await turn();
    }
    return win.__traj.stopSampler();
  } finally {
    for (const [k, d] of had) { if (d) Object.defineProperty(g, k, d); else delete g[k]; }
  }
}

test('the kit calls the recorder once before each sample when it exists, and does nothing when it does not', async () => {
  const calls = [];
  const rows = await sampleWith({ scrollY: 0, __fwDebug: { navTransitionRead: () => calls.push(1) } });
  assert.ok(rows.length >= 2, `samples: ${rows.length}`);
  assert.equal(calls.length, rows.length);
  assert.ok((await sampleWith({ scrollY: 0 })).length >= 2);
  assert.ok((await sampleWith({ scrollY: 0, __fwDebug: {} })).length >= 2);
});
