// The liveness guard (src/guard.mjs) and the relaunch steps, with injected probes: no Simulator, no waiting beyond a few ms.
// The rule itself is checked against the Lean goldens in fwcore.test.mjs; here the glue: probe -> action -> relaunch once -> give up.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGuard, runSteps, within } from '../src/guard.mjs';
import { createServer } from 'node:http';
import { InspectorDeadError, DEAD_EXIT, inspectorAfterRelaunch } from '../src/inspector.mjs';
import { probeInspector, SIM_ID } from '../src/sim.mjs';

const UP = { socket: true, proxy: true, page: true };
const NO_PROXY = { socket: true, proxy: false, page: false };      // ECONNREFUSED, 0 devices or a timeout
const NO_PAGE = { socket: true, proxy: true, page: false };        // Safari gone, proxy still listing the Simulator
const NO_SOCKET = { socket: false, proxy: false, page: false };
const script = (...ps) => { let i = 0; return async () => ps[Math.min(i++, ps.length - 1)]; };
const make = (probe, o = {}) => {
  const lines = [], dead = [], calls = { relaunch: 0, repair: 0 };
  const g = createGuard({
    probe, log: (s) => lines.push(s), onDead: (e) => dead.push(e), tickMs: 5,
    relaunch: async () => { calls.relaunch++; if (o.relaunchFails) throw new Error('boom'); },
    repair: async () => { calls.repair++; }, reboot: null, deviceUp: async () => true,
  });
  return { g, lines, dead, calls };
};

test('a healthy inspector proceeds and resets the count', async () => {
  const { g, calls } = make(script(NO_PROXY, UP, NO_PROXY, UP));
  for (let i = 0; i < 4; i++) await g.check();
  assert.equal(g.fails, 0);
  assert.equal(calls.relaunch, 0);
});

test('one failed probe proceeds; with repair it starts the proxy again', async () => {
  const { g, calls } = make(script(NO_PROXY, UP));
  const r = await g.check('reconnect', { repair: true });
  assert.deepEqual(r, { ok: false, relaunched: false });
  assert.equal(calls.repair, 1);
  assert.equal((await g.check()).ok, true);
});

for (const [name, bad] of [['proxy refused', NO_PROXY], ['page missing', NO_PAGE]]) {
  test(`${name} twice in a row relaunches once, then two more failures give up with exit 4`, async () => {
    const { g, lines, dead, calls } = make(script(bad, bad, bad, bad));
    await g.check(); // fails 1: proceed
    const r = await g.check(); // fails 2: dead -> relaunch
    assert.equal(r.relaunched, true);
    assert.equal(calls.relaunch, 1);
    await g.check(); // after the relaunch: fails 1
    await assert.rejects(g.check(), (e) => e instanceof InspectorDeadError && e.exitCode === DEAD_EXIT && e.exitCode === 4);
    assert.equal(calls.relaunch, 1, 'no third launch');
    assert.equal(dead.length, 1);
    assert.ok(lines.some((l) => /relaunching Safari once/.test(l)));
    assert.ok(lines.some((l) => /giving up/.test(l) && /exit code 4/.test(l)));
    await assert.rejects(g.check(), InspectorDeadError); // once dead, always dead
  });
}

test('a gone socket relaunches at once; a gone socket after the relaunch gives up at once', async () => {
  const { g, calls } = make(script(NO_SOCKET, NO_SOCKET));
  assert.equal((await g.check()).relaunched, true);
  await assert.rejects(g.check(), InspectorDeadError);
  assert.equal(calls.relaunch, 1);
});

test('a relaunch that fails gives up without a second one', async () => {
  const { g, lines, calls } = make(script(NO_SOCKET), { relaunchFails: true });
  await assert.rejects(g.check(), (e) => /relaunching Safari failed: boom/.test(e.message) && e.exitCode === 4);
  assert.equal(calls.relaunch, 1);
  assert.ok(lines.some((l) => /giving up: .*relaunching Safari failed/.test(l)));
});

test('a probe that never answers counts as failed once its bound is over', async () => {
  const lines = [];
  const g = createGuard({ probe: () => new Promise(() => {}), relaunch: async () => {}, reboot: null, probeMs: 10, log: (s) => lines.push(s) });
  assert.equal((await g.check()).ok, false);
  assert.equal(g.fails, 1);
  assert.equal((await g.check()).relaunched, true, 'the second timeout makes it dead');
});

