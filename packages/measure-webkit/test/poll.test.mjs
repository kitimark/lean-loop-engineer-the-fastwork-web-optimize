import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pollUntil, ensureTab, attachFresh, retryWhile } from '../src/poll.mjs';
import { reconnect, navigateTab } from '../src/wip.mjs';
import { phoneIds } from '../src/sim.mjs';

// A fake clock: sleeping only moves the time forward, so a 4-minute deadline costs no real time.
const fakeClock = () => { const c = { t: 0, slept: 0, now: () => c.t, sleep: async (ms) => { c.t += ms; c.slept += ms; } }; return c; };

test('pollUntil returns as soon as the condition holds and does not wait the full bound', async () => {
  const clock = fakeClock();
  let n = 0;
  const v = await pollUntil(() => ++n >= 3 && 'ok', { timeoutMs: 24000, intervalMs: 250, clock });
  assert.equal(v, 'ok');
  assert.equal(clock.slept, 500); // 2 polls of 250 ms, not the 24 s of a fixed T(3000) at scale 8
});
test('pollUntil counts a throw as not ready and fails at the deadline with the last reason', async () => {
  const clock = fakeClock();
  await assert.rejects(pollUntil(() => { throw new Error('stalled'); }, { timeoutMs: 1000, intervalMs: 250, clock, what: 'tab' }), /tab not ready in 1 s \(stalled\)/);
  assert.equal(clock.t, 1000);
});

test('ensureTab (session.mjs): returns at once when the tab is listed, asks nothing more', async () => {
  const clock = fakeClock();
  let asked = 0;
  const r = await ensureTab({ list: async () => [{ url: 'u' }], ask: () => { asked++; }, timeoutMs: 240000, clock });
  assert.equal(r.asks, 0);
  assert.equal(asked, 0);
  assert.equal(clock.slept, 0); // the old code slept T(3000) = 24 s here first
});
test('ensureTab re-sends openurl every 6 s while no tab is listed, and stops once one is', async () => {
  const clock = fakeClock();
  const askedAt = [];
  // the first openurl was dropped, the second one landed: the tab appears 1 s after the 2nd extra ask
  const r = await ensureTab({
    list: async () => (askedAt.length >= 2 && clock.t >= askedAt[1] + 1000 ? [{ url: 'u' }] : []),
    ask: () => askedAt.push(clock.t), timeoutMs: 240000, intervalMs: 500, clock,
  });
  assert.equal(r.asks, 2);
  assert.deepEqual(askedAt, [6000, 12000]);
  assert.ok(clock.t >= 13000 && clock.t < 14000, `returned at ${clock.t}`);
});
test('ensureTab gives up at the deadline and survives a list error and an ask error', async () => {
  const clock = fakeClock();
  let asks = 0;
  await assert.rejects(ensureTab({ list: async () => { throw new Error('fetch failed'); }, ask: () => { asks++; throw new Error('openurl failed'); }, timeoutMs: 20000, clock }), /no Safari tab listed in 20 s \(fetch failed; 3 extra openurl\)/);
  assert.equal(asks, 3); // at 6, 12 and 18 s
});

test('ensureTab with maxAsks 1 (the relaunch) asks at most once and not at all when Safari restored its tab', async () => {
  const clock = fakeClock();
  let asked = 0;
  await assert.rejects(ensureTab({ list: async () => [], ask: () => { asked++; }, maxAsks: 1, timeoutMs: 60000, clock }), /no Safari tab listed in 60 s \(no tab listed; 1 extra openurl\)/);
  assert.equal(asked, 1);
  asked = 0;
  const r = await ensureTab({ list: async () => [{ url: 'u' }], ask: () => { asked++; }, maxAsks: 1, timeoutMs: 60000, clock });
  assert.equal(r.asks, 0);
  assert.equal(asked, 0, 'one restored tab: no second one is opened');
});
test('reconnect keeps the client that a relaunch connected and opens no second one', async () => {
  const old = { close: async () => {} }, fresh = { id: 'fresh' };
  const ctx = { c: old, url: 'u', setClient: (c) => { ctx.c = c; }, ensureProxy: async () => { ctx.setClient(fresh); } };
  let opened = 0;
  await reconnect(ctx, { openTabFn: async () => { opened++; return 'again'; } });
  assert.equal(ctx.c, fresh);
  assert.equal(opened, 0);
});

