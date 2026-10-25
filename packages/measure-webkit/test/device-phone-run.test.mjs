import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import * as P from '../src/device-phone-arms.mjs';
import { COUNT_TYPES } from '../src/reduce.mjs';
import { loadState, runBlock } from '../src/device-phone-run.mjs';

const STRIP = 'morph.countdown:strip';
const session = P.sessionOf([STRIP]);

const mkDist = (dir) => {
  const bySearch = { '': 'h0' };
  P.ARMS.filter((a) => a.flags.length > 0).forEach((a, i) => { bySearch[P.searchOf(a)] = `h${i + 1}`; });
  writeFileSync(join(dir, 'configs.json'), JSON.stringify({ bySearch, byHash: {} }));
};

const fakeResult = (hash) => ({
  counts: { fw: { configHash: hash }, reduced: [{ info: { vh: 844, maxY: 6000 }, zones: [{ y0: 0, counts: COUNT_TYPES.map(() => 1), paintArea: 5 }], census: [] }], readouts: [] },
  frames: { runs: [{ ts: [0, 16.7, 33.4, 50], ys: [0, 10, 20, 30], maxY: 6000 }], readouts: [] },
});

const world = ({ senses = [], visits = [], usb = [], listed = [true], proxies = () => [] } = {}) => {
  const w = { t: 1_800_000_000_000, sleeps: [], senseAt: [], visitAt: [], visitCalls: 0, senseCalls: 0, listedCalls: 0, usbCalls: 0 };
  const nominal = { state: 'Nominal', lock: 'unlocked', error: null, tempC: 33 };
  w.deps = {
    others: () => [], now: () => w.t, sleep: async (ms) => { w.sleeps.push(ms); w.t += ms; },
    proxies,
    sense: () => { w.senseAt.push(w.t / 1000); const s = senses[Math.min(w.senseCalls++, senses.length - 1)] ?? nominal; return s; },
    usbNow: () => usb[Math.min(w.usbCalls++, usb.length - 1)] ?? { verdict: 'ok', evidence: [] },
    usbListed: () => listed[Math.min(w.listedCalls++, listed.length - 1)],
    visit: async ({ row }) => {
      w.visitAt.push(w.t / 1000);
      const v = visits[w.visitCalls++];
      if (v instanceof Error) throw v;
      w.t += 400_000;
      return fakeResult(row.hash);
    },
  };
  return w;
};

const run = async (w, over = {}) => {
  const dir = mkdtempSync(join(tmpdir(), 'pr-'));
  const site = join(dir, 'dist'); await import('node:fs').then((fs) => fs.mkdirSync(site));
  mkDist(site);
  const raw = join(dir, 'raw');
  const out = { dir, raw, site };
  const log = [];
  const logFn = (s) => log.push(s);
  const orig = console.log; console.log = () => {};
  try { out.r = await runBlock({ site, dir: raw, log: logFn, session, deps: w.deps, blocked: join(dir, 'blocked.txt'), ...over }); } catch (e) { out.err = e; } finally { console.log = orig; }
  out.log = log;
  return out;
};
const cleanup = (o) => rmSync(o.dir, { recursive: true, force: true });
const faultErr = (m) => new Error(m);

test('--only plans the base around just the named arm: base, base, arm, base', () => {
  assert.deepEqual(session.map((a) => a.id), ['base', 'base', STRIP, 'base']);
  assert.throws(() => P.sessionOf(['nope']), /--only needs kept arm ids/);
  assert.throws(() => P.sessionOf([]), /--only needs kept arm ids/);
});

test('a block reads the thermal state at its start and after each visit, and records them', async () => {
  const w = world();
  const o = await run(w);
  try {
    assert.equal(o.err, undefined);
    assert.deepEqual(o.r.ran.map((x) => x.arm), ['base', 'base']);
    const st = loadState(o.raw);
    assert.deepEqual(st.session, ['base', 'base', STRIP, 'base']);
    assert.deepEqual(st.thermal.map((t) => t.phase), ['block-start', 'visit-end', 'visit-end']);
    assert.equal(st.firstTemp, 33);
    assert.ok(st.thermal.every((t) => t.verdict === 'go' && t.state === 'Nominal'));
  } finally { cleanup(o); }
});

test('the raw dir keeps its session: another plan is refused', async () => {
  const w = world();
  const o = await run(w);
  try {
    const again = await run(world(), { dir: o.raw, session: P.SESSION });
    assert.match(again.err.message, /holds the session plan/);
  } finally { cleanup(o); }
});

test('a Fair reading after a visit ends the block: no further pass starts; the next block waits a cool gap at nominal', async () => {
  const fair = { state: 'Fair', lock: 'unlocked', error: null, tempC: 34 };
  const nominal = { state: 'Nominal', lock: 'unlocked', error: null, tempC: 33 };
  const w = world({ senses: [nominal, nominal, fair] });
  const o = await run(w, { maxVisits: 4 });
  try {
    assert.equal(o.r.ran.length, 2);
    assert.equal(w.visitCalls, 2);
    assert.equal(o.r.paused, true);
    const st = loadState(o.raw);
    assert.equal(st.thermal.at(-1).state, 'Fair');
    assert.equal(st.thermal.at(-1).verdict, 'thermal');
    assert.ok(st.pausedAtS > 0);
    const w2 = world({ senses: [fair, fair, nominal] });
    w2.t = w.t;
    const o2 = await run(w2, { dir: o.raw, maxVisits: 4 });
    assert.equal(o2.err, undefined);
    const fairAt = w2.senseAt.filter((_, i) => i < 2).at(-1);
    assert.ok(w2.visitAt[0] - fairAt >= 300, `resumed ${w2.visitAt[0] - fairAt} s after the last Fair reading`);
    assert.deepEqual(o2.r.ran.map((x) => x.index), [2, 3]);
  } finally { cleanup(o); }
});

