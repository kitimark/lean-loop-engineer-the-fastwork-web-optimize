#!/usr/bin/env node
// circleci (task circleci-pilot): the glue between this repo and the CircleCI pilot (.circleci/config.yml;
// docs/team/tools/circleci.md). Every decision is the Lean module lean/Fw/Ci/Provider.lean, replayed from its golden
// packages/contracts/golden/ci/provider.jsonl (the price list, the limits and the job map are READ from the golden, not
// copied here; scripts/circleci.test.mjs replays every other row through the functions below). This file is request
// building, parsing, polling, file writing and printing.
//
//   fw ci circleci trigger --lane premise-tests|webkit-sim|land --branch ci/<name> [--class C] [--xcode V] [--legs a,b] [--dry]
//   fw ci circleci wait (--pipeline ID | --branch ci/<name> [--since EPOCH]) [--timeout S] [--interval S] [--out DIR]
//   fw ci circleci fetch --pipeline ID --out DIR
//   fw ci circleci compare --github gh-run.json --circleci DIR/run.json [--json]   (downloads the GitHub premises-<engine> artifacts)
//   fw ci circleci route --lane L --platform linux-arm|macos --class C --est-ms N --credits-left N [--allow a,b] [--gh-degraded]
//   fw ci circleci digest DIR
//   fw ci circleci dry-run [--lane L] [--branch ci/x] [--fixture NAME]
//   (also: fw ci wait --provider circleci ...; node scripts/circleci.mjs timings ... is the in-job step of .circleci/job.sh)
//
// The token is read from the macOS Keychain (service fw-circleci-token) inside each request: it is never printed, never in an
// argument list, never in a file; a dry run prints `<redacted>`. Exit codes of wait (Lean `waitStep`): 0 every workflow passed,
// 1 one failed, 3 timeout, 4 no workflow ran or one was cancelled, 5 the pilot stop rule fired (the workflow is cancelled; also
// fetch), 64 usage. compare: 0 no finding, 1 a finding (a verdict differs), 2 a pair that is not a pair (job, commit or a
// missing digest).
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
export const LANES = ['premise-tests', 'webkit-sim', 'land'];

/** The land legs (lean/land-legs.txt, the names of .github/workflows/land.yml's matrix): the values of `--legs`. */
export const landLegs = (root = ROOT) => readFileSync(join(root, 'lean', 'land-legs.txt'), 'utf8').split(/\s+/).filter(Boolean);
/** Free Arm classes the trigger accepts: the Gen 2 names (CONFIRMED: accepted by pipelines 15 and 16) and the Gen 1 fallback. */
export const CLASSES = ['arm.medium.gen2', 'arm.large.gen2', 'arm.medium', 'arm.large'];

export class Usage extends Error {}

// ---------------------------------------------------------------------------------------------------------------- golden

