import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { GOLDEN, LIMITS, LimitError, bound, call, cellOutcome, cellReady, cellsKept, cellsPass, closeBounded, errKind, retryNext, takeCell, waitCell, waitStep } from '../src/bounded.mjs';

const lines = readFileSync(GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (fn) => lines.filter((l) => l.fn === fn);

test('every verifyReady golden line is replayed by cellReady', () => {
  assert.ok(of('verifyReady').length >= 8);
  for (const l of of('verifyReady')) assert.equal(cellReady(l.in.want, l.in.base, l.in.flag), l.out, JSON.stringify(l.in));
});

test('every verifyWait golden line is replayed by waitStep', () => {
  assert.ok(of('verifyWait').length >= 5);
  for (const l of of('verifyWait')) assert.equal(waitStep(l.in.elapsed, l.in.limit, l.in.ready), l.out, JSON.stringify(l.in));
});

test('every verifyAttempts golden line is replayed by cellOutcome', () => {
  assert.ok(of('verifyAttempts').length >= 10);
  for (const l of of('verifyAttempts')) assert.equal(cellOutcome(l.in.max, l.in.attempts), l.out, JSON.stringify(l.in));
});

test('every verifyNext golden line is replayed by retryNext', () => {
  assert.ok(of('verifyNext').length >= 5);
  for (const l of of('verifyNext')) assert.equal(retryNext(l.in.n, l.in.max, l.in.attempt), l.out, JSON.stringify(l.in));
});

test('every verifyErr golden line is replayed by errKind, retryNext and cellOutcome', () => {
  assert.ok(of('verifyErr').length >= 5);
  for (const l of of('verifyErr')) {
    const kind = errKind(l.in.name);
    assert.equal(kind, l.out.kind, JSON.stringify(l.in));
    const attempt = kind === 'stall' ? 'fault' : 'fail';
    assert.equal(retryNext(1, LIMITS.attempts, attempt), l.out.next, JSON.stringify(l.in));
    assert.equal(cellOutcome(LIMITS.attempts, [attempt]), l.out.outcome, JSON.stringify(l.in));
  }
});

test('every verifyCells golden line is replayed by cellsKept and cellsPass', () => {
  assert.ok(of('verifyCells').length >= 5);
  for (const l of of('verifyCells')) {
    assert.equal(cellsKept(l.in.outcomes), l.out.kept, JSON.stringify(l.in));
    assert.equal(cellsPass(l.in.outcomes), l.out.pass, JSON.stringify(l.in));
  }
});

test('the limits come from the golden and are all named and positive', () => {
  assert.deepEqual(LIMITS, of('verifyLimits')[0].out);
  for (const k of ['attempts', 'callMs', 'closeMs', 'pollMs', 'readyMs', 'shotMs']) assert.ok(LIMITS[k] > 0, k);
  assert.ok(LIMITS.pollMs < LIMITS.readyMs && LIMITS.readyMs < LIMITS.callMs);
});

test('a fault is never a reading: the first reading decides, a failing one is not retried into a pass', () => {
  assert.equal(cellOutcome(2, ['fail', 'pass']), 'fail');
  assert.equal(cellOutcome(2, ['fault', 'fail']), 'fail');
  assert.equal(cellOutcome(2, ['fault', 'fault', 'pass']), 'exhausted');
  assert.equal(retryNext(1, 2, 'fail'), 'done');
});

test('bound rejects with a named LimitError when the work outlives its limit, and passes a fast result', async () => {
  assert.equal(await bound('fast', 200, async () => 7), 7);
  await assert.rejects(bound('slow thing', 20, () => new Promise(() => {})), (e) => e instanceof LimitError && e.limit === 'slow thing' && /slow thing: no answer in 20 ms/.test(e.message));
});

test('bound passes the work error through and swallows a late rejection', async () => {
  await assert.rejects(bound('boom', 200, async () => { throw new Error('x'); }), /x/);
  await assert.rejects(bound('late', 10, () => new Promise((_, rej) => setTimeout(() => rej(new Error('later')), 40))), LimitError);
  await new Promise((r) => setTimeout(r, 80));
});

test('closeBounded drops a close that hangs or throws', async () => {
  await closeBounded('x', null);
  await closeBounded('x', { close: async () => { throw new Error('gone'); } });
  let closed = false;
  await closeBounded('x', { close: async () => { closed = true; } });
  assert.equal(closed, true);
});

test('call runs page.evaluate with the function and argument', async () => {
  const page = { evaluate: async (fn, arg) => fn(arg) };
  assert.equal(await call('inc', page, (x) => x + 1, 4), 5);
});

test('takeCell retries a fault on a fresh start and reports pass', async () => {
  const seen = [];
  const dropped = [];
  const r = await takeCell('c', async (n) => { seen.push(n); if (n === 1) throw new LimitError('screenshot', 5); return { ok: true, value: 'v' }; }, { onFault: async (e, n) => dropped.push(n) });
  assert.equal(r.outcome, 'pass');
  assert.equal(r.value, 'v');
  assert.deepEqual(seen, [1, 2]);
  assert.deepEqual(dropped, [1]);
  assert.equal(r.faults.length, 1);
  assert.match(r.faults[0].error, /screenshot/);
});

test('takeCell does not retry a failing reading', async () => {
  let n = 0;
  const r = await takeCell('c', async () => { n++; return { ok: false, value: 'bad' }; });
  assert.equal(r.outcome, 'fail');
  assert.equal(n, 1);
});

test('takeCell rejects a defect after 1 attempt and calls onFault 0 times', async () => {
  let n = 0;
  let dropped = 0;
  await assert.rejects(
    takeCell('c', async () => { n++; throw new TypeError('x'); }, { onFault: async () => { dropped++; } }),
    (e) => e instanceof TypeError && e.message === 'x',
  );
  assert.equal(n, 1);
  assert.equal(dropped, 0);
});

test('takeCell retries Playwright TimeoutError as a stall', async () => {
  let n = 0;
  const r = await takeCell('c', async () => { n++; if (n === 1) { const e = new Error('Timeout 120000ms exceeded'); e.name = 'TimeoutError'; throw e; } return { ok: true, value: 1 }; });
  assert.equal(r.outcome, 'pass');
  assert.equal(r.faults.length, 1);
});

test('takeCell is exhausted after the attempt limit of faults', async () => {
  let n = 0;
  const r = await takeCell('c', async () => { n++; throw new LimitError('screenshot', 5); });
  assert.equal(r.outcome, 'exhausted');
  assert.equal(n, LIMITS.attempts);
  assert.equal(r.faults.length, LIMITS.attempts);
});

test('waitCell reads once both pages are ready and says late when the limit runs out', async () => {
  const ok = { cols: 3, imgs: 2, loaded: 2, running: 0 };
  const mk = (obs) => ({ evaluate: async () => obs() });
  let k = 0;
  const flag = mk(() => (k++ < 2 ? { cols: 0, imgs: 0, loaded: 0, running: 0 } : ok));
  const r = await waitCell(mk(() => ok), flag, 3, { limitMs: 2000, pollMs: 5 });
  assert.equal(r.step, 'read');
  const never = await waitCell(mk(() => ok), mk(() => ({ ...ok, cols: 0 })), 3, { limitMs: 30, pollMs: 5 });
  assert.equal(never.step, 'late');
});
