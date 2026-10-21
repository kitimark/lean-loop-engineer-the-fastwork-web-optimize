// scripts/codemagic.test.mjs: the Codemagic glue against the Lean golden (packages/contracts/golden/ci/codemagic.jsonl, Lean
// Fw.Ci.Codemagic) and a fake fetch. Run: node --test scripts/codemagic.test.mjs
// No network, no Keychain: the API is a fake and the token is a fake string.
import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { billedMin, buildMinutes, classDigest, classRows, compareTables, exitOf, fetchBuild, ledgerRows, loadConfig, loadGolden, main, mayTrigger, monthOf, normBuild,
  redact, refusals, request, triggerRequest, usedIn, waitBuild, MIN_POLL_S } from './codemagic.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const g = loadGolden();
const TOKEN = 'cm-fake-token-0123456789';
const APP = 'appid000000000000000000a';
const tmp = () => mkdtempSync(join(tmpdir(), 'cm-test-'));
const res = (status, body = {}, headers = {}) => ({ status, ok: status >= 200 && status < 300, headers: { get: (k) => headers[k.toLowerCase()] ?? null }, text: async () => (typeof body === 'string' ? body : JSON.stringify(body)),
  arrayBuffer: async () => new TextEncoder().encode(typeof body === 'string' ? body : JSON.stringify(body)).buffer });

test('the golden has the kinds the glue replays', () => {
  assert.deepEqual(Object.keys(g).sort(), ['billed', 'constants', 'month', 'status', 'trigger']);
  assert.deepEqual([g.constants.freeMinutes, g.constants.stopAt, g.constants.maxCapMin, g.constants.maxBuilds], [500, 400, 40, 3]);
});

test('billed minutes: every golden row (Lean billedMin)', () => {
  for (const r of g.billed) assert.equal(billedMin(r.durMs), r.minutes, String(r.durMs));
});

test('calendar month: every golden row (Lean monthOf)', () => {
  assert.ok(g.month.length >= 6);
  for (const r of g.month) assert.equal(monthOf(r.ms), r.month, String(r.ms));
});

test('trigger rule: every golden row (Lean usedIn, refusals, mayTrigger)', () => {
  assert.ok(g.trigger.length >= 9);
  for (const r of g.trigger) {
    assert.equal(usedIn(r.month, r.rows), r.used, r.name);
    assert.deepEqual(refusals(g.constants, r.month, r.rows, r.cap), r.refusals, r.name);
    assert.equal(mayTrigger(g.constants, r.month, r.rows, r.cap), r.mayTrigger, r.name);
  }
  // the theorem in words: used + cap over 400 never triggers, whatever the rows
  for (let used = 0; used <= 420; used += 7) for (const cap of [1, 20, 40]) {
    const rows = [{ id: 'x', month: '2026-10', minutes: used }];
    if (used + cap > 400) assert.equal(mayTrigger(g.constants, '2026-10', rows, cap), false, `${used}+${cap}`);
  }
});

test('wait exit codes: every golden status (Lean exitOf)', () => {
  assert.equal(g.status.length, 13);
  for (const r of g.status) assert.equal(exitOf(r.status), r.exit, r.status);
});

test('the token: only api.codemagic.io sees it; a redirect leaves without it; an error never holds it', async () => {
  const seen = [];
  const fetchFn = async (url, init) => {
    seen.push({ url, token: init.headers['x-auth-token'] ?? null, redirect: init.redirect });
    if (url.startsWith('https://api.codemagic.io/artifacts/')) return res(302, '', { location: 'https://storage.example.net/signed?sig=abc' });
    if (url.startsWith('https://storage.example.net/')) return res(200, 'bytes');
    return res(500, `boom ${TOKEN}`);
  };
  const ctx = { fetchFn, getToken: () => TOKEN, sleep: async () => {} };
  const r = await request(ctx, 'GET', 'https://api.codemagic.io/artifacts/a/b/file.md', { accept: '*/*' });
  assert.equal(await r.text(), 'bytes');
  assert.deepEqual(seen.map((s) => [new URL(s.url).host, s.token]), [['api.codemagic.io', TOKEN], ['storage.example.net', null]]);
  assert.ok(seen.every((s) => s.redirect === 'manual'));
  await assert.rejects(request(ctx, 'GET', 'https://api.codemagic.io/builds/1'), (e) => e.message.includes('HTTP 500') && !e.message.includes(TOKEN) && e.message.includes('<redacted>'));
  assert.equal(redact('a TOKEN b'.replace('TOKEN', TOKEN), TOKEN), 'a <redacted> b');
  await assert.rejects(request({ ...ctx, fetchFn: async () => res(302, '', { location: 'http://api.codemagic.io/x' }) }, 'GET', 'https://api.codemagic.io/builds/1'), /non-https/);
});

