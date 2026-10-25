import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, chmodSync, rmSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { socketsWithin, CALL_CAP_MS, CALL_GRACE_MS, callBoundMs, callSettleMs, pendingCalls, runAsync, simctlAsync, simctlRetryAsync, retryAsync, phoneIdsAsync, SYNC_CAP_MS } from '../src/sim.mjs';
import { stalled, lagMs, tickBlocked } from '../src/watchdog.mjs';
import { withRetry } from '../src/simretry.mjs';
import { passFile, writePassFile, askOnce } from '../src/session.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const goldenPath = join(HERE, '../../contracts/golden/ci/telemetry.jsonl');
const fwcore = join(HERE, '../../../lean/.lake/build/bin/fwcore');
const host = readFileSync(goldenPath, 'utf8').trim().split('\n').map((l) => JSON.parse(l)).filter((g) => g.request.what !== undefined);

const standIn = (rq) => {
  if (rq.what === 'bound') return { boundMs: callBoundMs(rq.limitMs), settleMs: callSettleMs(rq.limitMs) };
  if (rq.what === 'stall') return { stalled: stalled(rq.nowMs, rq.lastMs, rq.limitMs) };
  if (rq.what === 'lag') return { lagMs: lagMs(rq.tickMs, rq.sinceMs), blocked: tickBlocked(rq.tickMs, rq.sinceMs) };
  return { error: `unknown what ${rq.what}` };
};

test('the golden has host-call cases for bound, stall and lag', () => {
  assert.ok(host.length >= 12);
  assert.deepEqual([...new Set(host.map((g) => g.request.what))].sort(), ['bound', 'lag', 'nope', 'stall']);
});

test('the TS stand-ins of the Lean call bound, stall rule and tick lag give the Lean reply on every golden case', () => {
  for (const g of host) {
    if (g.request.what === 'nope') { assert.match(g.response.error, /unknown what/); continue; }
    assert.deepEqual(standIn(g.request), g.response, g.name);
  }
});

test('the Lean binary gives the golden reply (when built)', { skip: !existsSync(fwcore) }, () => {
  for (const g of host) {
    const r = spawnSync(fwcore, [], { input: JSON.stringify({ id: 1, ...g.request }) + '\n', encoding: 'utf8' });
    const reply = JSON.parse(r.stdout.trim().split('\n')[0]);
    const { id, ...rest } = reply;
    assert.deepEqual(rest, g.response, g.name);
  }
});

test('the constants are the Lean ones: cap 200 s, grace 5 s, the old sync cap', () => {
  assert.equal(CALL_CAP_MS, 200000);
  assert.equal(CALL_GRACE_MS, 5000);
  assert.equal(SYNC_CAP_MS, CALL_CAP_MS);
});

const fake = (() => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-hostcall-'));
  const script = (name, body) => { const f = join(dir, name); writeFileSync(f, `#!/bin/sh\n${body}\n`); chmodSync(f, 0o755); return f; };
  return { dir, script };
})();
after(() => rmSync(fake.dir, { recursive: true, force: true }));

const withPath = async (f) => {
  const old = process.env.PATH;
  process.env.PATH = `${fake.dir}:${old}`;
  try { return await f(); } finally { process.env.PATH = old; }
};

test('runAsync: a call that hangs ends at its bound with ETIMEDOUT while the event loop keeps ticking', async () => {
  const hang = fake.script('hang', 'exec sleep 30');
  let ticks = 0;
  const t = setInterval(() => { ticks++; }, 20);
  const t0 = Date.now();
  const r = await runAsync(hang, [], { timeoutMs: 300, graceMs: 200 });
  clearInterval(t);
  const took = Date.now() - t0;
  assert.equal(r.status, null);
  assert.equal(r.error.code, 'ETIMEDOUT');
  assert.ok(took >= 290 && took < 300 + 200 + 400, `took ${took} ms`);
  assert.ok(ticks >= 8, `the loop ticked ${ticks} times during a 300 ms hang`);
  assert.deepEqual(pendingCalls(), []);
});

test('runAsync: the bound is the Lean bound (a limit above the cap is cut), and the call is listed while it runs', async () => {
  const nap = fake.script('nap', 'exec sleep 1');
  const p = runAsync(nap, [], { timeoutMs: 900000, what: 'simctl nap' });
  const [c] = pendingCalls();
  assert.equal(c.what, 'simctl nap');
  assert.equal(c.boundMs, 200000);
  assert.ok(c.ageMs >= 0 && c.ageMs < 500);
  const r = await p;
  assert.equal(r.status, 0);
  assert.deepEqual(pendingCalls(), []);
});

