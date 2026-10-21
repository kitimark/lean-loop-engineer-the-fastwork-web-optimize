// A lost page target (Lean: Fw.Measure.SimBound, task webkit-sim-target-lost): the wait is bounded at 480 s, Safari is
// relaunched once, a second loss fails the session with exit code 5. The decision is checked against the Lean goldens
// (measure.targetLost, measure.simBounds); the glue (wip.mjs reconnect, target.mjs, guard.mjs) runs against a fake
// inspector on a virtual clock, so 480 s of waiting take a few ms. No Simulator.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { BOUNDS, TargetLostError, TARGET_LOST_EXIT, targetReply } from '../src/inspector.mjs';
import { waitForTarget, capped } from '../src/target.mjs';
import { reconnect } from '../src/wip.mjs';
import { createGuard } from '../src/guard.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const GOLDEN = join(HERE, '../../contracts/golden/measure');
const BIN = process.env.FW_CORE_BIN ?? resolve(HERE, '../../../lean/.lake/build/bin/fwcore');
const load = (op) => readFileSync(join(GOLDEN, `${op}.jsonl`), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('measure.targetLost: fwcore (Lean) reproduces every golden row', () => {
  assert.ok(existsSync(BIN), `fwcore not found at ${BIN}; build it with: cd lean && lake build`);
  const cases = load('measure.targetLost');
  const input = cases.map((c, i) => JSON.stringify({ ...c.request, id: i })).join('\n') + '\n';
  const r = spawnSync(BIN, [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 26 });
  assert.equal(r.status, 0, `fwcore exit: ${r.stderr}`);
  const got = r.stdout.toString().trim().split('\n').map((l) => { const { id, ...rest } = JSON.parse(l); return rest; });
  cases.forEach((c, i) => assert.deepStrictEqual(got[i], c.response, c.name));
});

test('measure.targetLost: src/inspector.mjs agrees with every golden row, every branch is there', () => {
  const cases = load('measure.targetLost');
  for (const c of cases) assert.deepStrictEqual(targetReply(c.request), c.response, c.name);
  const seen = new Set(cases.map((c) => c.response.action));
  for (const a of ['connect', 'wait', 'relaunch', 'failSession']) assert.ok(seen.has(a), `no golden row for ${a}`);
  assert.ok(cases.some((c) => c.response.afterRelaunch === 'wait') && cases.some((c) => c.response.afterRelaunch === 'failSession'));
});

test('measure.simBounds: the target constants are the golden ones', () => {
  const [row] = load('measure.simBounds');
  for (const k of ['targetWaitMs', 'targetAfterMs', 'targetEndMs', 'targetLostExit']) assert.equal(BOUNDS[k], row.response[k], k);
  assert.equal(TARGET_LOST_EXIT, 5);
});

// A virtual clock: timers fire in order of their time, microtasks run between them.
function virtualClock() {
  let t = 0, seq = 0;
  const timers = [];
  const after = (ms, fn) => { const e = { at: t + ms, seq: seq++, fn }; timers.push(e); return () => { const i = timers.indexOf(e); if (i >= 0) timers.splice(i, 1); }; };
  return {
    now: () => t, sleep: (ms) => new Promise((r) => after(ms, r)), after,
    async run(p) {
      let done = false, val, err, failed = false;
      p.then((v) => { done = true; val = v; }, (e) => { done = true; failed = true; err = e; });
      for (let i = 0; i < 200000 && !done; i++) {
        await new Promise((r) => setImmediate(r));
        if (done) break;
        timers.sort((a, b) => a.at - b.at || a.seq - b.seq);
        const e = timers.shift();
        if (e) { t = Math.max(t, e.at); e.fn(); }
      }
      assert.ok(done, 'the wait never ended');
      if (failed) throw err;
      return val;
    },
  };
}

// A fake inspector: while `lost`, a poll fails like the real one ("no page target"), or hangs when `hang` is set. A relaunch
// brings the target back when `restores` is set, after `relaunchMs` of virtual time.
function fakeInspector(clock, { lostFromMs = 0, backAtMs = Infinity, restores = false, hang = false, relaunchMs = 10000, relaunchFails = false } = {}) {
  const f = { polls: 0, caps: [], relaunches: 0, relaunchedAt: [], closed: 0, restored: false };
  const lost = () => clock.now() >= lostFromMs && clock.now() < backAtMs && !f.restored;
  f.tryOnce = (cap) => {
    f.polls++; f.caps.push(cap);
    if (!lost()) return Promise.resolve({ id: f.polls, close: () => { f.closed++; } });
    if (hang) return new Promise(() => {});
    return Promise.reject(new Error('no page target (is another inspector client attached to this tab?)'));
  };
  f.relaunch = async () => {
    f.relaunches++; f.relaunchedAt.push(clock.now());
    await clock.sleep(relaunchMs);
    if (relaunchFails) throw new Error('Safari was relaunched already');
    if (restores) f.restored = true;
  };
  return f;
}
const pause = (e) => (/no page target/.test(e.message) ? 2000 : 500);
const wait = (clock, f, o = {}) => waitForTarget({ tryOnce: f.tryOnce, relaunch: f.relaunch, pauseMs: pause, clock, late: (c) => c.close(), ...o });

test('a target that answers connects at once: no relaunch, no wait', async () => {
  const clock = virtualClock(), f = fakeInspector(clock, { lostFromMs: Infinity });
  const c = await clock.run(wait(clock, f));
  assert.equal(c.id, 1); assert.equal(f.relaunches, 0); assert.equal(clock.now(), 0);
});

test('a target that returns at 470 s connects without a relaunch', async () => {
  const clock = virtualClock(), f = fakeInspector(clock, { backAtMs: 470000 });
  await clock.run(wait(clock, f));
  assert.equal(f.relaunches, 0);
  assert.ok(clock.now() >= 470000 && clock.now() < 473000, `connected at ${clock.now()}`);
});

test('a lost target is waited for 480 s, then Safari is relaunched once and the target is back', async () => {
  const clock = virtualClock(), f = fakeInspector(clock, { restores: true });
  const logs = [];
  const c = await clock.run(wait(clock, f, { log: (s) => logs.push(s) }));
  assert.ok(c.id > 1);
  assert.equal(f.relaunches, 1);
  assert.ok(f.relaunchedAt[0] >= BOUNDS.targetWaitMs && f.relaunchedAt[0] <= BOUNDS.targetWaitMs + 2000, `relaunch at ${f.relaunchedAt[0]}`);
  assert.ok(logs.some((l) => /relaunching Safari once/.test(l)));
});

test('a target that stays lost through the one relaunch fails the session: exit 5, within the Lean end bound', async () => {
  const clock = virtualClock(), f = fakeInspector(clock, { restores: false });
  await assert.rejects(clock.run(wait(clock, f)), (e) => {
    assert.ok(e instanceof TargetLostError); assert.equal(e.exitCode, 5); assert.equal(e.name, 'TargetLostError');
    return true;
  });
  assert.equal(f.relaunches, 1, 'Safari is relaunched at most once');
  const relaunchCost = 10000;
  assert.ok(clock.now() <= BOUNDS.targetWaitMs + relaunchCost + BOUNDS.targetAfterMs + 2000, `ended at ${clock.now()}`);
  assert.ok(clock.now() + BOUNDS.exitMs <= BOUNDS.targetEndMs + 2000);
});

test('a poll that hangs is dropped at the bound: the lost runs waited 876 s of 480 s in one try', async () => {
  const clock = virtualClock(), f = fakeInspector(clock, { hang: true, restores: true });
  await clock.run(wait(clock, f));
  assert.equal(f.relaunches, 1);
  assert.equal(f.relaunchedAt[0], BOUNDS.targetWaitMs, 'the first (hung) poll is capped to the rest of the bound');
  assert.equal(f.caps[0], BOUNDS.targetWaitMs);
});

test('every poll gets at most what is left of the bound', async () => {
  const clock = virtualClock(), f = fakeInspector(clock, { restores: false });
  await assert.rejects(clock.run(wait(clock, f)), TargetLostError);
  for (const cap of f.caps) assert.ok(cap > 0 && cap <= BOUNDS.targetWaitMs);
  assert.equal(f.caps[0], BOUNDS.targetWaitMs);
  assert.ok(f.caps.some((c) => c <= BOUNDS.targetAfterMs && c > 0));
});

test('a client that connects after its poll was dropped is closed', async () => {
  const clock = virtualClock();
  let resolveLate;
  const late = new Promise((r) => { resolveLate = r; });
  const closed = [];
  const p = capped(1000, late, { after: clock.after, late: (c) => closed.push(c) });
  const out = clock.run(p);
  await assert.rejects(out, /took longer than 1 s/);
  resolveLate('client');
  await new Promise((r) => setImmediate(r));
  assert.deepEqual(closed, ['client']);
});

test('no relaunch available (or Safari already relaunched): the first loss fails the session at the bound, no second relaunch', async () => {
  for (const relaunch of [null, 'rejects']) {
    const clock = virtualClock(), f = fakeInspector(clock, { relaunchFails: true });
    await assert.rejects(clock.run(waitForTarget({ tryOnce: f.tryOnce, relaunch: relaunch ? f.relaunch : null, pauseMs: pause, clock })), (e) => e instanceof TargetLostError && e.exitCode === 5);
    assert.equal(f.relaunches, relaunch ? 1 : 0);
    assert.ok(clock.now() >= BOUNDS.targetWaitMs && clock.now() <= BOUNDS.targetWaitMs + 11000);
  }
});

test('reconnect (wip.mjs): closes, ensures the proxy, waits for the target, relaunches through ctx.relaunchTab, sets the new client', async () => {
  const clock = virtualClock(), f = fakeInspector(clock, { restores: true });
  const order = [];
  const ctx = {
    url: 'http://127.0.0.1:1/', c: { close: async () => { order.push('close'); } }, ensureProxy: async () => { order.push('proxy'); },
    relaunchTab: async () => { order.push('relaunch'); await f.relaunch(); }, setClient: (c) => { order.push('set'); ctx.got = c; },
  };
  await clock.run(reconnect(ctx, { openTabFn: (_u, { waitMs }) => f.tryOnce(waitMs), clock }));
  assert.deepEqual(order, ['close', 'proxy', 'relaunch', 'set']);
  assert.ok(ctx.got.id > 1);
});

test('reconnect with a target that stays lost ends in TargetLostError (the lag probe stops its passes on it)', async () => {
  const clock = virtualClock(), f = fakeInspector(clock, { restores: false });
  const ctx = { url: 'http://127.0.0.1:1/', c: { close: async () => {} }, relaunchTab: f.relaunch, setClient: () => assert.fail('no client') };
  await assert.rejects(clock.run(reconnect(ctx, { openTabFn: (_u, { waitMs }) => f.tryOnce(waitMs), clock })), TargetLostError);
  assert.equal(f.relaunches, 1);
});

// the guard's one relaunch is shared between the dead-inspector rule and the lost page target
const UP = { socket: true, proxy: true, page: true };
const guardWith = (probe) => {
  const calls = { relaunch: 0 };
  const g = createGuard({ probe: async () => probe, relaunch: async () => { calls.relaunch++; }, tickMs: 5 });
  return { g, calls };
};
test('guard.relaunchTab: relaunches once, a second call is refused', async () => {
  const { g, calls } = guardWith(UP);
  await g.relaunchTab();
  assert.equal(calls.relaunch, 1); assert.equal(g.relaunched, true);
  await assert.rejects(g.relaunchTab(), /relaunched already/);
  assert.equal(calls.relaunch, 1);
});
test('guard.relaunchTab: refused after the dead-inspector rule relaunched Safari', async () => {
  const { g, calls } = guardWith({ socket: false, proxy: false, page: false });
  await g.check();
  assert.equal(calls.relaunch, 1);
  await assert.rejects(g.relaunchTab(), /relaunched already/);
  assert.equal(calls.relaunch, 1);
});
test('guard.relaunchTab: a relaunch that fails rejects (the wait then fails the session)', async () => {
  const g = createGuard({ probe: async () => UP, relaunch: async () => { throw new Error('boom'); }, tickMs: 5 });
  await assert.rejects(g.relaunchTab(), /boom/);
});
