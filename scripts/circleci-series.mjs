#!/usr/bin/env node
// circleci-series (task circleci-series): a sequential series of CircleCI `premise-tests` pipelines per resource class, started through
// the API trigger of scripts/circleci.mjs (a push starts nothing), and the reduction of their timings. This file is glue: requests,
// waiting, writing rows. Every decision (credit price list, stop rule, status maps) is read from scripts/circleci.mjs, which replays
// the Lean module Fw.Ci.Provider; the statistics below follow the Lean nearest-rank median `Fw.Obs.Timing.p50` (lean/Fw/Obs/Timing.lean:140)
// and extend it with the same rank rule at 95 percent. That extension is a TS stand-in (no Lean statement of p95 yet); the test pins both
// ranks to the Lean #guard values.
//
//   node scripts/circleci-series.mjs run --branch ci/<name> --runs 10 [--classes a,b] --out results/circleci-series --scratch DIR
//        [--config-root DIR]   (where .local/circleci.json lives, when this worktree has none)
//   node scripts/circleci-series.mjs insights --out results/circleci-series [--config-root DIR]   (billed credits per workflow run)
//   node scripts/circleci-series.mjs github --out results/circleci-series [--limit 20]            (stored GitHub land-lane runs)
//   node scripts/circleci-series.mjs summary --out results/circleci-series                       (summary.json and the table)
//
// Budget: at most MAX_RUNS pipelines in one invocation (the task's cap is 40 CircleCI runs in all, 20 per class; `run` also reads the rows already
// written and refuses to pass the cap). The token is read inside each request by scripts/circleci.mjs, never printed.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { API, CLASSES, MIN_POLL_S, call, credits, fetchPipeline, keyAdvice, keyCheck, keychainToken, listAll, loadConfig, loadGolden, ms, triggerRequest, urls, waitPipeline } from './circleci.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const ROOT = resolve(here, '..');
export const MAX_RUNS = 40;
const idsPath = join(ROOT, '.local', 'circleci-series-ids.json'); // { <pipeline number>: { pipelineId, workflowId } }, gitignored

// ------------------------------------------------------------------------------------------------------------ statistics

/** Nearest-rank percentile of integers: the ceil(pct*n/100)-th smallest (1-based); 0 for no values. pct 50 is Lean `p50`
 *  (rank50 n = ceil(n/2), the lower median); pct 95 uses the same rule. For n = 10, p95 is the 10th value, the maximum. */
export function nearestRank(xs, pct) {
  if (xs.length === 0) return 0;
  const sorted = [...xs].sort((a, b) => a - b);
  return sorted[Math.max(1, Math.ceil((pct * sorted.length) / 100)) - 1];
}
export const spread = (xs) => ({ n: xs.length, p50: nearestRank(xs, 50), p95: nearestRank(xs, 95), max: xs.length ? Math.max(...xs) : 0, min: xs.length ? Math.min(...xs) : 0 });

// ------------------------------------------------------------------------------------------------------------- one row

/** The per-run row of a finished pipeline: pipeline number, class, commit, the workflow wall time (workflow created to stopped), the
 *  queue of the pipeline (workflow created to the first job start), and per job its queue (queued_at to started_at), duration and
 *  the credits the Lean price list gives (INFERRED; `insights` adds the billed value, MEASURED). */
export function rowOf({ g, number, pipelineId, cls, workflow, runs, pipelineCreatedMs }) {
  const created = ms(workflow.created_at), stopped = ms(workflow.stopped_at);
  const jobs = runs.map((r) => ({ job: r.job, conclusion: r.conclusion, class: r.class, queueMs: r.queueMs, durMs: r.durMs, credits: credits(g, r.class || cls, r.durMs) }));
  return {
    number, class: cls, sha: runs[0]?.sha ?? '', status: workflow.status, // no pipeline or workflow ids in a row (public file): `idsPath` keeps them locally
    workflowWallMs: created != null && stopped != null ? stopped - created : null,
    pipelineCreatedMs, jobs,
    jobCredits: jobs.reduce((n, j) => n + (j.credits ?? 0), 0), billedCredits: null,
  };
}

// ----------------------------------------------------------------------------------------------------------- run series

const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));

function flags(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith('--')) throw new Error(`unexpected argument ${argv[i]}`);
    o[argv[i].slice(2)] = argv[i + 1]?.startsWith('--') || argv[i + 1] === undefined ? true : argv[++i];
  }
  return o;
}

