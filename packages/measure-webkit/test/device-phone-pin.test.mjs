import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import * as P from '../src/device-phone-arms.mjs';
import { COUNT_TYPES } from '../src/reduce.mjs';
import { loadState, runBlock, reduceDir } from '../src/device-phone-run.mjs';
import { pinnedSession } from '../src/device-phone-pin.mjs';
import { PIN } from '../src/device-thermal-pin.mjs';
import { fakeWorld, mkOwner } from './pin-world.mjs';

const STRIP = 'morph.countdown:strip';
const session = P.sessionOf([STRIP]);

const fakeResult = (hash) => ({
  counts: { fw: { configHash: hash }, reduced: [{ info: { vh: 844, maxY: 6000 }, zones: [{ y0: 0, counts: COUNT_TYPES.map(() => 1), paintArea: 5 }], census: [] }], readouts: [] },
  frames: { runs: [{ ts: [0, 16.7, 33.4, 50], ys: [0, 10, 20, 30], maxY: 6000 }], readouts: [] },
});
const S = (state, extra = {}) => ({ state, lock: 'unlocked', error: null, tempC: 33, ...extra });

const phone = (w, { senses, held = () => true, onVisit = () => {} }) => {
  const c = { senseCalls: 0, lanes: [], visits: 0, order: [] };
  c.deps = {
    others: () => [], now: () => w.t, sleep: async (ms) => { w.t += ms; c.order.push(`sleep ${ms}`); },
    proxies: () => [],
    sense: () => { c.order.push('sense'); return senses[Math.min(c.senseCalls++, senses.length - 1)]; },
    usbNow: () => ({ verdict: 'ok', evidence: [] }), usbListed: () => true,
    visit: async ({ row, gate }) => {
      c.visits++;
      c.order.push('frames');
      c.lanes.push('frames');
      onVisit(c.visits);
      if (gate) await gate();
      c.order.push('counts');
      c.lanes.push('counts');
      w.t += 400_000;
      return fakeResult(row.hash);
    },
  };
  c.pin = { target: 'Serious', held, onHeld: () => {} };
  return c;
};

const setup = () => {
  const dir = mkdtempSync(join(tmpdir(), 'pp-'));
  const site = join(dir, 'dist');
  mkdirSync(site);
  const bySearch = { '': 'h0' };
  P.ARMS.filter((a) => a.flags.length > 0).forEach((a, i) => { bySearch[P.searchOf(a)] = `h${i + 1}`; });
  writeFileSync(join(site, 'configs.json'), JSON.stringify({ bySearch, byHash: {} }));
  return { dir, site, raw: join(dir, 'raw') };
};
const quietRun = async (fn) => {
  const orig = console.log; console.log = () => {};
  try { return await fn(); } finally { console.log = orig; }
};
const block = (e, c, over = {}) => quietRun(() => runBlock({ site: e.site, dir: e.raw, log: () => {}, session, deps: c.deps, pin: c.pin, maxVisits: 2, ...over }));