test('a phone that stays Serious is a named stop after the pause limit, with no visit and no attempt', async () => {
  const serious = { state: 'Serious', lock: 'unlocked', error: null, tempC: 40 };
  const w = world({ senses: [serious] });
  const o = await run(w);
  try {
    assert.match(o.r.stopped, /paused over 3600 s: the phone thermal state is not Nominal/);
    assert.equal(w.visitCalls, 0);
    assert.deepEqual(loadState(o.raw).visits, []);
    assert.match(readFileSync(join(o.dir, 'blocked.txt'), 'utf8'), /paused over/);
  } finally { cleanup(o); }
});

test('a battery 2 C over the first readout pauses even at Nominal', async () => {
  const w = world({ senses: [{ state: 'Nominal', lock: 'unlocked', error: null, tempC: 33 }, { state: 'Nominal', lock: 'unlocked', error: null, tempC: 35 }] });
  const o = await run(w);
  try {
    assert.equal(o.r.ran.length, 1);
    const st = loadState(o.raw);
    assert.deepEqual(st.thermal.map((t) => t.verdict), ['go', 'battery']);
    assert.equal(o.r.paused, true);
  } finally { cleanup(o); }
});

test('a locked phone is a named refusal, not a harness fault: no attempt is recorded', async () => {
  const w = world({ senses: [{ state: 'Nominal', lock: 'locked', error: null, tempC: 33 }] });
  const o = await run(w);
  try {
    assert.match(o.r.stopped, /the phone is locked/);
    assert.equal(w.visitCalls, 0);
    assert.deepEqual(loadState(o.raw).visits, []);
  } finally { cleanup(o); }
});

test('a USB reset is named usbReset with log evidence; the run waits for the phone to list and resumes the same visit', async () => {
  const ev = { verdict: 'reset', listed: false, onBus: true, evidence: [{ at: '2026-10-25 16:24:38', what: 'usbpowerd discovered' }] };
  const w = world({ visits: [faultErr('Inspector proxy closed (code 1006)')], usb: [ev], listed: [false, false, true] });
  const o = await run(w);
  try {
    assert.equal(o.err, undefined);
    assert.equal(o.r.stopped, null);
    assert.equal(w.visitCalls, 3);
    const st = loadState(o.raw);
    const v0 = st.visits.find((v) => v.index === 0);
    assert.equal(v0.status, 'done');
    assert.equal(v0.attempts, 2);
    assert.deepEqual(v0.faults, ['usbReset']);
    assert.ok(o.log.some((l) => /USB reset \(2026-10-25 16:24:38 usbpowerd discovered\)/.test(l)));
    assert.ok(o.log.some((l) => /lists again after 10 s; retrying visit 0/.test(l)));
  } finally { cleanup(o); }
});

test('the failed attempt keeps its fault name and log evidence in the state', async () => {
  const ev = { verdict: 'reset', listed: false, onBus: true, evidence: [{ at: '2026-10-25 16:24:38', what: 'usbpowerd terminated' }] };
  const w = world({ visits: [faultErr('Runtime.evaluate timed out 15 s')], usb: [ev], listed: [false] });
  const o = await run(w);
  try {
    assert.match(o.r.stopped, /failed \(usbReset\)/);
    assert.match(o.r.stopped, /did not list on USB within 180 s/);
    const v = loadState(o.raw).visits[0];
    assert.deepEqual(v.faults, ['usbReset']);
    assert.deepEqual(v.usb.evidence, ev.evidence);
    assert.equal(v.usb.verdict, 'reset');
  } finally { cleanup(o); }
});

test('an unnamed failure without a reset stays other and stops the block', async () => {
  const w = world({ visits: [faultErr('Runtime.evaluate timed out 15 s')], usb: [{ verdict: 'ok', evidence: [] }] });
  const o = await run(w);
  try {
    assert.match(o.r.stopped, /failed \(other\)/);
    assert.deepEqual(loadState(o.raw).visits[0].faults, ['other']);
    assert.equal(w.visitCalls, 1);
  } finally { cleanup(o); }
});

test('another proxy on the guarded ports refuses the run before any attempt', async () => {
  const w = world({ proxies: () => { throw new Error('another ios_webkit_debug_proxy is running (pid 1 holdsPorts on ports 9221)'); } });
  const o = await run(w);
  try {
    assert.match(o.err.message, /another ios_webkit_debug_proxy/);
    assert.equal(w.visitCalls, 0);
    assert.equal(w.senseCalls, 0);
    assert.deepEqual(loadState(o.raw).visits, []);
    assert.ok(existsSync(join(o.dir, 'blocked.txt')));
  } finally { cleanup(o); }
});