/** The golden rows by op: { rates, constants, jobMap, credits: [...], ... }. */
export function loadGolden(path = GOLDEN) {
  const rows = readFileSync(path, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const byOp = {};
  for (const r of rows) (byOp[r.op] ??= []).push(r);
  return { rows, byOp, rates: byOp.rates[0].response, constants: byOp.constants[0].response, jobMap: byOp.jobMap[0].response.jobs, landJobs: byOp.jobMap[0].response.landJobs };
}

/** Lean `Fw.Ci.Provider.ghMatches`: a GitHub job name fits an `exact` rule, or a matrix rule (prefix, `, <vm>)` suffix, no overlap). */
export function ghMatches(rule, name) {
  if (rule.exact !== undefined) return rule.exact === name;
  return name.startsWith(rule.prefix) && name.endsWith(rule.suffix) && [...rule.prefix].length + [...rule.suffix].length <= [...name].length;
}

/** Lean `jobOfGithub`: the first job-map row a GitHub job name belongs to, or undefined. */
export const jobOfGithub = (g, name) => g.jobMap.find((r) => ghMatches(r.github, name));

/** Lean `savesCacheJob`: the CircleCI job has a `save_cache` step (a pilot job of the map that says so, or a land job of Lean `landJobs`). */
export const savesCacheJob = (g, job) => g.jobMap.some((r) => r.circleci === job && r.savesCache) || g.landJobs.includes(job);

/** Lean `digestJob`: the pilot job (CircleCI name) is judged by its premise digest. */
export const digestJob = (g, job) => g.jobMap.some((r) => r.circleci === job && r.digest);

/** Lean `classOfApi`: the API writes `arm-medium-gen2`, the config and the price list `arm.medium.gen2`. */
export const classOfApi = (name) => String(name).replaceAll('-', '.');

/** Lean `ofCircleStatus`. */
export function ofCircleStatus(status) {
  if (status === 'success') return 'pass';
  return ['failed', 'infrastructure_fail', 'timedout', 'error', 'failing', 'unauthorized'].includes(status) ? 'fail' : 'not-run';
}

/** Lean `ofGithubConclusion` (a missing conclusion is the empty string). */
export function ofGithubConclusion(c) {
  if (c === 'success') return 'pass';
  return ['failure', 'timed_out', 'startup_failure', 'action_required'].includes(c ?? '') ? 'fail' : 'not-run';
}

/** Lean `circleTerminal`. */
export const circleTerminal = (s) => ['success', 'failed', 'error', 'canceled', 'not_run', 'unauthorized', 'infrastructure_fail', 'timedout', 'terminated-unknown'].includes(s);

/** Lean `waitStep`: the exit code of a wait at one poll, or null while it goes on. */
export function waitStep({ statuses, waitedS, noWorkflowS, timeoutS }) {
  if (statuses.length === 0) return noWorkflowS <= waitedS ? 4 : timeoutS <= waitedS ? 3 : null;
  if (statuses.every(circleTerminal)) return statuses.every((x) => x === 'success') ? 0 : statuses.some((x) => ['failed', 'error', 'infrastructure_fail', 'timedout', 'unauthorized'].includes(x)) ? 1 : 4;
  return timeoutS <= waitedS ? 3 : null;
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

export function storageNow(g, rows, now) {
  const { windowMs, retentionDays: d } = g.constants;
  const byteDays = rows.filter((r) => r.at == null || now <= r.at + windowMs)
    .reduce((n, r) => n + BigInt(r.cache) * BigInt(d.cache) + BigInt(r.workspace) * BigInt(d.workspace) + BigInt(r.artifacts) * BigInt(d.artifact), 0n);
  return Number((byteDays * 1000n + 30n * 1000000000n - 1n) / (30n * 1000000000n));
}

export function storageCredits(g, milli) {
  const c = g.constants;
  return Math.floor((Math.max(0, milli - c.storageAllowMilli) * c.overageCreditsPerGbMonth + 999) / 1000);
}

/** Lean `verdictEq`: equal conclusions and, when both sides carry a digest, equal digests. */
export const verdictEq = (a, b) => a.conclusion === b.conclusion && (a.digest == null || b.digest == null || a.digest === b.digest);

/** Lean `verdict`: a digest job is judged by its digest alone (its step conclusion is `pass` on both sides), else `verdictEq`. */
export const verdict = (g, a, b) => (digestJob(g, a.job) ? a.digest != null && a.digest === b.digest : verdictEq(a, b));

/** Lean `compare`: { comparable: false, reason } or { comparable: true, finding, ratioPermille, queueGithubMs, queueCircleMs, credits }. */
export function compare(g, gh, cc) {
  if (gh.provider !== 'github' || cc.provider !== 'circleci') return { comparable: false, reason: 'providers' };
  if (gh.job !== cc.job) return { comparable: false, reason: 'job' };
  if (gh.sha !== cc.sha) return { comparable: false, reason: 'sha' };
  if (digestJob(g, gh.job) && (gh.digest == null || cc.digest == null)) return { comparable: false, reason: 'digest' };
  return { comparable: true, finding: !verdict(g, gh, cc), ratioPermille: gh.durMs === 0 ? null : Math.floor((cc.durMs * 1000) / gh.durMs),
    queueGithubMs: gh.queueMs, queueCircleMs: cc.queueMs, credits: credits(g, cc.class, cc.durMs) };
}

/** Lean `cacheSavedBytes`: what one `save_cache` step added to the cache. `save` is { kind: 'absent' | 'skipped' | 'stored', tenthsMiB }.
 *  The printed size is rounded to a tenth of a MiB, so one more tenth is added (an upper bound). */
export function cacheSavedBytes(save) {
  if (save.kind === 'absent' || save.kind === 'skipped') return 0;
  if (save.kind === 'stored') return Math.floor(((save.tenthsMiB + 1) * 1048576 + 9) / 10);
  throw new Error(`unknown cache save kind ${save.kind}`);
}

/** Lean `cachePipelineBytes`: the sum over the saves of a pipeline's jobs. */
export const cachePipelineBytes = (saves) => saves.reduce((n, s) => n + cacheSavedBytes(s), 0);

/** Lean `stops`: every reason the pilot stops, in the order cap, queue, storage. */
export function stops(g, i) {
  const c = g.constants;
  return [...(c.capMs <= i.durMs ? ['cap'] : []), ...(c.queueMaxMs < i.queueMs ? ['queue'] : []), ...(c.storageStopMilli < i.storageMilli ? ['storage'] : [])];
}

export function landStops(g, i) {
  const c = g.constants;
  return [...(c.capMs <= i.durMs ? ['cap'] : []), ...(c.queueMaxMs < i.queueMs ? ['queue'] : [])];
}

/** Lean `route`: github or circleci for one lane. */
export function route(g, i) {
  const r = g.rates.rates.find((x) => x.class === i.class);
  const affordable = !!r && r.free && r.platform === i.platform && Math.floor((i.estMs * r.creditsPerMin + 59999) / 60000) <= i.creditsLeft;
  return i.allow.includes(i.lane) && affordable && (i.platform !== 'macos' || i.ghDegraded) ? 'circleci' : 'github';
}

// ----------------------------------------------------------------------------------------------------- statuses and digests

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

export const ms = (iso) => { const t = Date.parse(iso ?? ''); return Number.isFinite(t) ? t : null; };
const span = (job, step, startMs, durMs, commit = '') => ({ tool: `circleci/${job}`, step, startMs, durMs: Math.max(0, durMs), exit: 0, commit, load: 0, host: 'ci' });

// --------------------------------------------------------------------------------------------------------- in-job timings

/** `timings.json` of a job: its spans (the span.sh lines) with the job, class, commit, digest and the bytes the job persisted to the workspace. */
export function timingsDoc({ spansText, job, cls, sha, digest, workspaceBytes = 0 }) {
  const spans = spansText.split('\n').filter(Boolean).flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
  return { schema: 'fw.circleci-timings/1', job, class: cls, sha, digest: digest ?? null, bytes: { workspace: workspaceBytes }, spans };
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

/** JSON.parse that accepts raw control characters inside strings (pipeline objects carry commit bodies with raw newlines). */
export function parseLoose(text) {
  try { return JSON.parse(text); } catch { /* escape raw control characters inside strings and parse again */ }
  let out = '', inStr = false, esc = false;
  for (const ch of text) {
    if (inStr && !esc && ch < ' ') { out += `\\u${ch.charCodeAt(0).toString(16).padStart(4, '0')}`; continue; }
    out += ch;
    if (esc) esc = false;
    else if (inStr && ch === '\\') esc = true;
    else if (ch === '"') inStr = !inStr;
  }
  return JSON.parse(out);
}

const isCircleHost = (url) => /(^|\.)circleci\.com$|(^|\.)circle-artifacts\.com$/.test(new URL(url).hostname);
const shown = (url) => { const u = new URL(url); return url.startsWith(API) ? url.slice(API.length) : `${u.host}${u.pathname}`; };

/** The one request path of every call (JSON and artifact bytes): the token is fetched by `getToken` inside each attempt and sent to
 *  CircleCI hosts only; a 429 waits Retry-After seconds (at most `retries` times); an error message never holds the token or a query. */
export async function request({ fetchFn = fetch, getToken = keychainToken, sleep = (s) => new Promise((r) => setTimeout(r, s * 1000)), retries = 3 }, method, url, { body, accept = 'application/json' } = {}) {
  for (let attempt = 0; ; attempt++) {
    const token = isCircleHost(url) ? getToken() : '';
    const res = await fetchFn(url, { method, headers: { ...(token ? { 'Circle-Token': token } : {}), Accept: accept, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
    if (res.status === 429 && attempt < retries) {
      const raw = res.headers?.get?.('retry-after');
      const ra = raw == null || raw === '' ? NaN : Number(raw);
      await sleep(Math.max(Number.isFinite(ra) ? ra : 60, 1));
      continue;
    }
    if (!res.ok) throw new Error(redact(`${method} ${shown(url)}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`, token));
    return res;
  }
}

/** One JSON API call (through `request`). */
export async function call(ctx, method, url, body) {
  const text = await (await request(ctx, method, url, { body })).text();
  return text ? parseLoose(text) : {};
}

/** The bytes of one artifact (through `request`: the same 429 handling). */
export async function callBytes(ctx, url) {
  return Buffer.from(await (await request(ctx, 'GET', url, { accept: '*/*' })).arrayBuffer());
}

/** Every item of a list endpoint: follows `next_page_token`, and fails loudly when `maxPages` pages were not enough. */
export async function listAll(ctx, url, { maxPages = 10 } = {}) {
  const items = [];
  let token = null;
  for (let page = 1; ; page++) {
    const r = await call(ctx, 'GET', token ? `${url}${url.includes('?') ? '&' : '?'}page-token=${encodeURIComponent(token)}` : url);
    items.push(...(r.items ?? []));
    token = r.next_page_token ?? null;
    if (!token) return items;
    if (page >= maxPages) throw new Error(`${shown(url)}: next_page_token still set after ${maxPages} pages`);
  }
}

// -------------------------------------------------------------------------------------------------------------- requests

/** The request that starts a pipeline for a branch (POST /project/{slug}/pipeline/run; the definition id is the project's
 *  pipeline definition). Returns { method, url, headers, body } with the token left out. */
export function triggerRequest({ slug, definitionId, branch, lane, cls, xcode, legs }) {
  const parameters = { lane };
  if ((lane === 'premise-tests' || lane === 'land') && cls) parameters.resource_class = cls;
  if (lane === 'land' && legs?.length) parameters.legs = legs.join(',');
  if (lane === 'webkit-sim' && xcode) parameters.xcode = xcode;
  return { method: 'POST', url: `${API}/project/${slug}/pipeline/run`, headers: { 'Circle-Token': '<redacted>', Accept: 'application/json', 'Content-Type': 'application/json' },
    body: { definition_id: definitionId, config: { branch }, checkout: { branch }, parameters } };
}

export const urls = {
  pipeline: (pipelineId) => `${API}/pipeline/${pipelineId}`,
  workflows: (pipelineId) => `${API}/pipeline/${pipelineId}/workflow`,
  jobs: (workflowId) => `${API}/workflow/${workflowId}/job`,
  job: (slug, n) => `${API}/project/${slug}/job/${n}`,
  /** API v1.1 job details: the only endpoint that lists the steps of a job and the URL of each step's output. */
  jobSteps: (slug, n) => `https://circleci.com/api/v1.1/project/${slug}/${n}`,
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

/** True for every pipeline whose trigger type is not `webhook` (the type a push makes). It reads neither the lane parameter nor the workflow list. */
export const isPilotPipeline = (p) => p?.trigger?.type !== 'webhook';

const TERMINAL = new Set(['success', 'failed', 'error', 'canceled', 'not_run', 'unauthorized', 'infrastructure_fail', 'timedout', 'terminated-unknown']);

/** Lean `Run` of a finished CircleCI job (detail of GET /project/{slug}/job/{n}); queue = queued_at (else created_at) to started_at. */
export function circleRun(detail, { sha, digest = null }) {
  const started = ms(detail.started_at), stopped = ms(detail.stopped_at), queuedAt = ms(detail.queued_at) ?? ms(detail.created_at);
  return { provider: 'circleci', job: detail.name, sha, conclusion: ofCircleStatus(detail.status), digest, class: classOfApi(detail.executor?.resource_class ?? ''),
    queueMs: started != null && queuedAt != null ? Math.max(0, started - queuedAt) : 0,
    durMs: Number.isFinite(detail.duration) ? detail.duration : started != null && stopped != null ? stopped - started : 0 };
}

/** Lean `Run`s of a GitHub run as `gh run view <id> --json databaseId,workflowName,headSha,createdAt,jobs` prints it, for the jobs the
 *  job map names (Lean `jobOfGithub`: a whole name, or a matrix name by prefix and VM); the first GitHub job of a row is the twin.
 *  `digests` maps a GitHub job name to the premiseDigest of its artifact. Queue = run createdAt to job startedAt. */
export function githubRuns(g, run, digests = {}) {
  const out = [];
  for (const j of run.jobs ?? []) {
    const m = jobOfGithub(g, j.name);
    if (!m || out.some((r) => r.job === m.circleci)) continue;
    const s = ms(j.startedAt), e = ms(j.completedAt), c = ms(run.createdAt);
    out.push({ provider: 'github', job: m.circleci, lane: m.lane, githubJob: j.name, sha: run.headSha ?? '', conclusion: ofGithubConclusion(j.conclusion), digest: digests[j.name] ?? null,
      class: '', queueMs: s != null && c != null ? Math.max(0, s - c) : 0, durMs: s != null && e != null ? Math.max(0, e - s) : 0 });
  }
  return out;
}

/** The GitHub artifact name that holds the premise results of a digest job (`engine (chromium)` -> `premises-chromium`), or null. */
export const premisesArtifact = (name) => { const m = /^engine \((.+)\)$/.exec(name); return m ? `premises-${m[1]}` : null; };

/** The digest of every digest job's GitHub artifact: downloads `premises-<engine>` of the run into `base` (unless it is there). */
export function githubDigests(g, run, base, download = ghDownload) {
  const digests = {};
  for (const j of run.jobs ?? []) {
    const m = jobOfGithub(g, j.name), art = premisesArtifact(j.name);
    if (!m?.digest || !art) continue;
    const dir = join(base, art);
    if (!existsSync(dir) && run.databaseId != null) { try { download(run.databaseId, art, dir); } catch { /* no artifact: the digest stays missing */ } }
    digests[j.name] = premiseDigest(dir);
  }
  return digests;
}

/** `gh run download <id> -n <artifact> -D <dir>`. */
export function ghDownload(runId, artifact, dir) {
  execFileSync('gh', ['run', 'download', String(runId), '-n', artifact, '-D', dir], { stdio: ['ignore', 'pipe', 'pipe'] });
}

// ------------------------------------------------------------------------------------------------------- cache saves of a job

/** The name CircleCI gives the `save_cache` step in the job steps. */
export const SAVE_STEP = 'Saving cache';

const UNIT_TENTHS_MIB = { B: 10 / 1048576, KiB: 10 / 1024, MiB: 10, GiB: 10 * 1024 };

/** Glue: the output text of a `Saving cache` step into a Lean `CacheSave`. The two outputs recorded on pipelines 15 and 16:
 *  "Skipping cache generation, cache already exists for key ..." (nothing uploaded) and "... Total size uploaded: 9.3 MiB". A text
 *  that is neither is an error: the bytes are not known, so the stop rule must not read a guess. */
export function parseCacheSave(text) {
  if (/Skipping cache generation/.test(text)) return { kind: 'skipped' };
  const m = /Total size uploaded:\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB)\b/.exec(text);
  if (m) return { kind: 'stored', tenthsMiB: Math.ceil(Number(m[1]) * UNIT_TENTHS_MIB[m[2]]) };
  throw new Error(`the save_cache step output is neither a skip nor a size: ${JSON.stringify(text.slice(0, 120))}`);
}

/** The Lean `CacheSave` of one job, from its steps (API v1.1) and the output of its save step. No save step (the job halted before
 *  it, or never reached it) is `absent`; a save step that failed is an error (what it uploaded is unknown). */
export async function readCacheSave(ctx, { slug, jobNumber }) {
  const d = await call(ctx, 'GET', urls.jobSteps(slug, jobNumber));
  const saves = (d.steps ?? []).flatMap((st) => st.actions ?? []).filter((a) => a.name === SAVE_STEP);
  if (saves.length === 0) return { kind: 'absent' };
  if (saves.length > 1) throw new Error(`job ${jobNumber}: ${saves.length} save_cache steps, expected at most one`);
  const a = saves[0];
  if (a.status !== 'success') {
    if (['not_run', 'canceled', 'queued', 'running'].includes(a.status)) return { kind: 'absent' };
    throw new Error(`job ${jobNumber}: the save_cache step ended ${a.status}; what it uploaded is unknown`);
  }
  if (!a.output_url) throw new Error(`job ${jobNumber}: the save_cache step has no output`);
  const parts = JSON.parse((await callBytes(ctx, a.output_url)).toString('utf8'));
  return parseCacheSave(parts.map((x) => x.message ?? '').join(''));
}

// ----------------------------------------------------------------------------------------------------------------- key check

/** The name CircleCI gives the clone step of a job. */
export const CHECKOUT_STEP = 'Checkout code';

/** Lean `usableKeyKind`: a checkout-key kind the clone can use. */
export const usableKeyKind = (kind) => kind === 'deploy-key' || kind === 'github-user-key';

/** Lean `checkoutOfStatus`: true (clone worked), false (clone failed), null (the status says nothing). */
export const checkoutOfStatus = (status) => (status === 'success' ? true : status === 'failed' ? false : null);

/** Lean `keyVerdict`: a readable key list decides (`keys` = usable keys, null when unreadable); an unreadable one falls back to the newest clone result. */
export function keyVerdict({ keys, checkout }) {
  if (keys != null) return keys > 0 ? 'ok' : 'missing';
  return checkout === true ? 'ok' : checkout === false ? 'missing' : 'unknown';
}

/** Lean `keyProceed`: a pipeline may start only on `ok`. */
export const keyProceed = (i) => keyVerdict(i) === 'ok';

/** Glue: the usable keys of GET /project/{slug}/checkout-key, or null when the list answers 403 (the token may not read it). Any other error is thrown. */
export async function readKeyList(ctx, { slug }) {
  try {
    return (await listAll(ctx, `${API}/project/${slug}/checkout-key`)).filter((k) => usableKeyKind(k.type)).length;
  } catch (e) {
    if (/HTTP 403/.test(e.message)) return null;
    throw e;
  }
}

/** Glue: the clone result of the newest pipeline whose `Checkout code` step finished (read-only: pipeline list, workflows, jobs, job steps).
 *  Looks at the newest `maxPipelines` pipelines of the project, any branch; null when none holds a finished clone. */
export async function readCloneResult(ctx, { slug, maxPipelines = 5 }) {
  const page = await call(ctx, 'GET', `${API}/project/${slug}/pipeline`);
  for (const p of (page.items ?? []).slice(0, maxPipelines)) {
    for (const wf of await listAll(ctx, urls.workflows(p.id))) {
      for (const j of await listAll(ctx, urls.jobs(wf.id))) {
        if (j.job_number == null) continue;
        let d;
        try { d = await call(ctx, 'GET', urls.jobSteps(slug, j.job_number)); } catch (e) { if (/HTTP 404/.test(e.message)) continue; throw e; }
        for (const a of (d.steps ?? []).flatMap((st) => st.actions ?? [])) {
          const c = a.name === CHECKOUT_STEP ? checkoutOfStatus(a.status) : null;
          if (c != null) return c;
        }
      }
    }
  }
  return null;
}

/** The read-only key check: only GETs, so a missing key costs no credits. The clone result is read only when the key list is unreadable
 *  (Lean `key_list_beats_clone`: a readable list ignores it). Returns { verdict, proceed, keys, checkout }. */
export async function keyCheck(ctx, { slug }) {
  const keys = await readKeyList(ctx, { slug });
  const checkout = keys == null ? await readCloneResult(ctx, { slug }) : null;
  return { verdict: keyVerdict({ keys, checkout }), proceed: keyProceed({ keys, checkout }), keys, checkout };
}

/** Exit code of a key check: 0 ok, 6 missing, 7 unknown. */
export const keyExit = (verdict) => (verdict === 'ok' ? 0 : verdict === 'missing' ? 6 : 7);

/** One line saying what to do about a key verdict that is not ok. */
export const keyAdvice = (r) => (r.verdict === 'missing'
  ? `no usable checkout key (${r.keys == null ? 'the key list is unreadable and the newest clone failed' : 'the key list holds none'}): add a deploy key or user key in Project Settings, SSH Keys; no pipeline was started`
  : 'cannot tell whether a checkout key exists (the key list answers 403 and no pipeline has finished a clone yet): no pipeline was started');

// ----------------------------------------------------------------------------------------------------------- storage ledger

/** The pilot's storage ledger (.local/circleci-ledger.json): { pipelines: { <id>: { artifacts, cache, workspace } } } in bytes. */
export function readLedger(path) {
  try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return { pipelines: {} }; }
}

export const ledgerBytes = (ledger, exceptId = '') => Object.entries(ledger.pipelines ?? {}).filter(([id]) => id !== exceptId).reduce((n, [, b]) => n + (b.artifacts ?? 0) + (b.cache ?? 0) + (b.workspace ?? 0), 0);

export const ledgerRows = (ledger, exceptId = '') => Object.entries(ledger.pipelines ?? {}).filter(([id]) => id !== exceptId)
  .map(([, b]) => ({ at: typeof b.at === 'number' && Number.isFinite(b.at) ? b.at : null, cache: b.cache ?? 0, workspace: b.workspace ?? 0, artifacts: b.artifacts ?? 0 }));

export const WINDOW_DAYS = 30;

export const storageSoFar = (ctx, exceptId = '', now = ctx.now?.() ?? Date.now()) =>
  (ctx.ledgerPath ? storageNow(ctx.golden ?? loadGolden(), ledgerRows(readLedger(ctx.ledgerPath), exceptId), now) : 0);

export function creditsSoFar(ctx, now = Date.now()) {
  if (!ctx.ledgerPath) return 0;
  const since = now - WINDOW_DAYS * 86400000;
  return Object.values(readLedger(ctx.ledgerPath).pipelines ?? {}).reduce((n, b) => n + (Number(b.at) >= since ? Number(b.credits) || 0 : 0), 0);
}

// ----------------------------------------------------------------------------------------------------------- the pilot

const sleepReal = (s) => new Promise((r) => setTimeout(r, s * 1000));

export async function pollOnce(ctx, { slug, pipelineId, now }) {
  const g = ctx.golden;
  const land = ctx.storageStop === false;
  const stored = land ? 0 : storageSoFar(ctx, pipelineId);
  const wfs = await listAll(ctx, urls.workflows(pipelineId));
  const jobs = [];
  for (const wf of wfs) {
    let list = [];
    try { list = await listAll(ctx, urls.jobs(wf.id)); } catch (e) { if (!/HTTP 404/.test(String(e?.message))) throw e; }
    for (const j of list) {
      let queueMs = 0, durMs = 0;
      if (j.job_number != null && (j.status === 'queued' || j.status === 'running')) {
        const d = await call(ctx, 'GET', urls.job(slug, j.job_number));
        const q = ms(d.queued_at) ?? ms(d.created_at), s = ms(d.started_at);
        queueMs = q == null ? 0 : (s ?? now) - q;
        durMs = s == null ? 0 : (ms(d.stopped_at) ?? now) - s;
      }
      jobs.push({ workflow: wf, name: j.name, status: j.status, number: j.job_number, stops: land ? landStops(g, { durMs, queueMs }) : stops(g, { durMs, queueMs, storageMilli: stored }) });
    }
  }
  return { workflows: wfs, jobs };
}

export async function waitPipeline(ctx, { slug, pipelineId, timeoutS = 3600, intervalS = MIN_POLL_S, noWorkflowS = 300 }) {
  const log = ctx.log ?? console.log;
  const step = Math.max(intervalS, ctx.minPollS ?? MIN_POLL_S);
  const t0 = ctx.now();
  for (;;) {
    const now = ctx.now();
    const p = await pollOnce(ctx, { slug, pipelineId, now });
    for (const j of p.jobs) {
      if (j.stops.length) {
        log(`STOP ${j.name}: ${j.stops.join(', ')} (Lean Fw.Ci.Provider.${ctx.storageStop === false ? 'landStops' : 'stops'}); cancelling its workflow`);
        await call(ctx, 'POST', urls.cancel(j.workflow.id));
        return { code: 5, ...p };
      }
    }
    log(`poll: ${p.workflows.length} workflow(s), jobs ${p.jobs.map((j) => `${j.name}=${j.status}`).join(' ') || 'none yet'}`);
    const code = waitStep({ statuses: p.workflows.map((w) => w.status), waitedS: Math.floor((now - t0) / 1000), noWorkflowS, timeoutS });
    if (code != null) return { code, ...p };
    await ctx.sleep(step);
  }
}

/** Download the artifacts of every finished job of the pipeline into `out/<job>/...` and write `out/run.json`
 *  ({schema, pipelineId, sha, runs: [Lean Run], spans, storage}). The commit is `vcs.revision` of GET /pipeline/{id}. The artifact path is
 *  checked: no `..`, no absolute path. Storage = artifact bytes + the cache bytes the save steps of the jobs uploaded (job steps, Lean
 *  `cachePipelineBytes`: a skipped or absent save counts 0) + the workspace bytes each job reports in timings.json, added to the
 *  ledger (`ctx.ledgerPath`) of all pilot pipelines. */
export async function fetchPipeline(ctx, { slug, pipelineId, out }) {
  const g = ctx.golden;
  mkdirSync(out, { recursive: true });
  const sha = (await call(ctx, 'GET', urls.pipeline(pipelineId))).vcs?.revision ?? '';
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error(`pipeline ${pipelineId} has no vcs.revision`);
  const runs = [], spans = [], lanes = [];
  const bytes = { artifacts: 0, cache: 0, workspace: 0 };
  const cacheSaves = [];
  for (const wf of await listAll(ctx, urls.workflows(pipelineId))) {
    for (const j of await listAll(ctx, urls.jobs(wf.id))) {
      // A job that never ran (`not_run`, e.g. the verdict job after a failed engine job) has no detail: GET /project/{slug}/job/{n} answers 404 (pipeline 261).
      if (j.job_number == null || !TERMINAL.has(j.status) || j.status === 'not_run') continue;
      const d = await call(ctx, 'GET', urls.job(slug, j.job_number));
      const dir = join(out, j.name);
      mkdirSync(dir, { recursive: true });
      let lanePath = null;
      let timingsPath = join(dir, 'timings.json'); // CircleCI keeps the absolute upload path (tmp/fw/artifacts/...) in the artifact path
      for (const a of await listAll(ctx, urls.artifacts(slug, j.job_number))) {
        const rel = String(a.path).replace(/^\/+/, '');
        if (rel.split('/').includes('..') || rel === '') throw new Error(`artifact path ${a.path} leaves the output directory`);
        const dest = join(dir, ...rel.split('/'));
        if (rel.split('/').pop() === 'timings.json') timingsPath = dest;
        if (rel.split('/').pop() === 'lane.json') lanePath = dest;
        if (!(dest + sep).startsWith(dir + sep)) throw new Error(`artifact path ${a.path} leaves the output directory`);
        const buf = await callBytes(ctx, a.url);
        mkdirSync(dirname(dest), { recursive: true });
        writeFileSync(dest, buf);
        bytes.artifacts += buf.length;
      }
      runs.push(circleRun(d, { sha, digest: digestJob(g, j.name) ? premiseDigest(dir) : null }));
      const lane = landLane(lanePath);
      if (lane) lanes.push({ job: j.name, conclusion: ofCircleStatus(d.status), ...lane });
      const started = ms(d.started_at), stopped = ms(d.stopped_at), queuedAt = ms(d.queued_at) ?? ms(d.created_at);
      let own = [], saved = {};
      try { const t = JSON.parse(readFileSync(timingsPath, 'utf8')); own = t.spans ?? []; saved = t.bytes ?? {}; } catch { /* no timings.json: the job died before finish */ }
      if (savesCacheJob(g, j.name)) cacheSaves.push({ job: j.name, number: j.job_number, ...(await readCacheSave(ctx, { slug, jobNumber: j.job_number })) });
      bytes.workspace += Number(saved.workspace) || 0;
      const lastEnd = own.reduce((m, s) => Math.max(m, s.startMs + s.durMs), started ?? 0);
      if (queuedAt != null && started != null) spans.push(span(j.name, 'queue', queuedAt, started - queuedAt, sha.slice(0, 7)));
      spans.push(...own);
      if (stopped != null) spans.push(span(j.name, 'upload (after the last step)', lastEnd, stopped - lastEnd, sha.slice(0, 7)));
      if (started != null && stopped != null) spans.push(span(j.name, 'job', started, stopped - started, sha.slice(0, 7)));
    }
  }
  bytes.cache = cachePipelineBytes(cacheSaves);
  const total = bytes.artifacts + bytes.cache + bytes.workspace;
  let ledger = { pipelines: {} };
  if (ctx.ledgerPath) {
    ledger = readLedger(ctx.ledgerPath);
    const spent = runs.reduce((n, r) => n + (credits(g, r.class, r.durMs) ?? 0), 0);
    ledger.pipelines = { ...ledger.pipelines, [pipelineId]: { ...bytes, credits: spent, at: ctx.now?.() ?? Date.now() } };
    mkdirSync(dirname(ctx.ledgerPath), { recursive: true });
    writeFileSync(ctx.ledgerPath, `${JSON.stringify(ledger, null, 2)}\n`);
  }
  const all = ctx.ledgerPath ? ledgerBytes(ledger) : total;
  const milli = storageNow(g, ctx.ledgerPath ? ledgerRows(ledger) : [{ at: null, ...bytes }], ctx.now?.() ?? Date.now());
  const doc = { schema: 'fw.circleci-run/1', pipelineId, sha, runs, lanes, spans, storage: { ...bytes, cacheSaves, bytes: total, ledgerBytes: all, milli, stops: stops(g, { durMs: 0, queueMs: 0, storageMilli: milli }) } };
  writeFileSync(join(out, 'run.json'), `${JSON.stringify(doc, null, 2)}\n`);
  return doc;
}

/** The lane record a land job writes ({leg, sha, digest, engine, rc}; .circleci/job.sh `land_suites`), or null when the file is absent
 *  or not that shape. The digest is the `LANE digest=` line of `fw checks`: the same value `.github/workflows/land.yml` prints in its
 *  `lane: sha=.. digest=..` step name, so the two providers' legs compare by `leg` and `digest`. */
export function landLane(path) {
  if (!path) return null;
  try {
    const j = JSON.parse(readFileSync(path, 'utf8'));
    if (typeof j.leg !== 'string' || typeof j.sha !== 'string' || typeof j.digest !== 'string') return null;
    return { leg: j.leg, sha: j.sha, digest: j.digest, engine: String(j.engine ?? ''), rc: Number(j.rc) };
  } catch { return null; }
}

/** Pair the runs by job and compare them with the Lean verdict: lines for print, and the exit code. */
export function comparePairs(g, ghRuns, ccRuns) {
  const rows = [];
  for (const m of g.jobMap) {
    const gh = ghRuns.find((r) => r.job === m.circleci), cc = ccRuns.find((r) => r.job === m.circleci);
    if (!gh || !cc) { if (gh || cc) rows.push({ job: m.circleci, unpaired: gh ? 'circleci' : 'github' }); continue; }
    rows.push({ job: m.circleci, githubJob: gh.githubJob, ...compare(g, gh, cc) });
  }
  const code = rows.some((r) => r.comparable === false || r.unpaired) ? 2 : rows.some((r) => r.finding) ? 1 : 0;
  return { rows, code };
}

export function renderComparison(rows) {
  const f = (r) => r.unpaired ? `${r.job}: only one side ran (missing: ${r.unpaired})`
    : !r.comparable ? `${r.job}: not a pair (${r.reason === 'digest' ? 'digest missing on a side' : r.reason})`
    : `${r.job}${r.githubJob && r.githubJob !== r.job ? ` (github: ${r.githubJob})` : ''}: ${r.finding ? 'FINDING verdicts differ' : 'verdicts equal'}; duration ${r.ratioPermille == null ? 'n/a' : `${(r.ratioPermille / 1000).toFixed(2)}x GitHub`}; queue github ${Math.round(r.queueGithubMs / 1000)}s (run start to job start), circleci ${Math.round(r.queueCircleMs / 1000)}s; credits ${r.credits ?? 'n/a (class not in the price list)'}`;
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
  for (const [name, url] of [['pipeline workflows', urls.workflows('<pipeline-id>')], ['workflow jobs', urls.jobs('<workflow-id>')], ['pipeline (commit)', urls.pipeline('<pipeline-id>')], ['job detail', urls.job(slug, '<job-number>')], ['job artifacts', urls.artifacts(slug, '<job-number>')], ['job steps (v1.1, the save_cache step)', urls.jobSteps(slug, '<job-number>')], ['cancel on stop', urls.cancel('<workflow-id>')]]) {
    log(`${name === 'cancel on stop' ? 'POST' : 'GET'} ${url}   (${name}; header Circle-Token: <redacted>)`);
  }
  const fx = loadFixture(fixture);
  const ctx = { golden, fetchFn: fixtureFetch(fx.api), getToken: () => 'fixture-token', sleep: async () => {}, now: () => Date.parse(fx.now), log, minPollS: 0 };
  const w = await waitPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, timeoutS: 10, intervalS: 0 });
  log(`fixture ${fixture}: wait exit ${w.code}`);
  if (w.code !== 0) return { wait: w };
  const out = tmp ?? mkdtempSync(join(tmpdir(), 'fwcircleci-'));
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out });
  const gh = githubRuns(golden, fx.github, fx.github.digests ?? {});
  const cmp = comparePairs(golden, gh, doc.runs);
  log(renderComparison(cmp.rows));
  log(`storage: ${doc.storage.bytes} bytes (artifacts ${doc.storage.artifacts}, cache ${doc.storage.cache}, workspace ${doc.storage.workspace}), ${doc.storage.milli} thousandths of a GB-month${doc.storage.stops.length ? `; STOP ${doc.storage.stops.join(',')}` : ''}`);
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
  '  trigger --lane premise-tests|webkit-sim|land --branch ci/<name> [--class arm.medium.gen2|arm.large.gen2] [--xcode V] [--legs a,b (land)] [--dry]',
  '  wait (--pipeline ID | --branch ci/<name> [--since EPOCH]) [--timeout S] [--interval S>=120] [--out DIR]',
  '  fetch --pipeline ID --out DIR      compare --github gh-run.json --circleci DIR/run.json [--json]',
  '  route --lane L --platform linux-arm|macos --class C --est-ms N --credits-left N [--allow a,b] [--gh-degraded]',
  '  key-check       read-only: is there a usable checkout key (exit 0 ok, 6 missing, 7 unknown); no pipeline is started',
  '  digest DIR      dry-run [--lane L] [--branch ci/x]',
].join('\n');

export async function main(argv, { root = ROOT, env = process.env, ctx: ctx0 = {}, log = console.log } = {}) {
  const [sub, ...rest] = argv[0] === 'circleci' ? argv.slice(1) : argv;
  const golden = ctx0.golden ?? loadGolden();
  try {
    if (sub === 'timings') {
      const o = flags(rest, { spans: 'v', out: 'v', job: 'v', class: 'v', sha: 'v', 'digest-from': 'v', 'workspace-bytes': 'v' });
      const doc = timingsDoc({ spansText: readFileSync(o.spans, 'utf8'), job: o.job, cls: o.class, sha: o.sha ?? '', digest: o['digest-from'] ? premiseDigest(o['digest-from']) : null, workspaceBytes: Number(o['workspace-bytes']) || 0 });
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
      const base = join(dirname(resolve(o.github)), 'gh-artifacts');
      const given = Object.fromEntries(Object.entries(gh.digestDirs ?? {}).map(([k, d]) => [k, premiseDigest(resolve(dirname(o.github), d))]));
      const digests = { ...githubDigests(golden, gh, base, ctx0.ghDownload ?? ghDownload), ...(gh.digests ?? {}), ...given };
      const cmp = comparePairs(golden, githubRuns(golden, gh, digests), JSON.parse(readFileSync(o.circleci, 'utf8')).runs);
      log(o.json ? JSON.stringify(cmp) : renderComparison(cmp.rows));
      return cmp.code;
    }
    if (sub === 'dry-run') {
      const o = flags(rest, { lane: 'v', branch: 'v', class: 'v', xcode: 'v', fixture: 'v' });
      for (const lane of o.lane ? [o.lane] : LANES.filter((l) => l !== 'land')) { // land has no recorded fixture: its proof is the live paired run
        if (!LANES.includes(lane)) throw new Usage(`unknown lane ${lane}; lanes: ${LANES.join(', ')}`);
        await dryRun({ golden, lane, branch: o.branch ?? 'ci/circleci-pilot', cls: o.class, xcode: o.xcode, fixture: o.fixture, log });
      }
      return 0;
    }
    const cfg = loadConfig(root, env);
    const need = (what) => { if (!cfg[what]) throw new Usage(`${what === 'slug' ? 'project slug' : 'pipeline definition id'} not set: FW_CIRCLECI_${what === 'slug' ? 'SLUG' : 'DEFINITION_ID'} or .local/circleci.json (docs/team/tools/circleci.md, step 5)`); return cfg[what]; };
    const ctx = { golden, fetchFn: fetch, getToken: keychainToken, sleep: sleepReal, now: Date.now, log, ledgerPath: join(root, '.local', 'circleci-ledger.json'), ...ctx0 };
    if (sub === 'key-check') {
      flags(rest, {});
      const r = await keyCheck(ctx, { slug: need('slug') });
      log(`circleci: key check ${r.verdict} (Lean Fw.Ci.Provider.keyVerdict; keys ${r.keys ?? 'unreadable'}, newest clone ${r.checkout ?? 'unseen'})`);
      if (!r.proceed) log(keyAdvice(r));
      return keyExit(r.verdict);
    }
    if (sub === 'trigger') {
      const o = flags(rest, { lane: 'v', branch: 'v', class: 'v', xcode: 'v', legs: 'v', dry: 'bool' });
      if (!LANES.includes(o.lane) || !/^ci\/[A-Za-z0-9._/-]+$/.test(o.branch ?? '')) throw new Usage(USAGE);
      const legs = o.legs ? o.legs.split(',').filter(Boolean) : [];
      if (o.lane === 'land' && (legs.length === 0 || legs.some((l) => !landLegs().includes(l)))) throw new Usage(`--legs must list land legs: ${landLegs().join(',')}`);
      if (o.lane !== 'land' && o.legs) throw new Usage('--legs is for --lane land only');
      if (o.class && !CLASSES.includes(o.class)) throw new Usage(`--class must be one of ${CLASSES.join(', ')} (no paid class)`);
      const req = triggerRequest({ slug: o.dry ? (cfg.slug || '<project-slug>') : need('slug'), definitionId: o.dry ? (cfg.definitionId || '<definition-id>') : need('definitionId'), branch: o.branch, lane: o.lane, cls: o.class, xcode: o.xcode, legs });
      if (o.dry) { log(`${req.method} ${req.url}`); log(JSON.stringify({ headers: req.headers, body: req.body }, null, 2)); return 0; }
      const k = await keyCheck(ctx, { slug: cfg.slug });
      if (!k.proceed) { log(keyAdvice(k)); return keyExit(k.verdict); }
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
        const list = await listAll(ctx, urls.pipelines(slug, o.branch), { maxPages: 5 });
        const since = o.since ? Number(o.since) * 1000 : 0;
        const p = list.find((x) => isPilotPipeline(x) && (ms(x.created_at) ?? 0) >= since);
        if (!p) { log(`circleci: no pilot pipeline (started through the API) for ${o.branch}${since ? ' since the given time' : ''}`); return 4; }
        pipelineId = p.id;
      }
      if (sub === 'fetch') {
        if (!o.out) throw new Usage('fetch needs --out DIR');
        const doc = await fetchPipeline(ctx, { slug, pipelineId, out: resolve(o.out) });
        log(`circleci: fetched ${doc.runs.length} job(s) to ${o.out}/run.json; storage ${doc.storage.milli} thousandths of a GB-month`);
        if (doc.storage.stops.length) { log(`STOP storage (Lean Fw.Ci.Provider.stops): the pilot ledger passed the limit`); return 5; }
        return 0;
      }
      const interval = Number(o.interval ?? MIN_POLL_S);
      if (!(interval >= MIN_POLL_S)) throw new Usage(`--interval must be at least ${MIN_POLL_S} s`);
      const w = await waitPipeline(ctx, { slug, pipelineId, timeoutS: Number(o.timeout ?? 3600), intervalS: interval });
      log(`circleci: pipeline ${pipelineId} ended with exit ${w.code} (0 pass, 1 fail, 3 timeout, 4 not run, 5 stop rule)`);
      if (o.out && w.code !== 3 && w.code !== 5) {
        const doc = await fetchPipeline(ctx, { slug, pipelineId, out: resolve(o.out) });
        log(`circleci: ${doc.runs.length} job(s) in ${o.out}/run.json; storage ${doc.storage.milli} thousandths of a GB-month`);
        if (doc.storage.stops.length) { log('STOP storage (Lean Fw.Ci.Provider.stops): the pilot ledger passed the limit'); return 5; }
      }
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