test('pinned block: a go reading before every lane, the lanes run in order, no cool wait, every reading carries its reason', async () => {
  const e = setup();
  try {
    const w = fakeWorld();
    const c = phone(w, { senses: [S('Serious')] });
    const r = await block(e, c);
    assert.equal(r.stopped, null);
    assert.deepEqual(r.ran.map((x) => x.arm), ['base', 'base']);
    const st = loadState(e.raw);
    assert.deepEqual(st.thermal.map((t) => t.phase), ['block-start', 'between-lanes', 'visit-end', 'between-lanes', 'visit-end']);
    assert.ok(st.thermal.every((t) => t.verdict === 'go' && t.why === 'onTarget' && t.held === true));
    assert.deepEqual(c.lanes, ['frames', 'counts', 'frames', 'counts']);
    assert.deepEqual(st.visits.map((v) => v.status), ['done', 'done']);
    assert.ok(c.order.indexOf('counts') > c.order.indexOf('sense'), 'a reading comes before the counts lane');
    const gate = c.order.slice(c.order.indexOf('frames'), c.order.indexOf('counts'));
    assert.ok(gate.includes('sense'), 'a reading sits between the frames lane and the counts lane');
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('pinned block: a state still rising at the start is waited for, not run on', async () => {
  const e = setup();
  try {
    const c = phone(fakeWorld(), { senses: [S('Nominal'), S('Fair'), S('Serious')] });
    const r = await block(e, c, { maxVisits: 1 });
    assert.equal(r.stopped, null);
    const st = loadState(e.raw);
    assert.deepEqual(st.thermal.slice(0, 3).map((t) => [t.state, t.verdict, t.why]), [['Nominal', 'wait', 'rising'], ['Fair', 'wait', 'rising'], ['Serious', 'go', 'onTarget']]);
    assert.equal(c.visits, 1);
    assert.ok(c.order.slice(0, c.order.indexOf('frames')).filter((x) => x === `sleep ${PIN.pinPollS * 1000}`).length >= 2);
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('pinned block: a state that never reaches the target runs no visit and stops after the wait budget', async () => {
  const e = setup();
  try {
    const c = phone(fakeWorld(), { senses: [S('Fair')] });
    const r = await block(e, c);
    assert.match(r.stopped, /did not reach the target in time/);
    assert.equal(c.visits, 0);
    assert.deepEqual(c.lanes, []);
    const last = loadState(e.raw).thermal.at(-1);
    assert.equal(last.why, 'timeout');
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('pinned block: Critical between the lanes refuses the visit, the counts lane never runs, the raw files are not written', async () => {
  const e = setup();
  try {
    const c = phone(fakeWorld(), { senses: [S('Serious'), S('Critical')] });
    const r = await block(e, c);
    assert.match(r.stopped, /refused.*Critical/);
    assert.deepEqual(c.lanes, ['frames']);
    const st = loadState(e.raw);
    assert.equal(st.visits[0].status, 'refused');
    assert.deepEqual(st.visits[0].pin, { why: 'critical', phase: 'between-lanes' });
    assert.equal(existsSync(join(e.raw, '00-base.counts.json')), false);
    assert.equal(existsSync(join(e.raw, '00-base.frames.json')), false);
    const sum = reduceDir({ dir: e.raw, out: join(e.dir, 'out') });
    assert.deepEqual(sum.notRun.map((n) => n.status), ['refused']);
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('pinned block: a state below the target after the visit refuses it; the next block runs the visit again', async () => {
  const e = setup();
  try {
    const c = phone(fakeWorld(), { senses: [S('Serious'), S('Serious'), S('Fair')] });
    const r = await block(e, c);
    assert.match(r.stopped, /fell below the target/);
    const st = loadState(e.raw);
    assert.equal(st.visits[0].status, 'refused');
    assert.deepEqual(st.visits[0].pin, { why: 'below', phase: 'visit-end' });
    assert.equal(existsSync(join(e.raw, '00-base.counts.json')), false);
    const c2 = phone(fakeWorld(), { senses: [S('Serious')] });
    const r2 = await block(e, c2, { maxVisits: 1 });
    assert.deepEqual(r2.ran.map((x) => x.index), [0]);
    assert.equal(loadState(e.raw).visits[0].status, 'done');
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('pinned block: when the owner is gone nothing runs, even at a Serious reading', async () => {
  const e = setup();
  try {
    let alive = true;
    const c = phone(fakeWorld(), { senses: [S('Serious')], held: () => alive, onVisit: () => { alive = false; } });
    const r = await block(e, c);
    assert.match(r.stopped, /owner process is not running/);
    assert.deepEqual(c.lanes, ['frames']);
    const blocked = await block(e, phone(fakeWorld(), { senses: [S('Serious')], held: () => false }));
    assert.match(blocked.stopped, /owner process is not running/);
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('pinned block: a locked phone stops the block', async () => {
  const e = setup();
  try {
    const c = phone(fakeWorld(), { senses: [S('Serious', { lock: 'locked' })] });
    const r = await block(e, c);
    assert.match(r.stopped, /locked/);
    assert.equal(c.visits, 0);
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

const session3 = async (e, { senses, dieOn, body, readSenses, listOk }) => {
  const w = fakeWorld({ dieOn, listOk });
  const { owner } = mkOwner(w);
  owner.dir = e.raw;
  owner.recFile = join(e.raw, 'pin-owner.json');
  const c = phone(w, { senses });
  let k = 0;
  const sense = () => { const s = readSenses[Math.min(k++, readSenses.length - 1)]; if (s instanceof Error) throw s; return s; };
  const out = { w, c, owner };
  try {
    out.result = await pinnedSession({ target: 'Serious', dir: e.raw, log: () => {}, owner, sense, signals: false, now: () => w.t, sleep: async (ms) => { w.t += ms; }, body: (pin) => (body ? body(pin, c, e, w) : block(e, { ...c, pin }, { maxVisits: 1 })) });
  } catch (err) { out.err = err; }
  out.st = loadState(e.raw);
  return out;
};

test('session: induce, run, stop with SIGTERM, read back below the target: ended cleared, the condition not set', async () => {
  const e = setup();
  try {
    const o = await session3(e, { senses: [S('Serious')], readSenses: [S('Fair')] });
    assert.equal(o.err, undefined);
    assert.deepEqual(o.w.signals, ['SIGTERM']);
    assert.equal(o.st.pin.end, 'cleared');
    assert.equal(o.st.pin.conditionSet, false);
    assert.equal(o.st.pin.acked, true);
    assert.equal(o.st.pin.profile, 'ThermalSerious');
    assert.equal(o.st.pin.owner.pid, 4000);
    assert.deepEqual(o.st.pin.readback.map((r) => r.state), ['Fair']);
    assert.equal(o.owner.alive(), false);
    assert.equal(o.st.visits[0].status, 'done');
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('session: a failing body still stops the owner and reads back (the finally path)', async () => {
  const e = setup();
  try {
    const o = await session3(e, { senses: [S('Serious')], readSenses: [S('Nominal')], body: async () => { throw new Error('phone dropped'); } });
    assert.match(o.err.message, /phone dropped/);
    assert.deepEqual(o.w.signals, ['SIGTERM']);
    assert.equal(o.st.pin.end, 'cleared');
    assert.equal(o.owner.alive(), false);
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('session: a start that fails (profile not listed) leaves no process and no condition', async () => {
  const e = setup();
  try {
    const o = await session3(e, { senses: [S('Serious')], readSenses: [S('Nominal')], listOk: false });
    assert.match(o.err.message, /condition list exited/);
    assert.equal(o.w.spawned.length, 0);
    assert.deepEqual(o.w.signals, []);
    assert.equal(o.st.pin.conditionSet, false);
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('session: an owner that dies by itself leaves the condition possibly set: the next lane is refused and the end is unconfirmed', async () => {
  const e = setup();
  try {
    const o = await session3(e, {
      senses: [S('Serious')], readSenses: [S('Fair')],
      body: (pin, c, ee, w) => { const dying = phone(w, { senses: [S('Serious')], held: pin.held, onVisit: () => { w.procs.clear(); } }); return block(ee, { ...dying, pin }); },
    });
    assert.deepEqual(o.w.signals, []);
    assert.match(o.err.message, /without confirming its clear/);
    assert.equal(o.st.pin.end, 'unconfirmed');
    assert.equal(o.st.pin.conditionSet, true);
    assert.equal(o.st.pin.acked, false);
    assert.equal(o.st.visits[0].status, 'refused');
    assert.deepEqual(o.st.visits[0].pin, { why: 'notHeld', phase: 'between-lanes' });
    assert.equal(o.w.log, '');
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('session: an owner that needs SIGKILL never confirmed its clear: gone, unconfirmed, condition possibly set', async () => {
  const e = setup();
  try {
    const o = await session3(e, { senses: [S('Serious')], readSenses: [S('Serious')], dieOn: ['SIGKILL'] });
    assert.deepEqual(o.w.signals, ['SIGTERM', 'SIGKILL']);
    assert.match(o.err.message, /without confirming its clear/);
    assert.equal(o.st.pin.end, 'unconfirmed');
    assert.equal(o.st.pin.conditionSet, true);
    assert.equal(o.owner.alive(), false);
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('session: an owner that survives SIGKILL is reported stuck, the session fails, the state says the condition may be set', async () => {
  const e = setup();
  try {
    const o = await session3(e, { senses: [S('Serious')], readSenses: [S('Serious')], dieOn: [] });
    assert.match(o.err.message, /did not exit/);
    assert.deepEqual(o.w.signals, ['SIGTERM', 'SIGKILL']);
    assert.equal(o.st.pin.end, 'stuck');
    assert.equal(o.st.pin.conditionSet, true);
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('session: a read-back that stays at the target is retried within the budget and then ends heatRemains; an unreadable one ends unread', async () => {
  const e = setup();
  try {
    const o = await session3(e, { senses: [S('Serious')], readSenses: [S('Serious')] });
    assert.equal(o.st.pin.end, 'heatRemains');
    assert.ok(o.st.pin.readback.length > 2);
    assert.equal(o.st.pin.conditionSet, false);
    const e2 = setup();
    const o2 = await session3(e2, { senses: [S('Serious')], readSenses: [new Error('xctrace failed')] });
    assert.equal(o2.st.pin.end, 'unread');
    rmSync(e2.dir, { recursive: true, force: true });
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});

test('session: the first run starts only after an earlier run\'s owner is stopped', async () => {
  const e = setup();
  try {
    const w = fakeWorld();
    const first = mkOwner(w);
    first.owner.dir = e.raw;
    first.owner.recFile = join(e.raw, 'pin-owner.json');
    await first.owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    const o = await session3(e, { senses: [S('Serious')], readSenses: [S('Fair')] });
    assert.equal(o.err, undefined);
    assert.equal(readFileSync(join(e.raw, 'pin-owner.json'), 'utf8').includes('stoppedAt'), true);
  } finally { rmSync(e.dir, { recursive: true, force: true }); }
});
