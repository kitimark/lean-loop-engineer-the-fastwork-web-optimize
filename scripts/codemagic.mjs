#!/usr/bin/env node
//   node scripts/codemagic.mjs check                          read-only: the token works and the app id is one of the account's apps (GET /apps)
//   node scripts/codemagic.mjs trigger --branch ci/<name> [--workflow webkit-sim] [--pool] [--dry]   (cap = codemagic.yaml max_build_duration)
//   node scripts/codemagic.mjs wait --build ID [--timeout S] [--interval S>=120] [--out DIR]
//   node scripts/codemagic.mjs fetch --build ID --out DIR     build.json, steps.json, artifacts/, ledger row with the minutes the build billed
//   node scripts/codemagic.mjs compare --github DIR --codemagic DIR [--json]   (each DIR holds v1-session-1.md, the class table)
//   node scripts/codemagic.mjs site-digest DIR               sha256 over the files of a built site
//   node scripts/codemagic.mjs ledger | digest FILE.md | dry-run
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
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


export function loadGolden(path = GOLDEN) {
  const by = {};
  for (const l of readFileSync(path, 'utf8').split('\n').filter(Boolean)) { const r = JSON.parse(l); (by[r.kind] ??= []).push(r); }
  return { ...by, constants: by.constants[0] };
}


export const billedMin = (durMs) => Math.max(1, Math.floor((durMs + 59999) / 60000));

export const monthOf = (ms) => new Date(ms).toISOString().slice(0, 7);

export const usedIn = (month, rows) => rows.reduce((n, r) => n + (r.month === month ? r.minutes : 0), 0);

export function refusals(c, month, rows, cap) {
  return [...(c.stopAt < usedIn(month, rows) + cap ? ['minutes'] : []), ...(c.maxBuilds <= rows.length ? ['builds'] : []), ...(c.maxCapMin < cap ? ['cap'] : [])];
}
export const mayTrigger = (c, month, rows, cap) => refusals(c, month, rows, cap).length === 0;

export function poolRefusals(c, used, cap) {
  return [...(c.stopAt < used + cap ? ['minutes'] : []), ...(c.maxCapMin < cap ? ['cap'] : [])];
}
export const poolOk = (c, used, cap) => poolRefusals(c, used, cap).length === 0;

/** The state word `fw ci state cm:<id>` prints: `running` until the Lean exit map (`exitOf`) answers, then `complete` for a finished build and `failed` for any other end. I/O glue, no decision. */
export function stateWord(status) {
  const code = exitOf(status);
  return code === null ? 'running' : code === 0 ? 'complete' : 'failed';
}

export function exitOf(status) {
  if (status === 'finished') return 0;
  if (status === 'failed' || status === 'timeout') return 1;
  if (status === 'canceled' || status === 'skipped') return 4;
  return null;
}


export function keychainToken() {
  try {
    const t = execFileSync('security', ['find-generic-password', '-s', KEYCHAIN_SERVICE, '-w'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    if (t) return t;
  } catch {}
  throw new Usage(`token missing: no Codemagic token in the Keychain (service ${KEYCHAIN_SERVICE}); see docs/team/tools/codemagic.md, step 3`);
}

export const redact = (text, token) => (token ? String(text).split(token).join('<redacted>') : String(text));
const isApi = (url) => new URL(url).hostname === API_HOST;
const shown = (url) => { const u = new URL(url); return `${u.host}${u.pathname}`; };

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
    if (!res.ok) throw Object.assign(new Error(redact(`${method} ${shown(url)}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`, token)), { status: res.status });
    return res;
  }
}

export async function call(ctx, method, url, body) {
  const text = await (await request(ctx, method, url, { body })).text();
  return text ? JSON.parse(text) : {};
}


export function loadConfig(root = ROOT, env = process.env) {
  let f = {};
  try { f = JSON.parse(readFileSync(join(root, '.local', 'codemagic.json'), 'utf8')); } catch {}
  return { appId: env.FW_CODEMAGIC_APP_ID || f.appId || '' };
}

export const CELL_VARS = { FW_TARGET: /^(original|rewrite)$/, FW_PRESET: /^[A-Za-z0-9._-]{1,40}$/, FW_FW: /^[A-Za-z0-9._:,-]{0,200}$/, FW_VM: /^[vr][1-9][0-9]?$/, FW_SESSIONS: /^[1-9]$/, FW_SEARCH: /^[A-Za-z0-9._:,=&%?-]{0,300}$/ };