const rowsDir = (out) => join(out, 'rows');
export const readRows = (out) => (existsSync(rowsDir(out)) ? readdirSync(rowsDir(out)).filter((f) => f.endsWith('.json')).sort().map((f) => JSON.parse(readFileSync(join(rowsDir(out), f), 'utf8'))) : []);

/** waitPipeline, but a 404 right after the trigger (the workflow is listed before its jobs are readable) is retried every 15 s, at most 12 times. */
async function waitRetry(ctx, args) {
  for (let n = 0; ; n++) {
    try { return await waitPipeline(ctx, args); } catch (e) { if (!/HTTP 404/.test(e.message) || n >= 12) throw e; await ctx.sleep(15); }
  }
}

async function runSeries(o) {
  const out = resolve(o.out ?? 'results/circleci-series'), scratch = resolve(o.scratch ?? join(ROOT, '.local', 'circleci-series'));
  const per = Number(o.runs ?? 10), classes = String(o.classes ?? 'arm.medium.gen2,arm.large.gen2').split(',');
  for (const c of classes) if (!CLASSES.includes(c)) throw new Error(`class ${c} is not a free class of the config`);
  const branch = String(o.branch ?? ''), adopt = o.adopt ?? null; // --adopt N: pipeline N (already started by an aborted driver) is run 1 of the first class
  if (!/^ci\/[A-Za-z0-9._/-]+$/.test(branch)) throw new Error('--branch ci/<name> is required');
  const done = readRows(out);
  const planned = per * classes.length;
  if (done.length + planned > MAX_RUNS) throw new Error(`budget: ${done.length} rows exist and ${planned} more would pass ${MAX_RUNS} runs`);
  const g = loadGolden();
  const cfg = loadConfig(o['config-root'] ? resolve(o['config-root']) : ROOT);
  if (!cfg.slug || !cfg.definitionId) throw new Error('no slug or definition id (.local/circleci.json or the FW_CIRCLECI_* variables)');
  const ctx = { golden: g, fetchFn: fetch, getToken: keychainToken, sleep, now: Date.now, log: (m) => console.log(m), ledgerPath: join(ROOT, '.local', 'circleci-ledger.json'), minPollS: MIN_POLL_S };
  const key = await keyCheck(ctx, { slug: cfg.slug });
  if (!key.proceed) throw new Error(keyAdvice(key));
  console.log(`series: key check ${key.verdict}`);
  mkdirSync(rowsDir(out), { recursive: true });
  let failures = 0;
  for (let i = 1; i <= per; i++) {
    for (const cls of classes) {
      if (failures >= 3) throw new Error('three failed pipelines in a row: stopping (budget guard)');
      const req = triggerRequest({ slug: cfg.slug, definitionId: cfg.definitionId, branch, lane: 'premise-tests', cls });
      const t0 = Date.now();
      let p;
      if (adopt && i === 1 && cls === classes[0]) {
        p = (await listAll(ctx, urls.pipelines(cfg.slug, branch), { maxPages: 5 })).find((x) => x.number === Number(adopt));
        if (!p) throw new Error(`--adopt: pipeline ${adopt} not found on ${branch}`);
      } else p = await call(ctx, req.method, req.url, req.body);
      console.log(`series: run ${i}/${per} ${cls}: pipeline number ${p.number}`);
      const w = await waitRetry(ctx, { slug: cfg.slug, pipelineId: p.id, timeoutS: 3600, intervalS: MIN_POLL_S });
      if (w.code === 5 || w.code === 3) throw new Error(`pipeline ${p.number}: wait exit ${w.code}`);
      const doc = await fetchPipeline(ctx, { slug: cfg.slug, pipelineId: p.id, out: join(scratch, `p${p.number}`) });
      const wf = (await listAll(ctx, urls.workflows(p.id)))[0];
      const row = rowOf({ g, number: p.number, pipelineId: p.id, cls, workflow: wf, runs: doc.runs, pipelineCreatedMs: ms(p.created_at) });
      row.series = { index: i, waitExit: w.code, startedAtMs: t0 };
      const ids = existsSync(idsPath) ? JSON.parse(readFileSync(idsPath, 'utf8')) : {};
      ids[p.number] = { pipelineId: p.id, workflowId: wf.id };
      mkdirSync(dirname(idsPath), { recursive: true });
      writeFileSync(idsPath, `${JSON.stringify(ids)}\n`);
      writeFileSync(join(rowsDir(out), `p${String(p.number).padStart(5, '0')}.json`), `${JSON.stringify(row, null, 2)}\n`);
      failures = row.status === 'success' ? 0 : failures + 1;
      console.log(`series: pipeline ${p.number} ${row.status}, wall ${row.workflowWallMs} ms`);
    }
  }
}