test('runAsync: stdout, stderr and the exit status come back; a missing binary is an error result, not a throw', async () => {
  const echo = fake.script('echo2', 'echo out; echo err >&2; exit 3');
  const r = await runAsync(echo, []);
  assert.deepEqual([r.status, r.stdout.trim(), r.stderr.trim(), r.error], [3, 'out', 'err', undefined]);
  const m = await runAsync(join(fake.dir, 'nope'), []);
  assert.equal(m.error.code, 'ENOENT');
  assert.equal(m.status, null);
});

test('runAsync: a grandchild that keeps the pipes open cannot hold the result past the bound and the grace', async () => {
  const done = join(fake.dir, 'grandchild-done');
  const sticky = fake.script('sticky', `(sleep 3; touch '${done}') &\nexec sleep 30`);
  const r = await runAsync(sticky, [], { timeoutMs: 200, graceMs: 100 });
  assert.equal(r.error.code, 'ETIMEDOUT');
  assert.equal(existsSync(done), false);
});

test('runAsync: output over the buffer is an error, as spawnSync gives', async () => {
  const flood = fake.script('flood', 'yes | head -c 5000');
  const r = await runAsync(flood, [], { maxBuffer: 100 });
  assert.equal(r.error?.code, 'ENOBUFS');
});