test('a 429 waits Retry-After and tries again, at most three times', async () => {
  let n = 0; const waits = [];
  const ctx = { fetchFn: async () => (++n < 3 ? res(429, '', { 'retry-after': '7' }) : res(200, { ok: 1 })), getToken: () => TOKEN, sleep: async (s) => waits.push(s) };
  assert.equal((await request(ctx, 'GET', 'https://api.codemagic.io/builds/1')).status, 200);
  assert.deepEqual(waits, [7, 7]);
  n = -10; waits.length = 0;
  await assert.rejects(request(ctx, 'GET', 'https://api.codemagic.io/builds/1'), /HTTP 429/);
  assert.equal(waits.length, 3);
});

test('a missing Keychain item stops the run with "token missing" (exit 64) before any request', () => {
  const bin = tmp(); writeFileSync(join(bin, 'security'), '#!/bin/sh\nexit 44\n', { mode: 0o755 });
  const r = spawnSync(process.execPath, [join(here, 'codemagic.mjs'), 'check'], { encoding: 'utf8', env: { PATH: `${bin}${delimiter}${dirname(process.execPath)}`, FW_CODEMAGIC_APP_ID: APP, HOME: tmp() } });
  assert.equal(r.status, 64);
  assert.match(r.stderr, /token missing/);
});

test('triggerRequest: POST /builds with appId, workflowId, branch; the token is left out', () => {
  const r = triggerRequest({ appId: APP, branch: 'ci/codemagic-pilot' });
  assert.equal(r.method, 'POST');
  assert.equal(r.url, 'https://api.codemagic.io/builds');
  assert.deepEqual(r.body, { appId: APP, workflowId: 'webkit-sim', branch: 'ci/codemagic-pilot' });
  assert.equal(r.headers['x-auth-token'], '<redacted>');
});

const finished = { build: { _id: 'b1', status: 'finished', index: 7, instanceType: 'mac_mini_m2', createdAt: '2026-10-21T10:00:00Z', startedAt: '2026-10-21T10:01:00Z', finishedAt: '2026-10-21T10:31:30Z',
  buildActions: [{ name: 'tool and runner facts', status: 'success', startedAt: '2026-10-21T10:01:10Z', finishedAt: '2026-10-21T10:01:20Z' }, { name: 'boot', status: 'success', startedAt: '2026-10-21T10:02:00Z', finishedAt: '2026-10-21T10:05:00Z', logUrl: 'https://api.codemagic.io/logs/1' }],
  artefacts: [{ name: 'v1-session-1.md', url: 'https://api.codemagic.io/artifacts/a/b/v1-session-1.md', size: 12 }] } };

test('normBuild reads the camelCase and the v3 snake_case shape; buildMinutes is Lean billedMin of the run', () => {
  const b = normBuild(finished);
  assert.deepEqual([b.id, b.status, b.steps.length, b.steps[1].durMs, b.artifacts[0].bytes], ['b1', 'finished', 2, 180000, 12]);
  assert.equal(buildMinutes(b), 31); // 30 min 30 s rounds up
  const v3 = normBuild({ id: 'b2', status: 'failed', created_at: '2026-10-21T10:00:00Z', started_at: '2026-10-21T10:00:30Z', finished_at: '2026-10-21T10:00:40Z', actions: [{ name: 's', status: 'failed', started_at: '2026-10-21T10:00:31Z', finished_at: '2026-10-21T10:00:33Z' }], artifacts: [{ name: 'f', short_lived_download_url: 'https://x.example/f', size_in_bytes: 3 }] });
  assert.deepEqual([v3.id, buildMinutes(v3), v3.steps[0].durMs, v3.artifacts[0].url], ['b2', 1, 2000, 'https://x.example/f']);
  assert.equal(buildMinutes(normBuild({ build: { status: 'building', startedAt: '2026-10-21T10:00:30Z' } })), null);
  assert.equal(buildMinutes({ ...b, reportedMinutes: 40 }), 40);
});