// ----------------------------------------------------------------------------------------------------------- insights

/** Billed credits per workflow run: GET /insights/{slug}/workflows/premise-tests/runs (credits_used), matched to rows by workflow id. */
async function insights(o) {
  const out = resolve(o.out ?? 'results/circleci-series');
  const cfg = loadConfig(o['config-root'] ? resolve(o['config-root']) : ROOT);
  const ctx = { golden: loadGolden(), fetchFn: fetch, getToken: keychainToken, sleep, now: Date.now, log: () => {} };
  const rows = readRows(out);
  const ids = existsSync(idsPath) ? JSON.parse(readFileSync(idsPath, 'utf8')) : {};
  const branch = String(o.branch ?? 'ci/circleci-series');
  const url = `${API}/insights/${cfg.slug}/workflows/premise-tests/runs?branch=${encodeURIComponent(branch)}&start-date=${new Date(Date.now() - 2 * 864e5).toISOString().slice(0, 10)}T00:00:00Z`;
  const items = await listAll(ctx, url);
  const byId = new Map(items.map((x) => [x.id, x]));
  let matched = 0;
  for (const r of rows) {
    const x = byId.get(ids[r.number]?.workflowId);
    if (!x || x.credits_used == null) continue;
    r.billedCredits = x.credits_used;
    r.insights = { durationS: x.duration, status: x.status };
    writeFileSync(join(rowsDir(out), `p${String(r.number).padStart(5, '0')}.json`), `${JSON.stringify(r, null, 2)}\n`);
    matched++;
  }
  console.log(`insights: ${items.length} workflow runs listed, ${matched} of ${rows.length} rows matched`);
}

// -------------------------------------------------------------------------------------------------------------- github

const GH_JOBS = ['engine (chromium)', 'engine (playwright-webkit)', 'verdict'];

/** The twin facts of one GitHub run (gh run view --json): job durations (completed - started) and the queue (run created to job started). */
export function ghRow(run) {
  const created = ms(run.createdAt);
  const jobs = {};
  for (const j of run.jobs ?? []) {
    if (!GH_JOBS.includes(j.name)) continue;
    const s = ms(j.startedAt), e = ms(j.completedAt);
    jobs[j.name] = { conclusion: j.conclusion, durMs: s != null && e != null ? e - s : null, queueMs: s != null && created != null ? Math.max(0, s - created) : null };
  }
  const ends = Object.values(run.jobs ?? []).map((j) => ms(j.completedAt)).filter((x) => x != null);
  return { runId: run.databaseId, event: run.event, branch: run.headBranch, createdAt: run.createdAt, conclusion: run.conclusion, wallMs: ends.length && created != null ? Math.max(...ends) - created : null, jobs };
}

/** The stored GitHub runs of the workflow in which both engine jobs ran (a push whose lane inputs equal main's skips the whole workflow,
 *  and a successful-looking push run then has no engine job): the newest `limit`, any branch, any event, newest first. */
function github(o) {
  const out = resolve(o.out ?? 'results/circleci-series'), limit = Number(o.limit ?? 20);
  const list = JSON.parse(execFileSync('gh', ['run', 'list', '--workflow', 'premise-tests.yml', '--status', 'success', '--limit', '300', '--json', 'databaseId'], { encoding: 'utf8' }));
  const rows = [];
  for (const r of list) {
    if (rows.length >= limit) break;
    const run = JSON.parse(execFileSync('gh', ['run', 'view', String(r.databaseId), '--json', 'databaseId,event,headBranch,conclusion,createdAt,jobs'], { encoding: 'utf8' }));
    const row = ghRow(run);
    if (['engine (chromium)', 'engine (playwright-webkit)'].every((n) => row.jobs[n]?.conclusion === 'success')) rows.push(row);
  }
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, 'github-runs.json'), `${JSON.stringify({ schema: 'fw.circleci-series-github/1', workflow: 'premise-tests', runner: 'ubuntu-24.04-arm', selection: `newest ${limit} successful runs (any branch, any event) in which both engine jobs ran`, runs: rows }, null, 2)}\n`);
  console.log(`github: ${rows.length} runs`);
}

// ------------------------------------------------------------------------------------------------------------- summary

const JOBS = [['engine-chromium', 'engine (chromium)'], ['engine-playwright-webkit', 'engine (playwright-webkit)'], ['verdict', 'verdict']];

