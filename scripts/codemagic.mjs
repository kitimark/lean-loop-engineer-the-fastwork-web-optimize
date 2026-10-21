#!/usr/bin/env node
// codemagic (task codemagic-pilot): the glue between this repo and the Codemagic pilot (codemagic.yaml; docs/team/tools/codemagic.md).
// The one decision that costs something, whether a build may start, is the Lean module lean/Fw/Ci/Codemagic.lean, replayed from its
// golden packages/contracts/golden/ci/codemagic.jsonl (scripts/codemagic.test.mjs replays every row through the functions below:
// billedMin, monthOf, refusals/mayTrigger, exitOf). This file is request building, parsing, polling, file writing and printing.
//
//   fw ci codemagic check                          read-only: the token works and the app id is one of the account's apps (GET /apps)
//   fw ci codemagic trigger --branch ci/<name> [--workflow webkit-sim] [--cap MIN] [--dry]
//   fw ci codemagic wait --build ID [--timeout S] [--interval S>=120] [--out DIR]
//   fw ci codemagic fetch --build ID --out DIR     build.json, steps.json, artifacts/, ledger row with the minutes the build billed
//   fw ci codemagic compare --github DIR --codemagic DIR [--json]   (each DIR holds v1-session-1.md, the class table)
//   fw ci codemagic ledger | digest FILE.md | dry-run
//
// The token is read from the macOS Keychain (service fw-codemagic-token) inside each request: never printed, never in an argument
// list, never in a file, sent only to api.codemagic.io (a redirect to another host is followed without it). Exit codes of wait (Lean
// `exitOf`): 0 finished, 1 failed or timeout, 3 the wait ran out, 4 canceled or skipped; trigger: 5 the Lean minutes rule refused; 64 usage.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const ROOT = resolve(here, '..');
export const GOLDEN = join(ROOT, 'packages', 'contracts', 'golden', 'ci', 'codemagic.jsonl');
export const API = 'https://api.codemagic.io';
export const API_HOST = 'api.codemagic.io';
export const KEYCHAIN_SERVICE = 'fw-codemagic-token';
export const MIN_POLL_S = 120;
export const WORKFLOW = 'webkit-sim';

export class Usage extends Error {}

// ---------------------------------------------------------------------------------------------------------------- golden

/** The golden rows by kind: { constants, billed: [...], month: [...], trigger: [...], status: [...] }. */
export function loadGolden(path = GOLDEN) {
  const by = {};
  for (const l of readFileSync(path, 'utf8').split('\n').filter(Boolean)) { const r = JSON.parse(l); (by[r.kind] ??= []).push(r); }
  return { ...by, constants: by.constants[0] };
}

// --------------------------------------------------------------------- the Lean decisions (checked against the golden rows)

/** Lean `billedMin`: whole minutes rounded up, at least one. */
export const billedMin = (durMs) => Math.max(1, Math.floor((durMs + 59999) / 60000));

/** The `YYYY-MM` (UTC) of a Unix time in ms. Lean `monthOf` made the golden vectors; this is the Date reading of the same thing. */
export const monthOf = (ms) => new Date(ms).toISOString().slice(0, 7);

/** Lean `usedIn`: minutes the rows of `month` used. */
export const usedIn = (month, rows) => rows.reduce((n, r) => n + (r.month === month ? r.minutes : 0), 0);

/** Lean `refusals`: every reason to refuse, in the order minutes, builds, cap. */
export function refusals(c, month, rows, cap) {
  return [...(c.stopAt < usedIn(month, rows) + cap ? ['minutes'] : []), ...(c.maxBuilds <= rows.length ? ['builds'] : []), ...(c.maxCapMin < cap ? ['cap'] : [])];
}
export const mayTrigger = (c, month, rows, cap) => refusals(c, month, rows, cap).length === 0;

/** Lean `exitOf`: the wait's exit code at a build status, or null while the build goes on. */
export function exitOf(status) {
  if (status === 'finished') return 0;
  if (status === 'failed' || status === 'timeout') return 1;
  if (status === 'canceled' || status === 'skipped') return 4;
  return null;
}