test('waitBuild polls at the given interval until Lean exitOf answers, and times out with 3', async () => {
  const statuses = ['queued', 'building', 'finishing', 'finished']; const waits = [];
  const ctx = { fetchFn: async () => res(200, { build: { _id: 'b', status: statuses.shift() } }), getToken: () => TOKEN, sleep: async (s) => waits.push(s) };
  const w = await waitBuild(ctx, { buildId: 'b', intervalS: MIN_POLL_S });
  assert.equal(w.code, 0);
  assert.deepEqual(waits, [120, 120, 120]);
  const slow = { ...ctx, fetchFn: async () => res(200, { build: { _id: 'b', status: 'building' } }) };
  assert.equal((await waitBuild(slow, { buildId: 'b', timeoutS: 240, intervalS: 120 })).code, 3);
  assert.equal((await waitBuild({ ...ctx, fetchFn: async () => res(200, { build: { status: 'failed' } }) }, { buildId: 'b' })).code, 1);
});

function fakeApi({ onPost } = {}) {
  const calls = [];
  const fetchFn = async (url, init) => {
    calls.push({ method: init.method, url, token: init.headers['x-auth-token'] ?? null, body: init.body });
    if (init.method === 'POST' && url.endsWith('/builds')) return onPost ? onPost() : res(200, { buildId: 'b1' });
    if (url.endsWith('/builds/b1')) return res(200, finished);
    if (url.endsWith('/artifacts/a/b/v1-session-1.md')) return res(200, '| family | count type | level | class | cells | differing | max spread |\n');
    if (url.endsWith('/logs/1')) return res(200, 'log text');
    if (url.endsWith('/apps')) return res(200, { applications: [{ _id: APP, appName: 'x' }] });
    return res(404, 'no');
  };
  return { calls, fetchFn };
}

test('trigger: the ledger is checked first, a pending row counts in full, fetch replaces it with the billed minutes', async () => {
  const root = tmp(); const ledgerPath = join(root, 'ledger.json'); const logs = [];
  const api = fakeApi();
  const base = { root, env: { FW_CODEMAGIC_APP_ID: APP }, log: (m) => logs.push(m), ctx: { fetchFn: api.fetchFn, getToken: () => TOKEN, ledgerPath, now: () => Date.parse('2026-10-21T10:00:00Z'), sleep: async () => {} } };
  assert.equal(await main(['trigger', '--branch', 'ci/codemagic-pilot'], base), 0);
  assert.deepEqual(api.calls.map((c) => [c.method, c.url, c.token]), [['POST', 'https://api.codemagic.io/builds', TOKEN]]);
  assert.deepEqual(JSON.parse(api.calls[0].body), { appId: APP, workflowId: 'webkit-sim', branch: 'ci/codemagic-pilot' });
  let rows = ledgerRows(JSON.parse(readFileSync(ledgerPath, 'utf8')));
  assert.deepEqual(rows, [{ id: 'b1', month: '2026-10', minutes: 40 }]);
  assert.ok(!readFileSync(ledgerPath, 'utf8').includes(TOKEN) && !logs.join('\n').includes(TOKEN));
  const out = join(root, 'out');
  assert.equal(await main(['fetch', '--build', 'b1', '--out', out], base), 0);
  rows = ledgerRows(JSON.parse(readFileSync(ledgerPath, 'utf8')));
  assert.deepEqual(rows, [{ id: 'b1', month: '2026-10', minutes: 31 }]);
  assert.ok(existsSync(join(out, 'artifacts', 'v1-session-1.md')) && existsSync(join(out, 'logs', '01-boot.txt')));
  const doc = JSON.parse(readFileSync(join(out, 'build.json'), 'utf8'));
  assert.deepEqual([doc.minutes, doc.steps[1].durMs, doc.status], [31, 180000, 'finished']);
  assert.ok(!JSON.stringify(doc).includes('commit'));
});

