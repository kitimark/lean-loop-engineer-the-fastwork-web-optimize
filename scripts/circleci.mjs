#!/usr/bin/env node
// circleci (task circleci-pilot): the glue between this repo and the CircleCI pilot (.circleci/config.yml;
// docs/team/tools/circleci.md). Every decision is the Lean module lean/Fw/Ci/Provider.lean, replayed from its golden
// packages/contracts/golden/ci/provider.jsonl (the price list, the limits and the job map are READ from the golden, not
// copied here; scripts/circleci.test.mjs replays every other row through the functions below). This file is request
// building, parsing, polling, file writing and printing.
//
//   fw ci circleci trigger --lane premise-tests|webkit-sim --branch ci/<name> [--class C] [--xcode V] [--dry]
//   fw ci circleci wait (--pipeline ID | --branch ci/<name> [--since EPOCH]) [--timeout S] [--interval S] [--out DIR]
//   fw ci circleci fetch --pipeline ID --out DIR
//   fw ci circleci compare --github gh-run.json --circleci DIR/run.json [--json]
//   fw ci circleci route --lane L --platform linux-arm|macos --class C --est-ms N --credits-left N [--allow a,b] [--gh-degraded]
//   fw ci circleci digest DIR
//   fw ci circleci dry-run [--lane L] [--branch ci/x] [--fixture NAME]
//   (also: fw ci wait --provider circleci ...; node scripts/circleci.mjs timings ... is the in-job step of .circleci/job.sh)
//
// The token is read from the macOS Keychain (service fw-circleci-token) inside each request: it is never printed, never in an
// argument list, never in a file; a dry run prints `<redacted>`. Exit codes of wait: 0 every workflow passed, 1 one failed,
// 3 timeout, 4 no workflow ran, 5 the pilot stop rule fired (the workflow is cancelled), 64 usage. compare: 0 no finding,
// 1 a finding (a verdict differs), 2 a pair that is not a pair.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const ROOT = resolve(here, '..');
export const GOLDEN = join(ROOT, 'packages', 'contracts', 'golden', 'ci', 'provider.jsonl');
export const API = 'https://circleci.com/api/v2';
export const KEYCHAIN_SERVICE = 'fw-circleci-token';
/** CircleCI answers 429 with a Retry-After; a poll is never faster than this (gh-hygiene: polls >= 120 s). */
export const MIN_POLL_S = 120;
export const LANES = ['premise-tests', 'webkit-sim'];
export const CLASSES = ['arm.medium.gen2', 'arm.large.gen2'];

export class Usage extends Error {}

// ---------------------------------------------------------------------------------------------------------------- golden

