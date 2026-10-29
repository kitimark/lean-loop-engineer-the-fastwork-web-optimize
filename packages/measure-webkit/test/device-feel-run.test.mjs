import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { callControl, makeGate, startControl, waitGone } from '../src/device-feel-run.mjs';
import { cmdNext, cmdRate, cmdStatus, freshState, loadFeel, saveFeel } from '../src/device-feel.mjs';

const pinOf = (held = true) => ({ held: () => held, onHeld: () => {} });
const senseSeq = (...states) => { let i = 0; return () => states[Math.min(i++, states.length - 1)]; };
const ok = (state) => ({ state, lock: 'unlocked', tempC: 30 });

test('the gate waits while the state rises and goes at the target', async () => {
  let t = 0;
  const gate = makeGate({ target: 'Serious', pin: pinOf(), sense: senseSeq(ok('Nominal'), ok('Fair'), ok('Serious')), sleep: async () => { t += 5000; }, now: () => t });
  const g = await gate();
  assert.equal(g.ok, true);
  assert.equal(g.reading.state, 'Serious');
  assert.equal(t, 10000);
});

test('the gate refuses on Critical, a locked phone, a dead owner, a state above and a fall after the first go', async () => {
  const run = async (sense, held = true, first = null) => {
    const gate = makeGate({ target: 'Serious', pin: pinOf(held), sense, sleep: async () => {}, now: () => 0 });
    if (first) await gate();
    return gate();
  };
  assert.match((await run(senseSeq(ok('Critical')))).why, /Critical/);
  assert.match((await run(senseSeq({ state: 'Serious', lock: 'locked' }))).why, /locked/);
  assert.match((await run(senseSeq(ok('Serious')), false)).why, /not running/);
  const fell = makeGate({ target: 'Serious', pin: pinOf(), sense: senseSeq(ok('Serious'), ok('Fair')), sleep: async () => {}, now: () => 0 });
  assert.equal((await fell()).ok, true);
  const second = await fell();
  assert.equal(second.ok, false);
  assert.match(second.why, /fell below/);
});

test('the gate stops after the wait bound when the state never rises', async () => {
  let t = 0;
  const gate = makeGate({ target: 'Serious', pin: pinOf(), sense: senseSeq(ok('Nominal')), sleep: async () => { t += 5000; }, now: () => t });
  const g = await gate();
  assert.equal(g.ok, false);
  assert.match(g.why, /did not reach the target in time/);
  assert.ok(t >= 180000);
});

test('the control server takes a command only with the token and runs commands one at a time', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'feel-test-'));
  try {
    const st = freshState({ seed: 0, pin: 'Serious', site: 'x' });
    const order = [];
    const handlers = {
      next: async () => { order.push('next-start'); const r = await cmdNext(st, { gate: async () => ({ ok: true }), open: async () => { await new Promise((r2) => setTimeout(r2, 30)); return { ok: true, info: {} }; }, now: Date.now }); order.push('next-end'); return r; },
      rate: ({ label, rating }) => { order.push('rate'); return cmdRate(st, label, rating); },
      status: ({ reveal }) => cmdStatus(st, { reveal }),
    };
    const control = await startControl({ token: 't0k', handlers });
    st.pid = process.pid;
    st.control = { port: control.port, token: 't0k' };
    saveFeel(dir, st);
    const a = callControl(dir, 'next');
    const b = callControl(dir, 'rate', { label: 'A', rating: 4 });
    const [ra, rb] = await Promise.all([a, b]);
    assert.equal(ra.ok, true);
    assert.equal(rb.ok, true);
    assert.deepEqual(order, ['next-start', 'next-end', 'rate']);
    const bad = await fetch(`http://127.0.0.1:${control.port}/status`, { method: 'POST', headers: { 'x-feel-token': 'wrong' }, body: '{}' });
    assert.equal(bad.status, 403);
    const get = await fetch(`http://127.0.0.1:${control.port}/status`);
    assert.equal(get.status, 403);
    assert.match((await callControl(dir, 'status')).text, /A=4/);
    await control.close();
    st.pid = 2 ** 22 + 12345;
    saveFeel(dir, st);
    await assert.rejects(() => callControl(dir, 'status'), /no feel session is running/);
    assert.equal(loadFeel(dir).ratings[0], 4);
    const g = await waitGone(dir, { maxS: 1, sleep: async () => {} });
    assert.equal(g.gone, true);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('a stop that closes the control server still gets its reply', async () => {
  let control;
  let closed;
  const handlers = { stop: () => { closed = Promise.resolve().then(() => control.close()); return { ok: true, text: 'stopping' }; } };
  control = await startControl({ token: 't0k', handlers });
  const r = await fetch(`http://127.0.0.1:${control.port}/stop`, { method: 'POST', headers: { 'x-feel-token': 't0k' }, body: '{}' });
  assert.equal((await r.json()).text, 'stopping');
  await closed;
});