test('trigger refuses (exit 5, no request) at 361 + 40, at three builds and at cap 41', async () => {
  for (const [name, builds, cap, why] of [
    ['over the line', { a: { month: '2026-10', minutes: 180 }, b: { month: '2026-10', minutes: 181 } }, '40', 'minutes'],
    ['three builds', { a: { month: '2026-09', minutes: 5 }, b: { month: '2026-09', minutes: 5 }, c: { month: '2026-09', minutes: 5 } }, '40', 'builds'],
    ['cap', {}, '41', 'cap']]) {
    const root = tmp(); const ledgerPath = join(root, 'ledger.json'); writeFileSync(ledgerPath, JSON.stringify({ builds }));
    const api = fakeApi(); const logs = [];
    const code = await main(['trigger', '--branch', 'ci/codemagic-pilot', '--cap', cap], { root, env: { FW_CODEMAGIC_APP_ID: APP }, log: (m) => logs.push(m), ctx: { fetchFn: api.fetchFn, getToken: () => TOKEN, ledgerPath, now: () => Date.parse('2026-10-21T10:00:00Z') } });
    assert.equal(code, 5, name);
    assert.equal(api.calls.length, 0, name);
    assert.match(logs.join('\n'), new RegExp(`STOP.*${why}`), name);
  }
});

test('a trigger the API rejects leaves no row in the ledger', async () => {
  const root = tmp(); const ledgerPath = join(root, 'ledger.json'); const err = console.error; console.error = () => {};
  try {
    const api = fakeApi({ onPost: () => res(403, 'no') });
    const code = await main(['trigger', '--branch', 'ci/x'], { root, env: { FW_CODEMAGIC_APP_ID: APP }, log: () => {}, ctx: { fetchFn: api.fetchFn, getToken: () => TOKEN, ledgerPath, now: () => 1 } });
    assert.equal(code, 1);
    assert.deepEqual(ledgerRows(JSON.parse(readFileSync(ledgerPath, 'utf8'))), []);
  } finally { console.error = err; }
});

test('trigger --dry prints the request without the token or the app id and the Lean refusal, and sends nothing', async () => {
  const root = tmp(); const api = fakeApi(); const logs = [];
  assert.equal(await main(['trigger', '--dry', '--branch', 'ci/codemagic-pilot'], { root, env: { FW_CODEMAGIC_APP_ID: APP }, log: (m) => logs.push(m), ctx: { fetchFn: api.fetchFn, getToken: () => TOKEN, ledgerPath: join(root, 'l.json'), now: () => Date.parse('2026-10-21T10:00:00Z') } }), 0);
  const text = logs.join('\n');
  assert.equal(api.calls.length, 0);
  assert.ok(text.includes('<redacted>') && text.includes('allowed') && !text.includes(TOKEN) && !text.includes(APP));
});

test('check: the app id must be one of the account apps', async () => {
  const api = fakeApi(); const logs = [];
  const base = { root: tmp(), log: (m) => logs.push(m), ctx: { fetchFn: api.fetchFn, getToken: () => TOKEN } };
  assert.equal(await main(['check'], { ...base, env: { FW_CODEMAGIC_APP_ID: APP } }), 0);
  const err = console.error; console.error = () => {};
  try { assert.equal(await main(['check'], { ...base, env: {} }), 64); } finally { console.error = err; }
  assert.equal(await main(['check'], { ...base, env: { FW_CODEMAGIC_APP_ID: 'other' } }), 1);
});