test('a failed probe after a host freeze counts one: stale failures before it are dropped', async () => {
  let frozenCount = 0, relaunches = 0;
  const g = createGuard({ probe: script(NO_PROXY), relaunch: async () => { relaunches++; }, reboot: null, deviceUp: async () => true, frozenCount: () => frozenCount });
  await g.check();
  assert.equal(g.fails, 1);
  frozenCount++;
  assert.equal((await g.check()).relaunched, false, 'the first failure after the freeze');
  assert.equal(g.fails, 1);
  assert.equal((await g.check()).relaunched, true, 'two in a row after it are dead');
  assert.equal(relaunches, 1);
});

test('the relaunch after a reboot is asked for a fresh start (no Safari to terminate)', async () => {
  const seen = [];
  const g = createGuard({
    probe: script(NO_SOCKET), relaunch: async (o) => { seen.push(o ?? null); }, reboot: async () => {}, deviceUp: async () => false, frozenCount: () => 0,
  });
  await g.check();
  assert.deepEqual(seen, [{ fresh: true }]);
});

test('a relaunch over its bound gives up', async () => {
  const g = createGuard({ probe: script(NO_SOCKET), relaunch: () => new Promise(() => {}), reboot: null, relaunchMs: 10 });
  await assert.rejects(g.check(), /relaunching Safari failed: the relaunch took longer/);
});

test('ticks probe by themselves, share a running check, and call onDead once', async () => {
  const { g, dead, calls } = make(script(NO_SOCKET, NO_SOCKET));
  g.start();
  await new Promise((r) => setTimeout(r, 80));
  g.stop();
  assert.equal(calls.relaunch, 1);
  assert.equal(dead.length, 1);
  assert.ok(dead[0] instanceof InspectorDeadError);
});

test('concurrent checks share one probe', async () => {
  let n = 0;
  const { g } = make(async () => { n++; await new Promise((r) => setTimeout(r, 10)); return UP; });
  await Promise.all([g.check(), g.check(), g.check()]);
  assert.equal(n, 1);
});

test('runSteps runs in order and stops at the first step over its bound', async () => {
  const order = [];
  await runSteps([{ name: 'a', ms: 100, run: async () => order.push('a') }, { name: 'b', ms: 100, run: () => order.push('b') }]);
  assert.deepEqual(order, ['a', 'b']);
  await assert.rejects(runSteps([{ name: 'slow', ms: 10, run: () => new Promise(() => {}) }, { name: 'never', ms: 10, run: () => order.push('never') }]), /slow took longer than 0 s/);
  assert.ok(!order.includes('never'));
  await assert.rejects(within(5, 'x', new Promise(() => {})), /x took longer/);
});

test('the give-up after a failed relaunch is the stand-in of Lean afterRelaunch', () => {
  assert.equal(inspectorAfterRelaunch(false), 'giveUp');
  assert.equal(inspectorAfterRelaunch(true), 'proceed');
});

test('the probe counts a listed tab without a webSocketDebuggerUrl as no page', async () => {
  const serve = (body) => new Promise((res) => { const s = createServer((_, r) => { r.setHeader('content-type', 'application/json'); r.end(JSON.stringify(body)); }); s.listen(0, '127.0.0.1', () => res(s)); });
  const list = await serve([{ deviceId: SIM_ID }]);
  const bare = await serve([{ url: 'http://127.0.0.1:1/p' }]);
  const full = await serve([{ url: 'http://127.0.0.1:1/p', webSocketDebuggerUrl: 'ws://x' }]);
  try {
    const ask = (tabs) => probeInspector({ urlPrefix: 'http://127.0.0.1:1/', p: { list: list.address().port, tabs: tabs.address().port }, timeoutMs: 2000, sockets: () => ['s'] });
    assert.deepEqual(await ask(bare), { socket: true, proxy: true, page: false });
    assert.deepEqual(await ask(full), { socket: true, proxy: true, page: true });
  } finally { for (const s of [list, bare, full]) s.close(); }
});