/** The golden rows by op: { rates, constants, jobMap, credits: [...], ... }. */
export function loadGolden(path = GOLDEN) {
  const rows = readFileSync(path, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const byOp = {};
  for (const r of rows) (byOp[r.op] ??= []).push(r);
  return { rows, byOp, rates: byOp.rates[0].response, constants: byOp.constants[0].response, jobMap: byOp.jobMap[0].response.jobs };
}

// --------------------------------------------------------------------- the Lean decisions (checked against the golden rows)

/** Lean `Fw.Ci.Provider.credits`: price times duration rounded up to a whole credit; null for a class outside the price list. */
export function credits(g, cls, durMs) {
  const r = g.rates.rates.find((x) => x.class === cls);
  return r ? Math.floor((durMs * r.creditsPerMin + 59999) / 60000) : null;
}

/** Lean `storageMilli`: bytes times retention days over 30 days, thousandths of a GB-month, rounded up. */
export function storageMilli(bytes, days) {
  return Number((BigInt(bytes) * BigInt(days) * 1000n + 30n * 1000000000n - 1n) / (30n * 1000000000n));
}

/** Lean `verdictEq`. */
export const verdictEq = (a, b) => a.conclusion === b.conclusion && (a.digest == null || b.digest == null || a.digest === b.digest);

/** Lean `compare`: { comparable: false, reason } or { comparable: true, finding, ratioPermille, queueGithubMs, queueCircleMs, credits }. */
export function compare(g, gh, cc) {
  if (gh.provider !== 'github' || cc.provider !== 'circleci') return { comparable: false, reason: 'providers' };
  if (gh.job !== cc.job) return { comparable: false, reason: 'job' };
  if (gh.sha !== cc.sha) return { comparable: false, reason: 'sha' };
  return { comparable: true, finding: !verdictEq(gh, cc), ratioPermille: gh.durMs === 0 ? null : Math.floor((cc.durMs * 1000) / gh.durMs),
    queueGithubMs: gh.queueMs, queueCircleMs: cc.queueMs, credits: credits(g, cc.class, cc.durMs) };
}

/** Lean `stops`: every reason the pilot stops, in the order cap, queue, storage. */
export function stops(g, i) {
  const c = g.constants;
  return [...(c.capMs <= i.durMs ? ['cap'] : []), ...(c.queueMaxMs < i.queueMs ? ['queue'] : []), ...(c.storageMaxMilli < i.storageMilli ? ['storage'] : [])];
}

/** Lean `route`: github or circleci for one lane. */
export function route(g, i) {
  const r = g.rates.rates.find((x) => x.class === i.class);
  const affordable = !!r && r.free && r.platform === i.platform && Math.floor((i.estMs * r.creditsPerMin + 59999) / 60000) <= i.creditsLeft;
  return i.allow.includes(i.lane) && affordable && (i.platform !== 'macos' || i.ghDegraded) ? 'circleci' : 'github';
}

// ----------------------------------------------------------------------------------------------------- statuses and digests

/** A CircleCI job/workflow status as a Lean `Conclusion`. */
export function circleConclusion(status) {
  if (status === 'success') return 'pass';
  if (['failed', 'infrastructure_fail', 'timedout', 'error', 'failing'].includes(status)) return 'fail';
  return 'not-run';
}

/** A GitHub job conclusion as a Lean `Conclusion` (cancelled and skipped did not reach a verdict). */
export function githubConclusion(c) {
  if (c === 'success') return 'pass';
  if (['failure', 'timed_out', 'startup_failure', 'action_required'].includes(c)) return 'fail';
  return 'not-run';
}

/** The digest of the premise result files in a directory (recursive): sha256 over the sorted `testId:ok` lines of every
 *  `results` array. The same function on the GitHub artifact and on the CircleCI artifact; null when no result file is found. */
export function premiseDigest(dir) {
  const lines = [];
  const walk = (d) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const p = join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.json')) {
        try { const j = JSON.parse(readFileSync(p, 'utf8')); if (Array.isArray(j.results)) for (const r of j.results) lines.push(`${r.testId}:${r.ok === true}`); } catch { /* not a result file */ }
      }
    }
  };
  if (existsSync(dir)) walk(dir);
  return lines.length ? createHash('sha256').update(`${lines.sort().join('\n')}\n`).digest('hex') : null;
}

const ms = (iso) => { const t = Date.parse(iso ?? ''); return Number.isFinite(t) ? t : null; };
const span = (job, step, startMs, durMs, commit = '') => ({ tool: `circleci/${job}`, step, startMs, durMs: Math.max(0, durMs), exit: 0, commit, load: 0, host: 'ci' });

// --------------------------------------------------------------------------------------------------------- in-job timings

/** `timings.json` of a job: its spans (the span.sh lines) with the job, class, commit and digest. */
export function timingsDoc({ spansText, job, cls, sha, digest }) {
  const spans = spansText.split('\n').filter(Boolean).flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
  return { schema: 'fw.circleci-timings/1', job, class: cls, sha, digest: digest ?? null, spans };
}

// ------------------------------------------------------------------------------------------------------------------ HTTP