// ------------------------------------------------------------------------------------------------------------------ HTTP

/** Read the token from the Keychain; the argument list holds the service name only. Throws a hint, never the token. */
export function keychainToken() {
  try {
    const t = execFileSync('security', ['find-generic-password', '-s', KEYCHAIN_SERVICE, '-w'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    if (t) return t;
  } catch { /* fall through */ }
  throw new Usage(`token missing: no Codemagic token in the Keychain (service ${KEYCHAIN_SERVICE}); see docs/team/tools/codemagic.md, step 3`);
}

export const redact = (text, token) => (token ? String(text).split(token).join('<redacted>') : String(text));
const isApi = (url) => new URL(url).hostname === API_HOST;
const shown = (url) => { const u = new URL(url); return `${u.host}${u.pathname}`; };

/** The one request path of every call: the token goes to api.codemagic.io only (a redirect is followed by hand, and without the token
 *  when it leaves that host: fetch would forward a custom header); a 429 waits Retry-After seconds, at most `retries` times; an
 *  error message holds neither the token nor a query. */
export async function request({ fetchFn = fetch, getToken = keychainToken, sleep = (s) => new Promise((r) => setTimeout(r, s * 1000)), retries = 3 }, method, url, { body, accept = 'application/json' } = {}) {
  for (let attempt = 0, hops = 0; ;) {
    const token = isApi(url) ? getToken() : '';
    const res = await fetchFn(url, { method, redirect: 'manual', headers: { ...(token ? { 'x-auth-token': token } : {}), Accept: accept, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
    if (res.status === 429 && attempt < retries) {
      attempt++;
      const raw = res.headers?.get?.('retry-after');
      const ra = raw == null || raw === '' ? NaN : Number(raw);
      await sleep(Math.max(Number.isFinite(ra) ? ra : 60, 1));
      continue;
    }
    if (res.status >= 300 && res.status < 400 && res.headers?.get?.('location')) {
      if (++hops > 5) throw new Error(`${method} ${shown(url)}: too many redirects`);
      url = new URL(res.headers.get('location'), url).href;
      if (new URL(url).protocol !== 'https:') throw new Error(`${method} ${shown(url)}: redirect to a non-https URL refused`);
      continue;
    }
    if (!res.ok) throw new Error(redact(`${method} ${shown(url)}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`, token));
    return res;
  }
}

export async function call(ctx, method, url, body) {
  const text = await (await request(ctx, method, url, { body })).text();
  return text ? JSON.parse(text) : {};
}

// -------------------------------------------------------------------------------------------------------------- requests

export function loadConfig(root = ROOT, env = process.env) {
  let f = {};
  try { f = JSON.parse(readFileSync(join(root, '.local', 'codemagic.json'), 'utf8')); } catch { /* none */ }
  return { appId: env.FW_CODEMAGIC_APP_ID || f.appId || '' };
}

/** POST /builds for a branch; the token is left out. */
export const triggerRequest = ({ appId, workflowId = WORKFLOW, branch }) => ({ method: 'POST', url: `${API}/builds`,
  headers: { 'x-auth-token': '<redacted>', Accept: 'application/json', 'Content-Type': 'application/json' }, body: { appId, workflowId, branch } });

export const urls = { build: (id) => `${API}/builds/${encodeURIComponent(id)}`, apps: `${API}/apps` };

// --------------------------------------------------------------------------------------------------------------- ledger

const emptyLedger = () => ({ builds: {} });
export function readLedger(path) {
  try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return emptyLedger(); }
}
export function writeLedger(path, ledger) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(ledger, null, 2)}\n`);
}
/** The Lean `Row`s of a ledger file. A build not yet fetched is a pending row at its cap, so it counts in full. */
export const ledgerRows = (ledger) => Object.entries(ledger.builds ?? {}).map(([id, b]) => ({ id, month: b.month, minutes: b.minutes }));

// --------------------------------------------------------------------------------------------------------- build reading

const pick = (o, ...keys) => { for (const k of keys) if (o?.[k] !== undefined && o[k] !== null) return o[k]; return undefined; };
const ms = (iso) => { const t = Date.parse(iso ?? ''); return Number.isFinite(t) ? t : null; };

/** One build from either API shape (`{build: {...}}` camelCase, or the v3 object in snake_case). */
export function normBuild(res) {
  const b = res?.build ?? res ?? {};
  const actions = pick(b, 'buildActions', 'actions') ?? [];
  const arts = pick(b, 'artefacts', 'artifacts') ?? [];
  return { id: String(pick(b, '_id', 'id') ?? ''), status: String(b.status ?? ''), index: pick(b, 'index'), instanceType: pick(b, 'instanceType', 'instance_type'),
    createdAt: ms(pick(b, 'createdAt', 'created_at')), startedAt: ms(pick(b, 'startedAt', 'started_at')), finishedAt: ms(pick(b, 'finishedAt', 'finished_at')),
    reportedMinutes: pick(b, 'buildMinutes', 'build_minutes'),
    steps: actions.map((a) => { const s = ms(pick(a, 'startedAt', 'started_at')), e = ms(pick(a, 'finishedAt', 'finished_at')); return { name: String(a.name ?? ''), status: a.status ?? null, durMs: s != null && e != null ? Math.max(0, e - s) : null, logUrl: pick(a, 'logUrl', 'log_url') ?? null }; }),
    artifacts: arts.map((a) => ({ name: String(a.name ?? ''), url: pick(a, 'url', 'short_lived_download_url') ?? null, bytes: pick(a, 'size', 'size_in_bytes') ?? null })) };
}

/** Minutes a finished build billed: Lean `billedMin` of its start-to-finish time (creation when it has no start), or the API's own figure when larger. */
export function buildMinutes(b) {
  const from = b.startedAt ?? b.createdAt;
  if (from == null || b.finishedAt == null) return null;
  const mine = billedMin(Math.max(0, b.finishedAt - from));
  return Number.isFinite(Number(b.reportedMinutes)) ? Math.max(mine, Math.ceil(Number(b.reportedMinutes))) : mine;
}

/** Poll until the Lean `exitOf` has an answer or `timeoutS` passes (exit 3). Never polls faster than MIN_POLL_S. */
export async function waitBuild(ctx, { buildId, timeoutS = 3600, intervalS = MIN_POLL_S }) {
  let waited = 0;
  for (;;) {
    const b = normBuild(await call(ctx, 'GET', urls.build(buildId)));
    const code = exitOf(b.status);
    ctx.log?.(`codemagic: build ${buildId} ${b.status} (waited ${waited} s)`);
    if (code !== null) return { code, build: b };
    if (waited >= timeoutS) return { code: 3, build: b };
    await ctx.sleep(intervalS);
    waited += intervalS;
  }
}

const safeName = (n) => n.replace(/[^A-Za-z0-9._-]+/g, '_').slice(0, 80) || 'file';

/** Write build.json (normalised, no commit or author fields), steps.json, the artifacts and the step logs the API names; record the ledger row. */
export async function fetchBuild(ctx, { buildId, out }) {
  const b = normBuild(await call(ctx, 'GET', urls.build(buildId)));
  mkdirSync(join(out, 'artifacts'), { recursive: true });
  const minutes = buildMinutes(b);
  const doc = { schema: 'fw.codemagic-build/1', buildId, status: b.status, index: b.index ?? null, instanceType: b.instanceType ?? null,
    startedAt: b.startedAt, finishedAt: b.finishedAt, createdAt: b.createdAt, minutes, steps: b.steps.map(({ name, status, durMs }) => ({ name, status, durMs })), artifacts: b.artifacts.map(({ name, bytes }) => ({ name, bytes })) };
  writeFileSync(join(out, 'build.json'), `${JSON.stringify(doc, null, 2)}\n`);
  for (const a of b.artifacts) {
    if (!a.url) continue;
    try { writeFileSync(join(out, 'artifacts', safeName(a.name)), Buffer.from(await (await request(ctx, 'GET', new URL(a.url, API).href, { accept: '*/*' })).arrayBuffer())); } catch (e) { ctx.log?.(`codemagic: artifact ${a.name}: ${e.message}`); }
  }
  mkdirSync(join(out, 'logs'), { recursive: true });
  for (const [i, s] of b.steps.entries()) {
    if (!s.logUrl) continue;
    try { writeFileSync(join(out, 'logs', `${String(i).padStart(2, '0')}-${safeName(s.name)}.txt`), Buffer.from(await (await request(ctx, 'GET', new URL(s.logUrl, API).href, { accept: '*/*' })).arrayBuffer())); } catch (e) { ctx.log?.(`codemagic: log ${s.name}: ${e.message}`); }
  }
  if (ctx.ledgerPath && minutes != null && exitOf(b.status) !== null) {
    const ledger = readLedger(ctx.ledgerPath);
    const at = b.startedAt ?? b.createdAt ?? ctx.now();
    ledger.builds[buildId] = { month: monthOf(at), minutes, pending: false, status: b.status, at };
    writeLedger(ctx.ledgerPath, ledger);
  }
  return doc;
}

// ------------------------------------------------------------------------------------------------------------- the class tables

/** The class rows of a determinism table (`v1-session-1.md`): { 'family|count type|level': class }. */
export function classRows(md) {
  const rows = {};
  for (const line of md.split('\n')) {
    const c = line.split('|').map((x) => x.trim());
    if (c.length < 8 || c[1] === 'family' || /^-+$/.test(c[1])) continue;
    rows[`${c[1]}|${c[2]}|${c[3]}`] = c[4].replaceAll('*', '');
  }
  return rows;
}

/** Row counts per class, and a digest over the sorted `key=class` lines. */
export function classDigest(md) {
  const rows = classRows(md), counts = {};
  for (const v of Object.values(rows)) counts[v] = (counts[v] ?? 0) + 1;
  const digest = Object.keys(rows).length ? createHash('sha256').update(`${Object.entries(rows).map(([k, v]) => `${k}=${v}`).sort().join('\n')}\n`).digest('hex') : null;
  return { rows: Object.keys(rows).length, counts, digest };
}

/** Compare two tables: rows both have with another class are `differ`; rows only one has are `only`. */
export function compareTables(ghMd, cmMd) {
  const a = classRows(ghMd), b = classRows(cmMd);
  const differ = Object.keys(a).filter((k) => k in b && a[k] !== b[k]).map((k) => ({ key: k, github: a[k], codemagic: b[k] }));
  const onlyGithub = Object.keys(a).filter((k) => !(k in b)), onlyCodemagic = Object.keys(b).filter((k) => !(k in a));
  return { github: classDigest(ghMd), codemagic: classDigest(cmMd), differ, onlyGithub, onlyCodemagic,
    comparable: Object.keys(a).length > 0 && Object.keys(b).length > 0, equal: differ.length === 0 && onlyGithub.length === 0 && onlyCodemagic.length === 0 };
}

// ------------------------------------------------------------------------------------------------------------------- CLI

function flags(argv, spec) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i], k = f.replace(/^--/, '');
    if (!f.startsWith('--') || !(k in spec)) throw new Usage(`unexpected argument ${f}`);
    if (spec[k] === 'bool') o[k] = true;
    else { const v = argv[++i]; if (v === undefined || v.startsWith('--')) throw new Usage(`flag ${f} needs a value`); o[k] = v; }
  }
  return o;
}

const USAGE = [
  'usage: fw ci codemagic <sub> ...',
  '  check                                            the token works and the app id is one of the apps (needs FW_CODEMAGIC_APP_ID or .local/codemagic.json)',
  '  trigger --branch ci/<name> [--workflow webkit-sim] [--cap MIN (default 40)] [--dry]',
  '  wait --build ID [--timeout S] [--interval S>=120] [--out DIR]     fetch --build ID --out DIR',
  '  compare --github DIR --codemagic DIR [--json]    ledger    digest FILE.md    dry-run',
].join('\n');

/** The trigger decision for now: the ledger, the month, the Lean refusals. */
export function triggerDecision(g, ledgerPath, cap, now) {
  const month = monthOf(now), rows = ledgerRows(readLedger(ledgerPath));
  return { month, used: usedIn(month, rows), builds: rows.length, cap, refusals: refusals(g.constants, month, rows, cap) };
}

export async function main(argv, { root = ROOT, env = process.env, ctx: ctx0 = {}, log = console.log } = {}) {
  const [sub, ...rest] = argv[0] === 'codemagic' ? argv.slice(1) : argv;
  try {
    const g = ctx0.golden ?? loadGolden();
    const ctx = { fetchFn: fetch, getToken: keychainToken, sleep: (s) => new Promise((r) => setTimeout(r, s * 1000)), now: () => Date.now(), log, ledgerPath: join(root, '.local', 'codemagic-ledger.json'), ...ctx0 };
    const cfg = loadConfig(root, env);
    const needApp = () => { if (!cfg.appId) throw new Usage('app id not set: FW_CODEMAGIC_APP_ID or .local/codemagic.json {"appId": ...}'); return cfg.appId; };
    if (sub === 'digest') { if (!rest[0]) throw new Usage('digest needs a file'); log(JSON.stringify(classDigest(readFileSync(rest[0], 'utf8')))); return 0; }
    if (sub === 'ledger') {
      const rows = ledgerRows(readLedger(ctx.ledgerPath)), month = monthOf(ctx.now());
      log(`codemagic: ${rows.length} pilot build(s) in the ledger, ${usedIn(month, rows)} of ${g.constants.freeMinutes} free minutes used in ${month} (stop line ${g.constants.stopAt})`);
      return 0;
    }
    if (sub === 'compare') {
      const o = flags(rest, { github: 'v', codemagic: 'v', json: 'bool' });
      if (!o.github || !o.codemagic) throw new Usage(USAGE);
      const r = compareTables(readFileSync(join(o.github, 'v1-session-1.md'), 'utf8'), readFileSync(join(o.codemagic, 'v1-session-1.md'), 'utf8'));
      if (o.json) log(JSON.stringify(r));
      else {
        log(`github:    ${r.github.rows} rows ${JSON.stringify(r.github.counts)}\ncodemagic: ${r.codemagic.rows} rows ${JSON.stringify(r.codemagic.counts)}`);
        log(`rows with another class: ${r.differ.length}; only on GitHub: ${r.onlyGithub.length}; only on Codemagic: ${r.onlyCodemagic.length}`);
        for (const d of r.differ.slice(0, 40)) log(`  ${d.key}: ${d.github} -> ${d.codemagic}`);
      }
      return !r.comparable ? 2 : r.equal ? 0 : 1;
    }
    if (sub === 'dry-run' || (sub === 'trigger' && rest.includes('--dry'))) {
      const o = flags(rest.filter((x) => x !== 'dry-run'), { branch: 'v', workflow: 'v', cap: 'v', dry: 'bool' });
      const cap = Number(o.cap ?? g.constants.maxCapMin), branch = o.branch ?? 'ci/codemagic-pilot';
      const req = triggerRequest({ appId: cfg.appId || '<app-id>', workflowId: o.workflow ?? WORKFLOW, branch });
      const d = triggerDecision(g, ctx.ledgerPath, cap, ctx.now());
      log(`${req.method} ${req.url}\n${JSON.stringify({ headers: req.headers, body: { ...req.body, appId: req.body.appId === cfg.appId && cfg.appId ? '<app-id>' : req.body.appId } }, null, 2)}`);
      log(`ledger (Lean Fw.Ci.Codemagic.refusals): month ${d.month}, ${d.used} of ${g.constants.freeMinutes} minutes used, ${d.builds} pilot build(s), cap ${d.cap} -> ${d.refusals.length ? `REFUSED (${d.refusals.join(', ')})` : 'allowed'}`);
      return 0;
    }
    if (sub === 'check') {
      const apps = await call(ctx, 'GET', urls.apps);
      const list = apps.applications ?? apps.items ?? apps;
      const ids = (Array.isArray(list) ? list : []).map((a) => String(a._id ?? a.id ?? ''));
      const ok = ids.includes(needApp());
      log(`codemagic: token accepted; ${ids.length} app(s); the configured app id is ${ok ? 'one of them' : 'NOT among them'}`);
      return ok ? 0 : 1;
    }
    if (sub === 'trigger') {
      const o = flags(rest, { branch: 'v', workflow: 'v', cap: 'v', dry: 'bool' });
      if (!/^ci\/[A-Za-z0-9._/-]+$/.test(o.branch ?? '')) throw new Usage(USAGE);
      const cap = Number(o.cap ?? g.constants.maxCapMin);
      if (!Number.isInteger(cap) || cap < 1) throw new Usage('--cap must be a whole number of minutes');
      const d = triggerDecision(g, ctx.ledgerPath, cap, ctx.now());
      if (d.refusals.length) { log(`STOP (Lean Fw.Ci.Codemagic.refusals): ${d.refusals.join(', ')}; ${d.used} of ${g.constants.freeMinutes} minutes used in ${d.month} (line ${g.constants.stopAt}), ${d.builds} pilot build(s) (max ${g.constants.maxBuilds}), cap ${cap}`); return 5; }
      const req = triggerRequest({ appId: needApp(), workflowId: o.workflow ?? WORKFLOW, branch: o.branch });
      const ledger = readLedger(ctx.ledgerPath), tmpId = `pending-${ctx.now()}`;
      ledger.builds[tmpId] = { month: d.month, minutes: cap, pending: true, at: ctx.now() }; // counts in full from before the request is sent
      writeLedger(ctx.ledgerPath, ledger);
      let r;
      try { r = await call(ctx, req.method, req.url, req.body); } catch (e) { delete ledger.builds[tmpId]; writeLedger(ctx.ledgerPath, ledger); throw e; }
      const id = r.buildId ?? r.build?._id ?? r.id;
      if (!id) throw new Error('trigger answered without a build id');
      delete ledger.builds[tmpId];
      ledger.builds[id] = { month: d.month, minutes: cap, pending: true, at: ctx.now() };
      writeLedger(ctx.ledgerPath, ledger);
      log(`codemagic: build ${id} for ${o.branch}; wait with: node scripts/codemagic.mjs wait --build ${id}`);
      return 0;
    }
    if (sub === 'wait' || sub === 'fetch') {
      const o = flags(rest, { build: 'v', timeout: 'v', interval: 'v', out: 'v' });
      if (!o.build) throw new Usage('give --build ID');
      if (sub === 'fetch') {
        if (!o.out) throw new Usage('fetch needs --out DIR');
        const doc = await fetchBuild(ctx, { buildId: o.build, out: resolve(o.out) });
        log(`codemagic: fetched build ${o.build} (${doc.status}, ${doc.minutes ?? 'unknown'} min billed, ${doc.steps.length} step(s), ${doc.artifacts.length} artifact(s)) to ${o.out}`);
        return 0;
      }
      const interval = Number(o.interval ?? MIN_POLL_S);
      if (!(interval >= MIN_POLL_S)) throw new Usage(`--interval must be at least ${MIN_POLL_S} s`);
      const w = await waitBuild(ctx, { buildId: o.build, timeoutS: Number(o.timeout ?? 3000), intervalS: interval });
      log(`codemagic: build ${o.build} ended with exit ${w.code} (0 finished, 1 failed or timeout, 3 wait timed out, 4 canceled or skipped), status ${w.build.status}`);
      if (o.out && w.code !== 3) await fetchBuild(ctx, { buildId: o.build, out: resolve(o.out) });
      return w.code;
    }
    throw new Usage(USAGE);
  } catch (e) {
    if (e instanceof Usage) { console.error(e.message); return 64; }
    console.error(`codemagic: ${e.message}`);
    return 1;
  }
}

export const SCRIPT = join('scripts', 'codemagic.mjs');
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = await main(process.argv.slice(2));