/** summary.json: per CircleCI class and per GitHub, spreads of workflow wall time, of every job's duration and queue, and credits. */
export function summarize(rows, gh) {
  const classes = {};
  for (const cls of [...new Set(rows.map((r) => r.class))].sort()) {
    const rs = rows.filter((r) => r.class === cls && r.status === 'success');
    const s = { runs: rows.filter((r) => r.class === cls).length, succeeded: rs.length, pipelines: rows.filter((r) => r.class === cls).map((r) => r.number),
      workflowWallMs: spread(rs.map((r) => r.workflowWallMs).filter((x) => x != null)), jobs: {}, jobCredits: spread(rs.map((r) => r.jobCredits)), billedCredits: spread(rs.map((r) => r.billedCredits).filter((x) => x != null)),
      billedCreditsTotal: rs.every((r) => r.billedCredits != null) ? rs.reduce((n, r) => n + r.billedCredits, 0) : null, jobCreditsTotal: rs.reduce((n, r) => n + r.jobCredits, 0) };
    for (const [name] of JOBS) {
      const js = rs.map((r) => r.jobs.find((j) => j.job === name)).filter(Boolean);
      s.jobs[name] = { dur: spread(js.map((j) => j.durMs)), queue: spread(js.map((j) => j.queueMs)) };
    }
    s.queueEngine = spread(rs.flatMap((r) => r.jobs.filter((j) => j.job.startsWith('engine-')).map((j) => j.queueMs)));
    classes[cls] = s;
  }
  let github = null;
  if (gh) {
    const rs = gh.runs.filter((r) => r.conclusion === 'success');
    github = { runs: rs.length, runIds: rs.map((r) => r.runId), wallMs: spread(rs.map((r) => r.wallMs).filter((x) => x != null)), jobs: {} };
    for (const [name, ghName] of JOBS) {
      const js = rs.map((r) => r.jobs[ghName]).filter((j) => j && j.durMs != null && j.conclusion === 'success');
      github.jobs[name] = { dur: spread(js.map((j) => j.durMs)), queue: spread(js.map((j) => j.queueMs ?? 0)) };
    }
    github.queueEngine = spread(rs.flatMap((r) => ['engine (chromium)', 'engine (playwright-webkit)'].map((n) => r.jobs[n]?.queueMs).filter((x) => x != null)));
  }
  return { schema: 'fw.circleci-series-summary/1', percentile: 'nearest rank, ceil(pct*n/100)-th smallest (Lean Fw.Obs.Timing.p50 rule); at n = 10, p95 = max', classes, github };
}

function summary(o) {
  const out = resolve(o.out ?? 'results/circleci-series');
  const gh = existsSync(join(out, 'github-runs.json')) ? JSON.parse(readFileSync(join(out, 'github-runs.json'), 'utf8')) : null;
  const doc = summarize(readRows(out), gh);
  writeFileSync(join(out, 'summary.json'), `${JSON.stringify(doc, null, 2)}\n`);
  const s = (x) => `${(x.p50 / 1000).toFixed(1)} / ${(x.p95 / 1000).toFixed(1)} / ${(x.max / 1000).toFixed(1)}`;
  for (const [cls, c] of Object.entries(doc.classes)) {
    console.log(`${cls}: ${c.succeeded}/${c.runs} ok; wall p50/p95/max s ${s(c.workflowWallMs)}; engine queue ${s(c.queueEngine)}; credits job-sum ${c.jobCredits.p50}/${c.jobCredits.max}, billed ${c.billedCredits.n ? `${c.billedCredits.p50}/${c.billedCredits.max}` : 'n/a'}`);
    for (const [n, j] of Object.entries(c.jobs)) console.log(`  ${n}: dur ${s(j.dur)}; queue ${s(j.queue)}`);
  }
  if (doc.github) {
    console.log(`github: ${doc.github.runs} runs; wall ${s(doc.github.wallMs)}; engine queue ${s(doc.github.queueEngine)}`);
    for (const [n, j] of Object.entries(doc.github.jobs)) console.log(`  ${n}: dur ${s(j.dur)}; queue ${s(j.queue)}`);
  }
}

async function main(argv) {
  const [sub, ...rest] = argv, o = flags(rest);
  if (sub === 'run') return runSeries(o);
  if (sub === 'insights') return insights(o);
  if (sub === 'github') return github(o);
  if (sub === 'summary') return summary(o);
  throw new Error('usage: circleci-series.mjs run|insights|github|summary (see the header)');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { await main(process.argv.slice(2)); } catch (e) { console.error(`circleci-series: ${e.message}`); process.exitCode = 1; }
}