/** Read the token from the Keychain; the argument list holds the service name only. Throws a hint, never the token. */
export function keychainToken() {
  try {
    const t = execFileSync('security', ['find-generic-password', '-s', KEYCHAIN_SERVICE, '-w'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    if (t) return t;
  } catch { /* fall through */ }
  throw new Usage(`no CircleCI token in the Keychain (service ${KEYCHAIN_SERVICE}); see docs/team/tools/circleci.md, step 4`);
}

export const redact = (text, token) => (token ? String(text).split(token).join('<redacted>') : String(text));

/** One API call: the token is fetched by `getToken` inside the call; a 429 waits Retry-After seconds (at most `retries` times). */
export async function call({ fetchFn = fetch, getToken = keychainToken, sleep = (s) => new Promise((r) => setTimeout(r, s * 1000)), retries = 3 }, method, url, body) {
  for (let attempt = 0; ; attempt++) {
    const token = getToken();
    const res = await fetchFn(url, { method, headers: { 'Circle-Token': token, Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
    if (res.status === 429 && attempt < retries) {
      const raw = res.headers?.get?.('retry-after');
      const ra = raw == null || raw === '' ? NaN : Number(raw);
      await sleep(Math.max(Number.isFinite(ra) ? ra : 60, 1));
      continue;
    }
    if (!res.ok) throw new Error(redact(`${method} ${url.replace(API, '')}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`, token));
    const text = await res.text();
    return text ? JSON.parse(text) : {};
  }
}

// -------------------------------------------------------------------------------------------------------------- requests

/** The request that starts a pipeline for a branch (POST /project/{slug}/pipeline/run; the definition id is the project's
 *  pipeline definition). Returns { method, url, headers, body } with the token left out. */
export function triggerRequest({ slug, definitionId, branch, lane, cls, xcode }) {
  const parameters = { lane };
  if (lane === 'premise-tests' && cls) parameters.resource_class = cls;
  if (lane === 'webkit-sim' && xcode) parameters.xcode = xcode;
  return { method: 'POST', url: `${API}/project/${slug}/pipeline/run`, headers: { 'Circle-Token': '<redacted>', Accept: 'application/json', 'Content-Type': 'application/json' },
    body: { definition_id: definitionId, config: { branch }, checkout: { branch }, parameters } };
}

export const urls = {
  workflows: (pipelineId) => `${API}/pipeline/${pipelineId}/workflow`,
  jobs: (workflowId) => `${API}/workflow/${workflowId}/job`,
  job: (slug, n) => `${API}/project/${slug}/job/${n}`,
  artifacts: (slug, n) => `${API}/project/${slug}/${n}/artifacts`,
  cancel: (workflowId) => `${API}/workflow/${workflowId}/cancel`,
  pipelines: (slug, branch) => `${API}/project/${slug}/pipeline?branch=${encodeURIComponent(branch)}`,
};

/** The project slug and pipeline definition: env FW_CIRCLECI_SLUG / FW_CIRCLECI_DEFINITION_ID, else the local-only
 *  .local/circleci.json ({slug, definitionId}). Never committed. */
export function loadConfig(root = ROOT, env = process.env) {
  let f = {};
  try { f = JSON.parse(readFileSync(join(root, '.local', 'circleci.json'), 'utf8')); } catch { /* none */ }
  return { slug: env.FW_CIRCLECI_SLUG || f.slug || '', definitionId: env.FW_CIRCLECI_DEFINITION_ID || f.definitionId || '' };
}

// ------------------------------------------------------------------------------------------------------------ run reading

const TERMINAL = new Set(['success', 'failed', 'error', 'canceled', 'not_run', 'unauthorized', 'infrastructure_fail', 'timedout', 'terminated-unknown']);

/** Lean `Run` of a finished CircleCI job (detail of GET /project/{slug}/job/{n}); queue = queued_at (else created_at) to started_at. */
export function circleRun(detail, { sha, digest = null }) {
  const started = ms(detail.started_at), stopped = ms(detail.stopped_at), queuedAt = ms(detail.queued_at) ?? ms(detail.created_at);
  return { provider: 'circleci', job: detail.name, sha, conclusion: circleConclusion(detail.status), digest, class: detail.executor?.resource_class ?? '',
    queueMs: started != null && queuedAt != null ? Math.max(0, started - queuedAt) : 0,
    durMs: Number.isFinite(detail.duration) ? detail.duration : started != null && stopped != null ? stopped - started : 0 };
}

/** Lean `Run`s of a GitHub run as `gh run view <id> --json workflowName,headSha,createdAt,jobs` prints it, for the jobs of the
 *  job map; `digests` maps a GitHub job name to the premiseDigest of its artifact. Queue = run createdAt to job startedAt. */
export function githubRuns(g, run, digests = {}) {
  const out = [];
  for (const m of g.jobMap) {
    const j = (run.jobs ?? []).find((x) => x.name === m.github);
    if (!j) continue;
    const s = ms(j.startedAt), e = ms(j.completedAt), c = ms(run.createdAt);
    out.push({ provider: 'github', job: m.circleci, lane: m.lane, sha: run.headSha ?? '', conclusion: githubConclusion(j.conclusion), digest: digests[j.name] ?? null,
      class: '', queueMs: s != null && c != null ? Math.max(0, s - c) : 0, durMs: s != null && e != null ? Math.max(0, e - s) : 0 });
  }
  return out;
}

// ----------------------------------------------------------------------------------------------------------- the pilot

const sleepReal = (s) => new Promise((r) => setTimeout(r, s * 1000));

/** The pilot stop rule over the jobs seen at one poll. Returns the Lean reasons per job. */
export async function pollOnce(ctx, { slug, pipelineId, sha, now }) {
  const g = ctx.golden;
  const wfs = (await call(ctx, 'GET', urls.workflows(pipelineId))).items ?? [];
  const jobs = [];
  for (const wf of wfs) {
    const items = (await call(ctx, 'GET', urls.jobs(wf.id))).items ?? [];
    for (const j of items) {
      let queueMs = 0, durMs = 0;
      if (j.job_number != null && (j.status === 'queued' || j.status === 'running')) {
        const d = await call(ctx, 'GET', urls.job(slug, j.job_number));
        const q = ms(d.queued_at) ?? ms(d.created_at), s = ms(d.started_at);
        queueMs = q == null ? 0 : (s ?? now) - q;
        durMs = s == null ? 0 : (ms(d.stopped_at) ?? now) - s;
      }
      jobs.push({ workflow: wf, name: j.name, status: j.status, number: j.job_number, stops: stops(g, { durMs, queueMs, storageMilli: 0 }) });
    }
  }
  return { workflows: wfs, jobs, sha };
}

/** Wait for a pipeline: polls every `intervalS` (at least MIN_POLL_S), stops the pilot when the stop rule fires. Exit codes in the header. */
export async function waitPipeline(ctx, { slug, pipelineId, timeoutS = 3600, intervalS = MIN_POLL_S, noWorkflowS = 300 }) {
  const log = ctx.log ?? console.log;
  const step = Math.max(intervalS, ctx.minPollS ?? MIN_POLL_S);
  const t0 = ctx.now();
  for (;;) {
    const now = ctx.now();
    const p = await pollOnce(ctx, { slug, pipelineId, now });
    for (const j of p.jobs) {
      if (j.stops.length) {
        log(`STOP ${j.name}: ${j.stops.join(', ')} (Lean Fw.Ci.Provider.stops); cancelling its workflow`);
        await call(ctx, 'POST', urls.cancel(j.workflow.id));
        return { code: 5, ...p };
      }
    }
    log(`poll: ${p.workflows.length} workflow(s), jobs ${p.jobs.map((j) => `${j.name}=${j.status}`).join(' ') || 'none yet'}`);
    if (p.workflows.length && p.workflows.every((w) => TERMINAL.has(w.status))) {
      const st = p.workflows.map((w) => w.status);
      return { code: st.every((s) => s === 'success') ? 0 : st.some((s) => ['failed', 'error', 'infrastructure_fail', 'timedout', 'unauthorized'].includes(s)) ? 1 : 4, ...p };
    }
    const waited = (now - t0) / 1000;
    if (!p.workflows.length && waited >= noWorkflowS) return { code: 4, ...p };
    if (waited >= timeoutS) return { code: 3, ...p };
    await ctx.sleep(step);
  }
}

/** Download the artifacts of every finished job of the pipeline into `out/<job>/...` and write `out/run.json`
 *  ({schema, pipelineId, sha, runs: [Lean Run], spans, storage}). The artifact path is checked: no `..`, no absolute path. */
export async function fetchPipeline(ctx, { slug, pipelineId, out, sha = '' }) {
  const g = ctx.golden;
  mkdirSync(out, { recursive: true });
  const runs = [], spans = [];
  let bytes = 0;
  const wfs = (await call(ctx, 'GET', urls.workflows(pipelineId))).items ?? [];
  for (const wf of wfs) {
    for (const j of (await call(ctx, 'GET', urls.jobs(wf.id))).items ?? []) {
      if (j.job_number == null || !TERMINAL.has(j.status)) continue;
      const d = await call(ctx, 'GET', urls.job(slug, j.job_number));
      const dir = join(out, j.name);
      mkdirSync(dir, { recursive: true });
      for (const a of (await call(ctx, 'GET', urls.artifacts(slug, j.job_number))).items ?? []) {
        const rel = String(a.path).replace(/^\/+/, '');
        if (rel.split('/').includes('..') || rel === '') throw new Error(`artifact path ${a.path} leaves the output directory`);
        const dest = join(dir, ...rel.split('/'));
        if (!(dest + sep).startsWith(dir + sep)) throw new Error(`artifact path ${a.path} leaves the output directory`);
        const res = await ctx.fetchFn(a.url, { headers: /(^|\.)circleci\.com$|(^|\.)circle-artifacts\.com$/.test(new URL(a.url).hostname) ? { 'Circle-Token': ctx.getToken() } : {} });
        if (!res.ok) throw new Error(`artifact ${rel} of ${j.name}: HTTP ${res.status}`);
        const buf = Buffer.from(await res.arrayBuffer());
        mkdirSync(dirname(dest), { recursive: true });
        writeFileSync(dest, buf);
        bytes += buf.length;
      }
      const jobSha = sha || d.pipeline?.vcs?.revision || '';
      const run = circleRun(d, { sha: jobSha, digest: LANES_WITH_DIGEST.includes(j.name) ? premiseDigest(dir) : null });
      runs.push(run);
      const started = ms(d.started_at), stopped = ms(d.stopped_at), queuedAt = ms(d.queued_at) ?? ms(d.created_at);
      let own = [];
      try { own = JSON.parse(readFileSync(join(dir, 'timings.json'), 'utf8')).spans ?? []; } catch { /* no timings.json: the job died before finish */ }
      const lastEnd = own.reduce((m, s) => Math.max(m, s.startMs + s.durMs), started ?? 0);
      if (queuedAt != null && started != null) spans.push(span(j.name, 'queue', queuedAt, started - queuedAt, jobSha.slice(0, 7)));
      spans.push(...own);
      if (stopped != null) spans.push(span(j.name, 'upload (after the last step)', lastEnd, stopped - lastEnd, jobSha.slice(0, 7)));
      if (started != null && stopped != null) spans.push(span(j.name, 'job', started, stopped - started, jobSha.slice(0, 7)));
    }
  }
  const doc = { schema: 'fw.circleci-run/1', pipelineId, sha: sha || (runs[0]?.sha ?? ''), runs, spans, storage: { bytes, days: 30, milli: storageMilli(bytes, 30), stops: stops(g, { durMs: 0, queueMs: 0, storageMilli: storageMilli(bytes, 30) }) } };
  writeFileSync(join(out, 'run.json'), `${JSON.stringify(doc, null, 2)}\n`);
  return doc;
}
const LANES_WITH_DIGEST = ['engine-chromium', 'engine-playwright-webkit'];

/** Pair the runs by job and compare them with the Lean verdict: lines for print, and the exit code. */
export function comparePairs(g, ghRuns, ccRuns) {
  const rows = [];
  for (const m of g.jobMap) {
    const gh = ghRuns.find((r) => r.job === m.circleci), cc = ccRuns.find((r) => r.job === m.circleci);
    if (!gh || !cc) { if (gh || cc) rows.push({ job: m.circleci, unpaired: gh ? 'circleci' : 'github' }); continue; }
    rows.push({ job: m.circleci, ...compare(g, gh, cc) });
  }
  const code = rows.some((r) => r.comparable === false || r.unpaired) ? 2 : rows.some((r) => r.finding) ? 1 : 0;
  return { rows, code };
}

export function renderComparison(rows) {
  const f = (r) => r.unpaired ? `${r.job}: only one side ran (missing: ${r.unpaired})`
    : !r.comparable ? `${r.job}: not a pair (${r.reason})`
    : `${r.job}: ${r.finding ? 'FINDING verdicts differ' : 'verdicts equal'}; duration ${r.ratioPermille == null ? 'n/a' : `${(r.ratioPermille / 1000).toFixed(2)}x GitHub`}; queue github ${Math.round(r.queueGithubMs / 1000)}s, circleci ${Math.round(r.queueCircleMs / 1000)}s; credits ${r.credits ?? 'n/a (class not in the price list)'}`;
  return rows.map(f).join('\n');
}

// ----------------------------------------------------------------------------------------------------------- dry run

/** The fixture-backed fetch of the dry run: serves a recorded API (scripts/circleci-fixtures/<name>.json, section `api`). */
export function fixtureFetch(api) {
  return async (url, init = {}) => {
    const u = String(url);
    const path = u.startsWith(API) ? u.slice(API.length) : u;
    const make = (status, body) => ({ status, ok: status < 400, headers: { get: () => null }, text: async () => JSON.stringify(body), arrayBuffer: async () => Buffer.from(typeof body === 'string' ? body : JSON.stringify(body)) });
    if (api.files && api.files[u] !== undefined) return make(200, api.files[u]);
    const hit = api.routes[`${init.method ?? 'GET'} ${path}`];
    if (hit === undefined) return make(404, { message: `fixture has no ${init.method ?? 'GET'} ${path}` });
    return make(200, hit);
  };
}

export function loadFixture(name, dir = join(here, 'circleci-fixtures')) {
  return JSON.parse(readFileSync(join(dir, `${name}.json`), 'utf8'));
}

/** Print the exact requests of one lane (token redacted), then replay wait + fetch + compare over a recorded fixture. */
export async function dryRun({ golden, lane, branch, cls = CLASSES[0], xcode = '27.0.0', fixture = lane, log = console.log, tmp }) {
  const slug = '<project-slug>';
  const req = triggerRequest({ slug, definitionId: '<definition-id>', branch, lane, cls, xcode });
  log(`${req.method} ${req.url}`);
  for (const [k, v] of Object.entries(req.headers)) log(`  ${k}: ${v}`);
  log(`  ${JSON.stringify(req.body)}`);
  for (const [name, url] of [['pipeline workflows', urls.workflows('<pipeline-id>')], ['workflow jobs', urls.jobs('<workflow-id>')], ['job detail', urls.job(slug, '<job-number>')], ['job artifacts', urls.artifacts(slug, '<job-number>')], ['cancel on stop', urls.cancel('<workflow-id>')]]) {
    log(`${name === 'cancel on stop' ? 'POST' : 'GET'} ${url}   (${name}; header Circle-Token: <redacted>)`);
  }
  const fx = loadFixture(fixture);
  const ctx = { golden, fetchFn: fixtureFetch(fx.api), getToken: () => 'fixture-token', sleep: async () => {}, now: () => Date.parse(fx.now), log, minPollS: 0 };
  const w = await waitPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, timeoutS: 10, intervalS: 0 });
  log(`fixture ${fixture}: wait exit ${w.code}`);
  if (w.code !== 0) return { wait: w };
  const out = tmp ?? mkdtempSync(join(tmpdir(), 'fwcircleci-'));
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out, sha: fx.sha });
  const gh = githubRuns(golden, fx.github, fx.github.digests ?? {});
  const cmp = comparePairs(golden, gh, doc.runs);
  log(renderComparison(cmp.rows));
  log(`storage: ${doc.storage.bytes} bytes, ${doc.storage.milli} thousandths of a GB-month${doc.storage.stops.length ? `; STOP ${doc.storage.stops.join(',')}` : ''}`);
  return { wait: w, doc, cmp };
}

// -------------------------------------------------------------------------------------------------------------- CLI

function flags(argv, spec) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i];
    const k = f.replace(/^--/, '');
    if (!f.startsWith('--') || !(k in spec)) throw new Usage(`unexpected argument ${f}`);
    if (spec[k] === 'bool') o[k] = true;
    else { const v = argv[++i]; if (v === undefined || v.startsWith('--')) throw new Usage(`flag ${f} needs a value`); o[k] = v; }
  }
  return o;
}