test('loadConfig: env wins over .local/codemagic.json', () => {
  const root = tmp(); mkdirSync(join(root, '.local')); writeFileSync(join(root, '.local', 'codemagic.json'), JSON.stringify({ appId: 'fromfile' }));
  assert.equal(loadConfig(root, {}).appId, 'fromfile');
  assert.equal(loadConfig(root, { FW_CODEMAGIC_APP_ID: 'fromenv' }).appId, 'fromenv');
  assert.equal(loadConfig(tmp(), {}).appId, '');
});

const table = (rows) => `| family | count type | level | class | cells | differing | max spread |\n|---|---|---|---|---|---|---|\n${rows.map(([f, t, l, c]) => `| ${f} | ${t} | ${l} | **${c}** | 1 | 0 | 0 |`).join('\n')}\n`;

test('class tables: rows, counts, digest, and the rows that differ', () => {
  const a = table([['census', 'layerCount', 'y=0', 'quarantined'], ['census', 'layerCount', 'y=3000', 'deterministic'], ['scroll', 'style', 'per step', 'stable']]);
  const b = table([['census', 'layerCount', 'y=0', 'stable'], ['census', 'layerCount', 'y=3000', 'deterministic'], ['seek', 'x', 'n=10', 'stable']]);
  assert.deepEqual(classRows(a), { 'census|layerCount|y=0': 'quarantined', 'census|layerCount|y=3000': 'deterministic', 'scroll|style|per step': 'stable' });
  assert.deepEqual(classDigest(a).counts, { quarantined: 1, deterministic: 1, stable: 1 });
  assert.equal(classDigest(a).digest, classDigest(a).digest);
  assert.notEqual(classDigest(a).digest, classDigest(b).digest);
  const c = compareTables(a, b);
  assert.deepEqual(c.differ, [{ key: 'census|layerCount|y=0', github: 'quarantined', codemagic: 'stable' }]);
  assert.deepEqual([c.onlyGithub, c.onlyCodemagic, c.equal, c.comparable], [['scroll|style|per step'], ['seek|x|n=10'], false, true]);
  assert.equal(compareTables(a, a).equal, true);
  assert.equal(compareTables(a, '').comparable, false);
});

test('fetchBuild records no ledger row for a build that has not finished', async () => {
  const root = tmp(); const ledgerPath = join(root, 'l.json');
  const ctx = { fetchFn: async () => res(200, { build: { _id: 'b9', status: 'building', startedAt: '2026-10-21T10:00:00Z' } }), getToken: () => TOKEN, ledgerPath, now: () => 0, log: () => {} };
  await fetchBuild(ctx, { buildId: 'b9', out: join(root, 'o') });
  assert.equal(existsSync(ledgerPath), false);
});

test('codemagic.yaml: one workflow, the pilot cap, no triggering block, the pinned runtime, the same steps as the GitHub cell', () => {
  const y = readFileSync(new URL('../codemagic.yaml', import.meta.url), 'utf8');
  assert.match(y, /^workflows:\n {2}webkit-sim:\n/m);
  assert.equal((y.match(/^ {2}[a-z][a-z0-9-]*:$/gm) ?? []).length, 1);
  assert.match(y, /instance_type: mac_mini_m2/);
  assert.match(y, new RegExp(`max_build_duration: ${g.constants.maxCapMin}\\b`));
  assert.match(y, /xcode: 27\.0\b/);
  assert.doesNotMatch(y, /^\s*triggering:/m);
  const gh = readFileSync(new URL('../.github/workflows/webkit-sim.yml', import.meta.url), 'utf8');
  for (const v of ['FW_IOS_VERSION', 'FW_IOS_BUILD', 'FW_SIM_NAME', 'FW_WK_TIMEOUT_SCALE', 'FW_WK_ATTEMPTS']) {
    const pick = (s) => new RegExp(`${v}: ['"]?([^'"\\s]+)['"]?`).exec(s)?.[1];
    assert.equal(pick(y), pick(gh), v);
  }
  assert.match(y, /node src\/cli\.mjs determinism --runs 2 --keep --out out\/v1-session-1\.json/);
  assert.ok(!/x-auth-token|fw-codemagic-token/.test(y));
});