const golden = readFileSync(join(HERE, '../../contracts/golden/device/sim-relaunch.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const R = { answers: { status: 0, stdout: '', stderr: '' }, transient: { status: 1, stderr: 'ETIMEDOUT' }, permanent: { status: 1, stderr: 'boom' } };

test('retryAsync replays the Lean call machine like withRetry, and its waits are the Lean waits', async () => {
  for (const g of golden.filter((x) => x.kind === 'call')) {
    const run = async (retry) => {
      const left = [...g.events];
      let used = 0, out = null;
      const stop = Symbol('script ends');
      const delays = [];
      const call = () => { if (!left.length) throw stop; used++; return R[left.shift()]; };
      try { out = await retry(call, delays); } catch (e) { if (e !== stop) throw e; }
      return { used, ok: out !== null, delays, status: out?.status };
    };
    const sync = await run((call, delays) => withRetry(call, { max: 2, text: (r) => r.stderr, sleepSync: (ms) => delays.push(ms) }));
    const asyn = await run((call, delays) => retryAsync(async () => call(), { max: 2, text: (r) => r.stderr, pause: async (ms) => { delays.push(ms); } }));
    assert.deepEqual(asyn, sync, g.name);
  }
});

test('simctlRetryAsync: a transient timeout is asked again after the Lean wait, a permanent failure at once', async () => {
  const counter = join(fake.dir, 'count');
  writeFileSync(counter, '0');
  fake.script('xcrun', `n=$(cat "${counter}"); n=$((n+1)); echo $n > "${counter}"\nif [ "$n" -lt 2 ]; then echo "ETIMEDOUT" >&2; exit 1; fi\necho ok`);
  await withPath(async () => {
    const waits = [];
    const r = await simctlRetryAsync(['list'], { timeoutMs: 5000 }, { max: 2, pause: async (ms) => { waits.push(ms); } });
    assert.equal(r.status, 0);
    assert.deepEqual(waits, [2000]);
    fake.script('xcrun', 'echo boom >&2; exit 1');
    const w2 = [];
    const p = await simctlRetryAsync(['list'], { timeoutMs: 5000 }, { max: 2, pause: async (ms) => { w2.push(ms); } });
    assert.equal(p.status, 1);
    assert.deepEqual(w2, []);
  });
});

test('simctlAsync with a hanging xcrun ends at the bound and the loop runs meanwhile (the sync call blocked it)', async () => {
  fake.script('xcrun', 'exec sleep 30');
  await withPath(async () => {
    let ticks = 0;
    const t = setInterval(() => { ticks++; }, 20);
    const r = await simctlAsync(['bootstatus', 'U', '-b'], { timeoutMs: 250 });
    clearInterval(t);
    assert.equal(r.error.code, 'ETIMEDOUT');
    assert.ok(ticks >= 6, `ticks ${ticks}`);
  });
});

test('phoneIdsAsync: the same fail-closed reading as phoneIds, a timeout asked again, no idevice_id is no phone', async () => {
  const ok = 'A'.repeat(40);
  assert.deepEqual(await phoneIdsAsync({ exec: async () => ({ status: 0, stdout: `${ok}\n`, stderr: '' }) }), [ok]);
  assert.deepEqual(await phoneIdsAsync({ exec: async () => ({ status: null, stdout: '', stderr: '', error: Object.assign(new Error('x'), { code: 'ENOENT' }) }) }), []);
  let n = 0;
  const flaky = async () => (++n === 1 ? { status: null, stdout: '', stderr: '', error: Object.assign(new Error('t'), { code: 'ETIMEDOUT' }) } : { status: 0, stdout: '', stderr: '' });
  assert.deepEqual(await phoneIdsAsync({ exec: flaky }), []);
  assert.equal(n, 3);
  await assert.rejects(phoneIdsAsync({ exec: async () => ({ status: 0, stdout: 'not an id\n', stderr: '' }) }), /cannot name/);
  await assert.rejects(phoneIdsAsync({ exec: async () => ({ status: 1, stdout: '', stderr: '' }) }), /not starting the proxy/);
});

test('askOnce: an openurl still running is not sent again, a failure is logged, the next ask goes out after it ends', async () => {
  const lines = [];
  let sent = 0, release;
  const ask = askOnce(() => { sent++; return new Promise((_, rej) => { release = rej; }); }, (l) => lines.push(l));
  ask(); ask();
  assert.equal(sent, 1);
  release(new Error('boom'));
  await new Promise((r) => setTimeout(r, 10));
  assert.match(lines[0], /openurl failed: boom/);
  ask();
  assert.equal(sent, 2);
});

test('passFile and writePassFile: x.json becomes x.pass-N.part (never *.json), written whole, nothing without --out', () => {
  assert.equal(passFile('out/v1-session-2.json', 1), 'out/v1-session-2.pass-1.part');
  assert.equal(passFile('out/v1-session-2', 2), 'out/v1-session-2.pass-2.part');
  assert.equal(writePassFile(undefined, 1, 2, {}), null);
  const dir = join(fake.dir, 'passes');
  mkdirSync(dir);
  const f = writePassFile(join(dir, 'v1-session-1.json'), 1, 2, { census: [1, 2], scroll: { total: { Layout: 3 } } }, { now: () => 1760000000000 });
  assert.equal(f, join(dir, 'v1-session-1.pass-1.part'));
  const j = JSON.parse(readFileSync(f, 'utf8'));
  assert.deepEqual(j, { schema: 'fw.webkit.pass/1', pass: 1, of: 2, wroteAt: '2025-10-09T08:53:20.000Z', data: { census: [1, 2], scroll: { total: { Layout: 3 } } } });
  assert.equal(existsSync(`${f}.tmp`), false);
  assert.equal(/-session-.*\.json$/.test(f), false);
});

test('socketsWithin: a timed-out lsof is asked again inside the budget, then its error is thrown; other errors at once', async () => {
  let n = 0;
  const slowTwice = async () => { if (++n < 3) throw new Error('lsof: ETIMEDOUT'); return ['/s']; };
  assert.deepEqual(await socketsWithin(1000, { find: slowTwice }), ['/s']);
  assert.equal(n, 3);
  let clock = 0, m = 0;
  const never = async () => { m++; clock += 600; throw new Error('lsof: ETIMEDOUT'); };
  await assert.rejects(socketsWithin(1000, { find: never, now: () => clock }), /ETIMEDOUT/);
  assert.equal(m, 2);
  let k = 0;
  await assert.rejects(socketsWithin(1000, { find: async () => { k++; throw new Error('lsof: ENOENT'); } }), /ENOENT/);
  assert.equal(k, 1);
});

const WD = join(HERE, '../src/watchdog.mjs');
const runWd = (body) => spawnSync(process.execPath, ['--input-type=module', '-e', `import { watch } from ${JSON.stringify(WD)};\n${body}`], { encoding: 'utf8', timeout: 20000 });

test('watchdog: a blocked event loop is reported with the running host calls, and the report is not counted as output', () => {
  const r = runWd(`
    watch({ stallMs: 2000, tickMs: 500, graceMs: 100, kill: () => {}, exit: () => {}, pending: () => [{ what: 'simctl bootstatus', ageMs: 5000, boundMs: 120000 }] });
    setTimeout(() => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1200), 100);
    setTimeout(() => process.exit(0), 3300);
  `);
  assert.match(r.stderr, /warning: event loop blocked: the \d+ s tick came \d+ s late; host calls running: \["simctl bootstatus 5 s of 120 s"\]/);
  assert.match(r.stderr, /error: stalled: no output for \d+ s \(limit 2 s\).*host calls running: \["simctl bootstatus 5 s of 120 s"\]; event loop blocked 1 time\(s\), worst \d+ s/);
});

test('watchdog: a loop that keeps its tick says nothing about blocking', () => {
  const r = runWd(`
    watch({ stallMs: 60000, tickMs: 100, kill: () => {}, exit: () => {} });
    setTimeout(() => process.exit(0), 600);
  `);
  assert.equal(r.stderr.includes('event loop blocked'), false);
});