const USAGE = [
  'usage: fw ci circleci <sub> ...',
  '  trigger --lane premise-tests|webkit-sim --branch ci/<name> [--class arm.medium.gen2|arm.large.gen2] [--xcode V] [--dry]',
  '  wait (--pipeline ID | --branch ci/<name> [--since EPOCH]) [--timeout S] [--interval S>=120] [--out DIR]',
  '  fetch --pipeline ID --out DIR      compare --github gh-run.json --circleci DIR/run.json [--json]',
  '  route --lane L --platform linux-arm|macos --class C --est-ms N --credits-left N [--allow a,b] [--gh-degraded]',
  '  digest DIR      dry-run [--lane L] [--branch ci/x]',
].join('\n');

export async function main(argv, { root = ROOT, env = process.env, ctx: ctx0 = {}, log = console.log } = {}) {
  const [sub, ...rest] = argv[0] === 'circleci' ? argv.slice(1) : argv;
  const golden = ctx0.golden ?? loadGolden();
  try {
    if (sub === 'timings') {
      const o = flags(rest, { spans: 'v', out: 'v', job: 'v', class: 'v', sha: 'v', 'digest-from': 'v' });
      const doc = timingsDoc({ spansText: readFileSync(o.spans, 'utf8'), job: o.job, cls: o.class, sha: o.sha ?? '', digest: o['digest-from'] ? premiseDigest(o['digest-from']) : null });
      writeFileSync(o.out, `${JSON.stringify(doc, null, 2)}\n`);
      return 0;
    }
    if (sub === 'digest') { if (!rest[0]) throw new Usage('digest needs a directory'); log(premiseDigest(rest[0]) ?? 'none'); return 0; }
    if (sub === 'route') {
      const o = flags(rest, { lane: 'v', platform: 'v', class: 'v', 'est-ms': 'v', 'credits-left': 'v', allow: 'v', 'gh-degraded': 'bool' });
      if (!o.lane || !['linux-arm', 'macos'].includes(o.platform) || !o.class || !(Number(o['est-ms']) >= 0) || !(Number(o['credits-left']) >= 0)) throw new Usage(USAGE);
      log(route(golden, { lane: o.lane, platform: o.platform, class: o.class, allow: (o.allow ?? '').split(',').filter(Boolean), ghDegraded: !!o['gh-degraded'], estMs: Number(o['est-ms']), creditsLeft: Number(o['credits-left']) }));
      return 0;
    }
    if (sub === 'compare') {
      const o = flags(rest, { github: 'v', circleci: 'v', json: 'bool' });
      if (!o.github || !o.circleci) throw new Usage(USAGE);
      const gh = JSON.parse(readFileSync(o.github, 'utf8'));
      const digests = Object.fromEntries(Object.entries(gh.digestDirs ?? {}).map(([k, d]) => [k, premiseDigest(resolve(dirname(o.github), d))]));
      const cmp = comparePairs(golden, githubRuns(golden, gh, { ...(gh.digests ?? {}), ...digests }), JSON.parse(readFileSync(o.circleci, 'utf8')).runs);
      log(o.json ? JSON.stringify(cmp) : renderComparison(cmp.rows));
      return cmp.code;
    }
    if (sub === 'dry-run') {
      const o = flags(rest, { lane: 'v', branch: 'v', class: 'v', xcode: 'v', fixture: 'v' });
      for (const lane of o.lane ? [o.lane] : LANES) {
        if (!LANES.includes(lane)) throw new Usage(`unknown lane ${lane}; lanes: ${LANES.join(', ')}`);
        await dryRun({ golden, lane, branch: o.branch ?? 'ci/circleci-pilot', cls: o.class, xcode: o.xcode, fixture: o.fixture, log });
      }
      return 0;
    }
    const cfg = loadConfig(root, env);
    const need = (what) => { if (!cfg[what]) throw new Usage(`${what === 'slug' ? 'project slug' : 'pipeline definition id'} not set: FW_CIRCLECI_${what === 'slug' ? 'SLUG' : 'DEFINITION_ID'} or .local/circleci.json (docs/team/tools/circleci.md, step 5)`); return cfg[what]; };
    const ctx = { golden, fetchFn: fetch, getToken: keychainToken, sleep: sleepReal, now: Date.now, log, ...ctx0 };
    if (sub === 'trigger') {
      const o = flags(rest, { lane: 'v', branch: 'v', class: 'v', xcode: 'v', dry: 'bool' });
      if (!LANES.includes(o.lane) || !/^ci\/[A-Za-z0-9._/-]+$/.test(o.branch ?? '')) throw new Usage(USAGE);
      if (o.class && !CLASSES.includes(o.class)) throw new Usage(`--class must be one of ${CLASSES.join(', ')} (no paid class)`);
      const req = triggerRequest({ slug: o.dry ? (cfg.slug || '<project-slug>') : need('slug'), definitionId: o.dry ? (cfg.definitionId || '<definition-id>') : need('definitionId'), branch: o.branch, lane: o.lane, cls: o.class, xcode: o.xcode });
      if (o.dry) { log(`${req.method} ${req.url}`); log(JSON.stringify({ headers: req.headers, body: req.body }, null, 2)); return 0; }
      const r = await call(ctx, req.method, req.url, req.body);
      log(`circleci: pipeline ${r.id} (number ${r.number}, ${r.state}) for ${o.branch}, lane ${o.lane}; wait with: pnpm fw ci wait --provider circleci --pipeline ${r.id}`);
      return 0;
    }
    if (sub === 'wait' || sub === 'fetch') {
      const o = flags(rest, { provider: 'v', pipeline: 'v', branch: 'v', since: 'v', timeout: 'v', interval: 'v', out: 'v' });
      if (o.provider && o.provider !== 'circleci') throw new Usage('--provider must be circleci here');
      const slug = need('slug');
      let pipelineId = o.pipeline;
      if (!pipelineId) {
        if (!o.branch) throw new Usage('give --pipeline ID or --branch ci/<name>');
        const list = (await call(ctx, 'GET', urls.pipelines(slug, o.branch))).items ?? [];
        const since = o.since ? Number(o.since) * 1000 : 0;
        const p = list.find((x) => (ms(x.created_at) ?? 0) >= since);
        if (!p) { log(`circleci: no pipeline for ${o.branch}${since ? ' since the given time' : ''}`); return 4; }
        pipelineId = p.id;
      }
      if (sub === 'fetch') {
        if (!o.out) throw new Usage('fetch needs --out DIR');
        const doc = await fetchPipeline(ctx, { slug, pipelineId, out: resolve(o.out) });
        log(`circleci: fetched ${doc.runs.length} job(s) to ${o.out}/run.json`);
        return 0;
      }
      const interval = Number(o.interval ?? MIN_POLL_S);
      if (!(interval >= MIN_POLL_S)) throw new Usage(`--interval must be at least ${MIN_POLL_S} s`);
      const w = await waitPipeline(ctx, { slug, pipelineId, timeoutS: Number(o.timeout ?? 3600), intervalS: interval });
      log(`circleci: pipeline ${pipelineId} ended with exit ${w.code} (0 pass, 1 fail, 3 timeout, 4 not run, 5 stop rule)`);
      if (o.out && w.code !== 3) { const doc = await fetchPipeline(ctx, { slug, pipelineId, out: resolve(o.out) }); log(`circleci: ${doc.runs.length} job(s) in ${o.out}/run.json`); }
      return w.code;
    }
    throw new Usage(USAGE);
  } catch (e) {
    if (e instanceof Usage) { console.error(e.message); return 64; }
    console.error(`circleci: ${e.message}`);
    return 1;
  }
}

export const SCRIPT = join('scripts', 'circleci.mjs');
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = await main(process.argv.slice(2));
