import test from 'node:test';
import assert from 'node:assert/strict';
import { connect, targetStep } from '../src/wip.mjs';

const created = (targetId, isProvisional = false, type = 'page') => ({ method: 'Target.targetCreated', params: { targetInfo: { targetId, type, isProvisional } } });
const commit = (oldTargetId, newTargetId) => ({ method: 'Target.didCommitProvisionalTarget', params: { oldTargetId, newTargetId } });
const destroyed = (targetId) => ({ method: 'Target.targetDestroyed', params: { targetId } });
const fold = (msgs) => msgs.reduce((s, m) => targetStep(s.state, m), { state: { targets: {}, provisional: {} }, swapped: null });

test('a provisional page target is not the command target until it commits', () => {
  const r = fold([created('page-1'), created('page-2', true)]);
  assert.equal(r.state.targets.page, 'page-1');
  assert.deepEqual(r.state.provisional, { 'page-2': 'page' });
});

test('the commit swaps the page target and names the old one; the old one is then destroyed', () => {
  const r = fold([created('page-1'), created('page-2', true), commit('page-1', 'page-2')]);
  assert.deepEqual(r.swapped, { from: 'page-1', to: 'page-2' });
  assert.equal(r.state.targets.page, 'page-2');
  assert.deepEqual(r.state.provisional, {});
  const after = targetStep(r.state, destroyed('page-1'));
  assert.equal(after.state.targets.page, 'page-2');
  assert.equal(after.swapped, null);
});

test('a provisional target destroyed before it commits leaves the page target alone', () => {
  const r = fold([created('page-1'), created('page-2', true), destroyed('page-2')]);
  assert.equal(r.state.targets.page, 'page-1');
  assert.deepEqual(r.state.provisional, {});
});

test('targets of other types and non-provisional page targets behave as before', () => {
  const r = fold([created('page-1'), created('w-1', false, 'worker'), created('page-3')]);
  assert.deepEqual(r.state.targets, { page: 'page-3', worker: 'w-1' });
});

test('targetStep does not change the state it is given', () => {
  const s0 = { targets: { page: 'page-1' }, provisional: {} };
  targetStep(s0, created('page-2', true));
  targetStep(s0, commit('page-1', 'page-2'));
  assert.deepEqual(s0, { targets: { page: 'page-1' }, provisional: {} });
});

class FakeSocket {
  static last = null;
  constructor() {
    this.sent = []; this.listeners = {};
    FakeSocket.last = this;
    queueMicrotask(() => this.onopen?.());
  }
  addEventListener(ev, fn) { (this.listeners[ev] ??= []).push(fn); }
  send(s) { this.sent.push(JSON.parse(s)); }
  close() { for (const f of this.listeners.close ?? []) f({ code: 1000 }); }
  push(m) { this.onmessage({ data: JSON.stringify(m) }); }
  reply(id, result, targetId) { this.push({ method: 'Target.dispatchMessageFromTarget', params: { targetId, message: JSON.stringify({ id, result }) } }); }
}

test('a command sent to the old page when its navigation commits fails at once with a named error; later commands go to the new page', async () => {
  const saved = globalThis.WebSocket;
  globalThis.WebSocket = FakeSocket;
  try {
    const cp = connect('ws://x');
    await new Promise((r) => setTimeout(r, 5));
    FakeSocket.last.push(created('page-1'));
    const c = await cp;
    const ws = FakeSocket.last;
    const p = c.send('Runtime.evaluate', { expression: '1' }, { timeoutMs: 15000 });
    const out = JSON.parse(ws.sent.at(-1).params.message);
    assert.equal(ws.sent.at(-1).params.targetId, 'page-1');
    assert.equal(out.method, 'Runtime.evaluate');
    ws.push(created('page-2', true));
    ws.push(commit('page-1', 'page-2'));
    await assert.rejects(p, (e) => e.swapped === true && /replaced by a navigation commit/.test(e.message));
    assert.doesNotMatch((await p.catch((e) => e)).message, /timed out/);
    const q = c.send('Runtime.evaluate', { expression: '2' });
    assert.equal(ws.sent.at(-1).params.targetId, 'page-2');
    const id = JSON.parse(ws.sent.at(-1).params.message).id;
    ws.reply(id, { result: { value: 2 } }, 'page-2');
    assert.deepEqual(await q, { result: { value: 2 } });
    await c.close();
  } finally { globalThis.WebSocket = saved; }
});

test('between the old page being destroyed and the commit a command is refused by name, not left to time out', async () => {
  const saved = globalThis.WebSocket;
  globalThis.WebSocket = FakeSocket;
  try {
    const cp = connect('ws://x');
    await new Promise((r) => setTimeout(r, 5));
    FakeSocket.last.push(created('page-1'));
    const c = await cp;
    FakeSocket.last.push(destroyed('page-1'));
    await assert.rejects(c.send('Runtime.evaluate', { expression: '1' }), /no committed page target/);
    await c.close();
  } finally { globalThis.WebSocket = saved; }
});