test('attachFresh releases a client that attached to the old document and returns the fresh one', async () => {
  const clock = fakeClock();
  const docs = [{ fresh: false }, { fresh: false }, { fresh: true, complete: 2 }];
  let i = 0; const released = [];
  const c = await attachFresh({
    attach: async () => docs[i++],
    isFresh: async (d) => d.fresh,
    ready: async (d) => --d.complete <= 0,
    release: async (d) => { released.push(d); },
    timeoutMs: 60000, clock,
  });
  assert.equal(c, docs[2]);
  assert.deepEqual(released, [docs[0], docs[1]]);
  assert.ok(clock.slept < 3000, `waited ${clock.slept} ms, not a fixed T(2000)=16 s`);
});
test('attachFresh fails at the deadline when only the old document is ever listed', async () => {
  const clock = fakeClock();
  await assert.rejects(attachFresh({ attach: async () => ({}), isFresh: async () => false, ready: async () => true, release: async () => {}, timeoutMs: 5000, clock }), /no fresh document after the navigation in 5 s/);
});

test('navigateTab (wip.mjs): marks the old document, closes, then attaches to the fresh one without a fixed sleep', async () => {
  const clock = fakeClock();
  const evals = [];
  const old = { evaluate: async (e) => { evals.push(e); return 'nav'; }, close: async () => { evals.push('close-old'); } };
  const stale = { evaluate: async (e) => (/__fwNav/.test(e) ? false : 'loading'), close: async () => { evals.push('close-stale'); } };
  const fresh = { evaluate: async (e) => (/__fwNav/.test(e) ? true : 'complete'), close: async () => {} };
  const queue = [stale, fresh];
  const c = await navigateTab(old, 'http://127.0.0.1:1/', { clock, openTabFn: async () => queue.shift() });
  assert.equal(c, fresh);
  assert.match(evals[0], /window\.__fwNav = 1; setTimeout/);
  assert.deepEqual(evals.slice(1), ['close-old', 'close-stale']);
  assert.ok(clock.slept <= 1000, `slept ${clock.slept}`);
});

test('reconnect (wip.mjs): closes, ensures the proxy, attaches, and has no fixed pause', async () => {
  const order = [];
  const ctx = { url: 'http://127.0.0.1:1/', c: { close: async () => { order.push('close'); } }, ensureProxy: async () => { order.push('proxy'); }, setClient: (c) => { order.push('set:' + c); } };
  const t0 = Date.now();
  await reconnect(ctx, { openTabFn: async () => { order.push('open'); return 'new'; } });
  assert.deepEqual(order, ['close', 'proxy', 'open', 'set:new']);
  assert.ok(Date.now() - t0 < 500, 'a fixed T(1500) pause would show here');
});

test('phoneIds (sim.mjs): a timeout is asked again with a scaled timeout, ENOENT means no phones, a real failure stops', () => {
  const calls = [];
  const id = 'A'.repeat(25);
  const exec = (cmd, args, opts) => {
    calls.push([args[0], opts.timeoutMs]);
    if (calls.length === 1) return { status: null, stdout: '', stderr: '', error: Object.assign(new Error('t'), { code: 'ETIMEDOUT' }) };
    return { status: 0, stdout: args[0] === '-l' ? id + '\n' : '', stderr: '' };
  };
  assert.deepEqual(phoneIds({ exec }), [id]);
  assert.deepEqual(calls.map((c) => c[0]), ['-l', '-l', '-n']);
  assert.equal(calls[0][1], 15000 * Number(process.env.FW_WK_TIMEOUT_SCALE ?? 1));
  assert.deepEqual(phoneIds({ exec: () => ({ status: null, stdout: '', stderr: '', error: Object.assign(new Error('x'), { code: 'ENOENT' }) }) }), []);
  assert.throws(() => phoneIds({ exec: () => ({ status: 1, stdout: '', stderr: '' }) }), /not starting the proxy/);
  let n = 0;
  assert.throws(() => phoneIds({ exec: () => { n++; return { status: null, stdout: '', stderr: '', error: Object.assign(new Error('t'), { code: 'ETIMEDOUT' }) }; }, tries: 3 }), /not starting the proxy/);
  assert.equal(n, 3);
});

test('retryWhile stops at the first result that is not retryable', () => {
  let n = 0;
  assert.equal(retryWhile(() => ++n, { tries: 5, retryable: (x) => x < 3 }), 3);
  assert.equal(retryWhile(() => ++n, { tries: 2, retryable: () => true }), 5);
});