export const EMPTY = 'none';

export function cellVars(vars) {
  const out = {};
  for (const [k, v] of Object.entries(vars ?? {})) {
    if (!(k in CELL_VARS) || typeof v !== 'string' || !CELL_VARS[k].test(v)) throw new Usage(`--vars: ${k} is not an allowed cell variable or its value is off the pattern`);
    out[k] = v === '' ? EMPTY : v;
  }
  return out;
}

export const triggerRequest = ({ appId, workflowId = WORKFLOW, branch, vars }) => {
  const v = cellVars(vars);
  return { method: 'POST', url: `${API}/builds`,
    headers: { 'x-auth-token': '<redacted>', Accept: 'application/json', 'Content-Type': 'application/json' },
    body: { appId, workflowId, branch, ...(Object.keys(v).length ? { environment: { variables: v } } : {}) } };
};

export const urls = { build: (id) => `${API}/builds/${encodeURIComponent(id)}`, apps: `${API}/apps` };


const emptyLedger = () => ({ builds: {} });
export function readLedger(path) {
  try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return emptyLedger(); }
}
export function writeLedger(path, ledger) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(ledger, null, 2)}\n`);
}
export const ledgerRows = (ledger) => Object.entries(ledger.builds ?? {}).map(([id, b]) => ({ id, month: b.month, minutes: b.minutes }));


const pick = (o, ...keys) => { for (const k of keys) if (o?.[k] !== undefined && o[k] !== null) return o[k]; return undefined; };
const ms = (iso) => { const t = Date.parse(iso ?? ''); return Number.isFinite(t) ? t : null; };

export function normBuild(res) {
  const b = res?.build ?? res ?? {};
  const actions = pick(b, 'buildActions', 'actions') ?? [];
  const arts = pick(b, 'artefacts', 'artifacts') ?? [];
  return { id: String(pick(b, '_id', 'id') ?? ''), status: String(b.status ?? ''), index: pick(b, 'index'), instanceType: pick(b, 'instanceType', 'instance_type'),
    createdAt: ms(pick(b, 'createdAt', 'created_at')), startedAt: ms(pick(b, 'startedAt', 'started_at')), finishedAt: ms(pick(b, 'finishedAt', 'finished_at')),
    sha: /^[0-9a-f]{40}$/.test(String(pick(pick(b, 'commit') ?? {}, 'hash') ?? '')) ? String(pick(b, 'commit').hash) : null,
    reportedMinutes: pick(b, 'buildMinutes', 'build_minutes'),
    steps: actions.map((a) => { const s = ms(pick(a, 'startedAt', 'started_at')), e = ms(pick(a, 'finishedAt', 'finished_at')); return { name: String(a.name ?? ''), status: a.status ?? null, durMs: s != null && e != null ? Math.max(0, e - s) : null, logUrl: pick(a, 'logUrl', 'log_url') ?? null }; }),
    artifacts: arts.map((a) => ({ name: String(a.name ?? ''), url: pick(a, 'url', 'short_lived_download_url') ?? null, bytes: pick(a, 'size', 'size_in_bytes') ?? null })) };
}

export function buildMinutes(b) {
  const from = b.startedAt ?? b.createdAt;
  if (from == null || b.finishedAt == null) return null;
  const mine = billedMin(Math.max(0, b.finishedAt - from));
  return Number.isFinite(Number(b.reportedMinutes)) ? Math.max(mine, Math.ceil(Number(b.reportedMinutes))) : mine;
}

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

export async function fetchBuild(ctx, { buildId, out }) {
  const b = normBuild(await call(ctx, 'GET', urls.build(buildId)));
  mkdirSync(join(out, 'artifacts'), { recursive: true });
  const minutes = buildMinutes(b);
  const doc = { schema: 'fw.codemagic-build/1', buildId, status: b.status, index: b.index ?? null, instanceType: b.instanceType ?? null,
    startedAt: b.startedAt, finishedAt: b.finishedAt, createdAt: b.createdAt, sha: b.sha, minutes, steps: b.steps.map(({ name, status, durMs }) => ({ name, status, durMs })), artifacts: b.artifacts.map(({ name, bytes }) => ({ name, bytes })) };
  writeFileSync(join(out, 'build.json'), `${JSON.stringify(doc, null, 2)}\n`);
  for (const a of b.artifacts) {
    if (!a.url) continue;
    try {
      const file = join(out, 'artifacts', safeName(a.name));
      writeFileSync(file, Buffer.from(await (await request(ctx, 'GET', new URL(a.url, API).href, { accept: '*/*' })).arrayBuffer()));
      if (/\.zip$/i.test(a.name)) execFileSync('unzip', ['-o', '-q', '-j', file, '-d', join(out, 'artifacts')]);
    } catch (e) { ctx.log?.(`codemagic: artifact ${a.name}: ${e.message}`); }
  }
  mkdirSync(join(out, 'logs'), { recursive: true });
  for (const [i, s] of b.steps.entries()) {
    if (!s.logUrl) continue;
    try { writeFileSync(join(out, 'logs', `${String(i).padStart(2, '0')}-${safeName(s.name)}.txt`), Buffer.from(await (await request(ctx, 'GET', new URL(s.logUrl, API).href, { accept: '*/*' })).arrayBuffer())); } catch (e) { ctx.log?.(`codemagic: log ${s.name}: ${e.message}`); }
  }
  if (ctx.ledgerPath && minutes != null && exitOf(b.status) !== null) {
    const ledger = readLedger(ctx.ledgerPath);
    const at = b.startedAt ?? b.createdAt ?? ctx.now();
    ledger.builds[buildId] = { month: monthOf(at), minutes, pending: false, status: b.status, at, startedAt: b.startedAt, finishedAt: b.finishedAt, createdAt: b.createdAt };
    writeLedger(ctx.ledgerPath, ledger);
  }
  return doc;
}


export function siteDigest(dir) {
  const files = [];
  const walk = (d, rel) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      if (e.name.startsWith('.')) continue;
      const r = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) walk(join(d, e.name), r);
      else if (e.isFile()) files.push(r);
    }
  };
  walk(dir, '');
  files.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const content = (f) => {
    const buf = readFileSync(join(dir, f));
    if (f !== 'build-info.json') return buf;
    try { const j = JSON.parse(buf.toString('utf8')); delete j.ms; return Buffer.from(JSON.stringify(j)); } catch { return buf; }
  };
  const h = createHash('sha256');
  for (const f of files) { const c = content(f); h.update(`${f}\0${c.length}\0${createHash('sha256').update(c).digest('hex')}\n`); }
  return { digest: files.length ? h.digest('hex') : null, files: files.length };
}

export function digestOfText(text) { return /^([0-9a-f]{64})\b/.exec(text.trim())?.[1] ?? null; }

export function classRows(md) {
  const rows = {};
  for (const line of md.split('\n')) {
    const c = line.split('|').map((x) => x.trim());
    if (c.length < 8 || c[1] === 'family' || /^-+$/.test(c[1])) continue;
    rows[`${c[1]}|${c[2]}|${c[3]}`] = c[4].replaceAll('*', '');
  }
  return rows;
}

export function classDigest(md) {
  const rows = classRows(md), counts = {};
  for (const v of Object.values(rows)) counts[v] = (counts[v] ?? 0) + 1;
  const digest = Object.keys(rows).length ? createHash('sha256').update(`${Object.entries(rows).map(([k, v]) => `${k}=${v}`).sort().join('\n')}\n`).digest('hex') : null;
  return { rows: Object.keys(rows).length, counts, digest };
}

export function compareTables(ghMd, cmMd) {
  const a = classRows(ghMd), b = classRows(cmMd);
  const differ = Object.keys(a).filter((k) => k in b && a[k] !== b[k]).map((k) => ({ key: k, github: a[k], codemagic: b[k] }));
  const onlyGithub = Object.keys(a).filter((k) => !(k in b)), onlyCodemagic = Object.keys(b).filter((k) => !(k in a));
  return { github: classDigest(ghMd), codemagic: classDigest(cmMd), differ, onlyGithub, onlyCodemagic,
    comparable: Object.keys(a).length > 0 && Object.keys(b).length > 0, equal: differ.length === 0 && onlyGithub.length === 0 && onlyCodemagic.length === 0 };
}


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
  'usage: node scripts/codemagic.mjs <sub> ...',
  '  check                                            the token works and the app id is one of the apps (needs FW_CODEMAGIC_APP_ID or .local/codemagic.json)',
  '  trigger --branch ci/<name> [--workflow webkit-sim] [--pool] [--vars JSON] [--dry]   (--vars: FW_TARGET FW_PRESET FW_FW FW_VM FW_SESSIONS FW_SEARCH; cap = codemagic.yaml max_build_duration; --pool: no build count)',
  '  facts                                            {month, used, busy} for the macOS pool (fw ci pool dispatch)',
  '  state --build ID                                 one line, cm:ID running|complete|failed (fw ci state cm:ID); no ledger write',
  '  wait --build ID [--timeout S] [--interval S>=120] [--out DIR]     fetch --build ID --out DIR',
  '  compare --github DIR --codemagic DIR [--vm v1|r1] [--site-github DIR --site-codemagic FILE] [--json]    ledger    digest FILE.md    site-digest DIR    dry-run',
].join('\n');

export function yamlCap(root) {
  const cap = Number(/^\s*max_build_duration:\s*(\d+)\s*$/m.exec(readFileSync(join(root, 'codemagic.yaml'), 'utf8'))?.[1]);
  if (!Number.isInteger(cap) || cap < 1) throw new Error('codemagic.yaml: no max_build_duration');
  return cap;
}
const onlyWorkflow = (w) => { if (w !== undefined && w !== WORKFLOW) throw new Usage(`--workflow must be ${WORKFLOW} (codemagic.yaml has one workflow)`); return WORKFLOW; };

export function triggerDecision(g, ledgerPath, cap, now, pool = false) {
  const month = monthOf(now), rows = ledgerRows(readLedger(ledgerPath)), used = usedIn(month, rows);
  return { month, used, builds: rows.length, cap, rule: pool ? 'poolRefusals' : 'refusals', refusals: pool ? poolRefusals(g.constants, used, cap) : refusals(g.constants, month, rows, cap) };
}

export function poolFacts(ledgerPath, now) {
  const month = monthOf(now), builds = readLedger(ledgerPath).builds ?? {};
  return { month, used: usedIn(month, ledgerRows({ builds })), busy: Object.values(builds).filter((b) => b.pending).length };
}

export async function main(argv, { root = ROOT, env = process.env, ctx: ctx0 = {}, log = console.log } = {}) {
  const [sub, ...rest] = argv[0] === 'codemagic' ? argv.slice(1) : argv;
  try {
    const g = ctx0.golden ?? loadGolden();
    const ctx = { fetchFn: fetch, getToken: keychainToken, sleep: (s) => new Promise((r) => setTimeout(r, s * 1000)), now: () => Date.now(), log, ledgerPath: join(root, '.local', 'codemagic-ledger.json'), ...ctx0 };
    const cfg = loadConfig(root, env);
    const needApp = () => { if (!cfg.appId) throw new Usage('app id not set: FW_CODEMAGIC_APP_ID or .local/codemagic.json {"appId": ...}'); return cfg.appId; };
    if (sub === 'site-digest') {
      if (!rest[0] || !existsSync(rest[0])) throw new Usage('site-digest needs a directory');
      const r = siteDigest(rest[0]);
      if (!r.digest) { console.error('codemagic: site-digest: no files'); return 2; }
      log(`${r.digest}  ${r.files} files`);
      return 0;
    }
    if (sub === 'digest') { if (!rest[0]) throw new Usage('digest needs a file'); log(JSON.stringify(classDigest(readFileSync(rest[0], 'utf8')))); return 0; }
    if (sub === 'ledger') {
      const rows = ledgerRows(readLedger(ctx.ledgerPath)), month = monthOf(ctx.now());
      log(`codemagic: ${rows.length} pilot build(s) in the ledger, ${usedIn(month, rows)} of ${g.constants.freeMinutes} free minutes used in ${month} (stop line ${g.constants.stopAt})`);
      return 0;
    }
    if (sub === 'compare') {
      const o = flags(rest, { github: 'v', codemagic: 'v', json: 'bool', vm: 'v', 'site-github': 'v', 'site-codemagic': 'v' });
      if (!o.github || !o.codemagic) throw new Usage(USAGE);
      const vm = o.vm ?? 'v1';
      if (!/^[vr][1-9][0-9]?$/.test(vm)) throw new Usage('--vm is v<n> or r<n>');
      const r = compareTables(readFileSync(join(o.github, `${vm}-session-1.md`), 'utf8'), readFileSync(join(o.codemagic, `${vm}-session-1.md`), 'utf8'));
      if (o['site-github'] || o['site-codemagic']) {
        if (!o['site-github'] || !o['site-codemagic']) throw new Usage('give both --site-github DIR and --site-codemagic FILE');
        r.site = { github: siteDigest(o['site-github']).digest, codemagic: digestOfText(readFileSync(o['site-codemagic'], 'utf8')) };
        r.site.equal = r.site.github !== null && r.site.github === r.site.codemagic;
      }
      if (o.json) log(JSON.stringify(r));
      else {
        log(`github:    ${r.github.rows} rows ${JSON.stringify(r.github.counts)}\ncodemagic: ${r.codemagic.rows} rows ${JSON.stringify(r.codemagic.counts)}`);
        log(`rows with another class: ${r.differ.length}; only on GitHub: ${r.onlyGithub.length}; only on Codemagic: ${r.onlyCodemagic.length}`);
        for (const d of r.differ.slice(0, 40)) log(`  ${d.key}: ${d.github} -> ${d.codemagic}`);
      }
      if (r.site) log(`site digest: github ${r.site.github ?? 'none'}, codemagic ${r.site.codemagic ?? 'none'}: ${r.site.equal ? 'equal' : 'DIFFERENT (the cell is not routable)'}`);
      return !r.comparable ? 2 : r.site && !r.site.equal ? 3 : r.equal ? 0 : 1;
    }
    if (sub === 'state') {
      const o = flags(rest, { build: 'v' });
      if (!/^[0-9a-f]{24}$/.test(o.build ?? '')) throw new Usage('give --build ID (24 hex digits)');
      log(`cm:${o.build} ${stateWord(normBuild(await call(ctx, 'GET', urls.build(o.build))).status)}`);
      return 0;
    }
    if (sub === 'facts') { flags(rest, {}); log(JSON.stringify(poolFacts(ctx.ledgerPath, ctx.now()))); return 0; }
    if (sub === 'dry-run' || (sub === 'trigger' && rest.includes('--dry'))) {
      const o = flags(rest.filter((x) => x !== 'dry-run'), { branch: 'v', workflow: 'v', dry: 'bool', pool: 'bool' });
      const cap = yamlCap(root), branch = o.branch ?? 'ci/codemagic-pilot';
      const req = triggerRequest({ appId: cfg.appId || '<app-id>', workflowId: onlyWorkflow(o.workflow), branch });
      const d = triggerDecision(g, ctx.ledgerPath, cap, ctx.now(), !!o.pool);
      log(`${req.method} ${req.url}\n${JSON.stringify({ headers: req.headers, body: { ...req.body, appId: req.body.appId === cfg.appId && cfg.appId ? '<app-id>' : req.body.appId } }, null, 2)}`);
      log(`ledger (Lean Fw.Ci.Codemagic.${d.rule}): month ${d.month}, ${d.used} of ${g.constants.freeMinutes} minutes used, ${d.builds} pilot build(s), cap ${d.cap} -> ${d.refusals.length ? `REFUSED (${d.refusals.join(', ')})` : 'allowed'}`);
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
      const o = flags(rest, { branch: 'v', workflow: 'v', dry: 'bool', pool: 'bool', vars: 'v' });
      if (!/^ci\/[A-Za-z0-9._/-]+$/.test(o.branch ?? '')) throw new Usage(USAGE);
      const cap = yamlCap(root), workflowId = onlyWorkflow(o.workflow);
      const d = triggerDecision(g, ctx.ledgerPath, cap, ctx.now(), !!o.pool);
      if (d.refusals.length) { log(`STOP (Lean Fw.Ci.Codemagic.${d.rule}): ${d.refusals.join(', ')}; ${d.used} of ${g.constants.freeMinutes} minutes used in ${d.month} (line ${g.constants.stopAt}), ${d.builds} build(s) in the ledger${o.pool ? '' : ` (max ${g.constants.maxBuilds})`}, cap ${cap}`); return 5; }
      const req = triggerRequest({ appId: needApp(), workflowId, branch: o.branch, vars: o.vars ? JSON.parse(o.vars) : {} });
      const ledger = readLedger(ctx.ledgerPath), tmpId = `pending-${ctx.now()}`;
      ledger.builds[tmpId] = { month: d.month, minutes: cap, pending: true, at: ctx.now() };
      writeLedger(ctx.ledgerPath, ledger);
      let r;
      try { r = await call(ctx, req.method, req.url, req.body); } catch (e) { if (e.status >= 400 && e.status < 500) { delete ledger.builds[tmpId]; writeLedger(ctx.ledgerPath, ledger); } throw e; }
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
