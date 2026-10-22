// scripts/circleci.test.mjs: the CircleCI glue against the Lean golden (packages/contracts/golden/ci/provider.jsonl, Lean
// Fw.Ci.Provider), the recorded-shape fixtures and the static facts of .circleci/. Run: node --test scripts/circleci.test.mjs
// No network, no Keychain: the API is a fixture and the token is a fake.
import { strict as assert } from 'node:assert';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir, userInfo } from 'node:os';
import { delimiter, dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { creditsSoFar, ledgerRows, storageCredits, storageNow, storageSoFar, landLane, landLegs, CHECKOUT_STEP, checkoutOfStatus, keyAdvice, keyCheck, keyExit, keyProceed, keyVerdict, readCloneResult, readKeyList, usableKeyKind, cachePipelineBytes, cacheSavedBytes, classOfApi, parseCacheSave, readCacheSave, savesCacheJob, API, MIN_POLL_S, ROOT, call, callBytes, comparePairs, compare, credits, digestJob, dryRun, fetchPipeline, fixtureFetch, githubDigests, githubRuns, isPilotPipeline, jobOfGithub, listAll, loadFixture, loadGolden, main, ofCircleStatus, ofGithubConclusion, parseLoose, premiseDigest, premisesArtifact, readLedger, redact, renderComparison, route, stops, landStops, storageMilli, timingsDoc, triggerRequest, urls, waitPipeline, waitStep } from './circleci.mjs';

const g = loadGolden();
const here = dirname(fileURLToPath(import.meta.url));
const rowsOf = (op) => g.byOp[op] ?? [];
const toRun = (r) => ({ ...r, class: r.class });

test('the golden has every op the glue replays, and no more', () => {
  assert.deepEqual([...new Set(g.rows.map((r) => r.op))].sort(), ['cachePipeline', 'cacheSaved', 'checkoutStatus', 'circleStatus', 'classOfApi', 'compare', 'constants', 'credits', 'ghJob', 'githubConclusion', 'jobMap', 'keyCheck', 'keyKind', 'landStop', 'rates', 'route', 'stop', 'storage', 'storageCredits', 'storageNow', 'wait']);
  assert.ok(g.rows.length >= 140);
});

test('key check: every golden row (Lean keyVerdict, keyProceed), and the kind and clone-status maps', () => {
  assert.equal(rowsOf('keyCheck').length, 7);
  for (const r of rowsOf('keyCheck')) {
    const i = { keys: r.request.keys, checkout: r.request.checkout };
    assert.equal(keyVerdict(i), r.response.verdict, r.name);
    assert.equal(keyProceed(i), r.response.proceed, r.name);
  }
  for (const r of rowsOf('keyKind')) assert.equal(usableKeyKind(r.request.kind), r.response.usable, r.name);
  for (const r of rowsOf('checkoutStatus')) assert.equal(checkoutOfStatus(r.request.status), r.response.clone, r.name);
});

test('credits: every golden row', () => {
  for (const r of rowsOf('credits')) assert.equal(credits(g, r.request.class, r.request.durMs), r.response.credits, r.name);
});

test('storage: every golden row', () => {
  for (const r of rowsOf('storage')) assert.equal(storageMilli(r.request.bytes, r.request.days), r.response.milli, r.name);
});

test('storageNow and storageCredits: every golden row', () => {
  assert.ok(rowsOf('storageNow').length >= 10);
  for (const r of rowsOf('storageNow')) assert.equal(storageNow(g, r.request.rows, r.request.now), r.response.milli, r.name);
  for (const r of rowsOf('storageCredits')) assert.equal(storageCredits(g, r.request.milli), r.response.credits, r.name);
});

test('storageSoFar: the ledger at retention within the 30-day window; a pipeline with no time counts; no golden in ctx loads it', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fwwin-'));
  const ledgerPath = join(dir, 'ledger.json');
  const now = Date.parse('2026-10-22T00:00:00Z');
  const day = 86400000;
  writeFileSync(ledgerPath, JSON.stringify({ pipelines: {
    old: { artifacts: 0, cache: 1000000000, workspace: 0, at: now - 30 * day - 1 },
    edge: { artifacts: 0, cache: 1000000000, workspace: 0, at: now - 30 * day },
    untimed: { artifacts: 1000000000, cache: 0, workspace: 0 },
  } }));
  assert.equal(storageSoFar({ ledgerPath, golden: g }, '', now), 500 + 1000);
  assert.equal(storageSoFar({ ledgerPath }, '', now), 1500);
  assert.equal(storageSoFar({ ledgerPath, golden: g }, 'untimed', now), 500);
  assert.equal(storageSoFar({ ledgerPath, golden: g }, '', now + 1), 1000);
  assert.equal(storageSoFar({ golden: g }, '', now), 0);
  assert.deepEqual(ledgerRows({ pipelines: { a: { cache: 5, at: 7 }, b: { workspace: 3, at: 'x' } } }), [
    { at: 7, cache: 5, workspace: 0, artifacts: 0 }, { at: null, cache: 0, workspace: 3, artifacts: 0 }]);
});

test('compare: every golden row', () => {
  for (const r of rowsOf('compare')) {
    const got = compare(g, toRun(r.request.github), toRun(r.request.circleci));
    assert.deepEqual(got, r.response, r.name);
  }
});

test('stop: every golden row', () => {
  for (const r of rowsOf('stop')) {
    const got = stops(g, r.request);
    assert.deepEqual(got, r.response.reasons, r.name);
    assert.equal(got.length > 0, r.response.stop, r.name);
  }
});

test('landStop: every golden row; storage is never a reason', () => {
  assert.ok(rowsOf('landStop').length >= 9);
  for (const r of rowsOf('landStop')) {
    const got = landStops(g, r.request);
    assert.deepEqual(got, r.response.reasons, r.name);
    assert.ok(!got.includes('storage'), r.name);
  }
});

test('classOfApi: every golden row (the API writes dashes, the price list dots)', () => {
  assert.ok(rowsOf('classOfApi').length >= 6);
  for (const r of rowsOf('classOfApi')) assert.equal(classOfApi(r.request.name), r.response.class, r.name);
});

test('circleStatus and githubConclusion: every golden row; only success passes', () => {
  assert.ok(rowsOf('circleStatus').length >= 10 && rowsOf('githubConclusion').length >= 8);
  for (const r of rowsOf('circleStatus')) assert.equal(ofCircleStatus(r.request.status), r.response.conclusion, r.name);
  for (const r of rowsOf('githubConclusion')) assert.equal(ofGithubConclusion(r.request.conclusion || null), r.response.result, r.name);
  assert.equal(ofGithubConclusion(undefined), 'not-run');
});

test('wait: every golden row (the exit code rule)', () => {
  for (const r of rowsOf('wait')) assert.equal(waitStep(r.request), r.response.exit, r.name);
});

test('ghJob: every golden row; the GitHub name rule is prefix + vm for the sim matrix, the whole name otherwise', () => {
  for (const r of rowsOf('ghJob')) {
    const row = jobOfGithub(g, r.request.name);
    assert.equal(row?.circleci ?? null, r.response.circleci, r.name);
    assert.equal(row?.lane ?? null, r.response.lane, r.name);
    assert.equal(row ? digestJob(g, row.circleci) : null, r.response.digest, r.name);
  }
  const names = g.jobMap.map((r) => r.circleci);
  assert.equal(new Set(names).size, names.length);
  assert.deepEqual(g.jobMap.find((r) => r.circleci === 'webkit-sim').github, { prefix: 'sim (original,', vm: 'v1', suffix: ', v1)' });
});

test('route: every golden row', () => {
  for (const r of rowsOf('route')) assert.equal(route(g, r.request), r.response.provider, r.name);
});

test('the pilot lanes only use classes the Lean price list marks free', () => {
  const cfg = readFileSync(join(ROOT, '.circleci', 'config.yml'), 'utf8');
  const free = new Set(g.rates.rates.filter((r) => r.free).map((r) => r.class));
  for (const m of cfg.matchAll(/enum: \[([^\]]+)\]/g)) for (const c of m[1].split(',').map((x) => x.trim())) if (/^(arm|m4pro)\./.test(c)) assert.ok(free.has(c), `${c} is not a free class`);
  assert.match(cfg, /resource_class: m4pro\.medium/);
  assert.ok(!/xlarge|m4pro\.large|arm\.(xlarge|2xlarge)/.test(cfg), 'no paid resource class');
});

test('every CircleCI job of the job map is a job of the config, and every workflow is guarded on ci/ and on the lane parameter', () => {
  const cfg = readFileSync(join(ROOT, '.circleci', 'config.yml'), 'utf8');
  for (const m of g.jobMap) assert.ok(cfg.includes(`name: ${m.circleci}`) || new RegExp(`^  ${m.circleci}:`, 'm').test(cfg), `job ${m.circleci}`);
  const whens = [...cfg.matchAll(/^    when: (.*)$/gm)].map((x) => x[1]);
  assert.equal(whens.length, 2);
  for (const w of whens) { assert.match(w, /pipeline\.git\.branch starts-with "ci\/"/); assert.match(w, /pipeline\.parameters\.lane == "/); }
  // the Lake cache is the land job's alone (test 'land lane: the Lake cache ...'); the pilot jobs keep the pnpm store only
  const pilot = cfg.slice(cfg.indexOf('\njobs:'), cfg.indexOf('\n  land:')).replace(/^ *#.*$/gm, '');
  assert.ok(!/save_cache[\s\S]*lake/i.test(pilot), 'no Lake cache in the pilot jobs');
});

test('job.sh and node-install.sh parse; job.sh handles every step the config calls', () => {
  for (const f of ['job.sh', 'node-install.sh']) execFileSync('sh', ['-n', join(ROOT, '.circleci', f)]);
  const cfg = readFileSync(join(ROOT, '.circleci', 'config.yml'), 'utf8');
  const job = readFileSync(join(ROOT, '.circleci', 'job.sh'), 'utf8');
  for (const m of cfg.matchAll(/job\.sh (since|[a-z-]+)/g)) assert.ok(new RegExp(`^  ${m[1]}[ )]`, 'm').test(job), `step ${m[1]}`);
});

test('job.sh sim-run takes the exit status of node, not of a pipe (round 2 finding 1)', () => {
  const job = readFileSync(join(ROOT, '.circleci', 'job.sh'), 'utf8');
  const body = job.slice(job.indexOf('sim_run()'), job.indexOf('sim_delete()'));
  const node = body.split('\n').find((l) => l.includes('node src/cli.mjs determinism'));
  assert.ok(node, 'the determinism command is in sim_run');
  assert.ok(!node.includes('|'), 'no pipe after node: `$?` would be the exit status of the last command of the pipe');
  assert.match(node, /> out\/v1-session-1\.md 2> out\/v1-session-1\.log$/);
  assert.ok(body.indexOf('rc=$?') > body.indexOf(node), 'rc is read right after node');
});

test('triggerRequest: the exact request, the token left out', () => {
  const r = triggerRequest({ slug: 's/l/u', definitionId: 'd1', branch: 'ci/x', lane: 'premise-tests', cls: 'arm.large.gen2' });
  assert.equal(r.method, 'POST');
  assert.equal(r.url, `${API}/project/s/l/u/pipeline/run`);
  assert.deepEqual(r.body, { definition_id: 'd1', config: { branch: 'ci/x' }, checkout: { branch: 'ci/x' }, parameters: { lane: 'premise-tests', resource_class: 'arm.large.gen2' } });
  assert.equal(r.headers['Circle-Token'], '<redacted>');
  assert.deepEqual(triggerRequest({ slug: 's', definitionId: 'd', branch: 'ci/x', lane: 'webkit-sim', cls: 'arm.large.gen2', xcode: '27.0.1' }).body.parameters, { lane: 'webkit-sim', xcode: '27.0.1' });
});

test('call: the token goes in the header only, 429 waits Retry-After, errors are redacted', async () => {
  const seen = [];
  const sleeps = [];
  const resp = (status, body, h = {}) => ({ status, ok: status < 400, headers: { get: (k) => h[k.toLowerCase()] ?? null }, text: async () => body });
  let n = 0;
  const fetchFn = async (url, init) => { seen.push({ url, init }); n++; return n === 1 ? resp(429, 'slow down', { 'retry-after': '7' }) : resp(200, '{"ok":true}'); };
  const out = await call({ fetchFn, getToken: () => 'SECRET', sleep: async (s) => sleeps.push(s) }, 'GET', `${API}/x`);
  assert.deepEqual(out, { ok: true });
  assert.deepEqual(sleeps, [7]);
  assert.equal(seen.length, 2);
  for (const s of seen) { assert.equal(s.init.headers['Circle-Token'], 'SECRET'); assert.ok(!s.url.includes('SECRET')); }
  await assert.rejects(call({ fetchFn: async () => resp(500, 'boom SECRET boom'), getToken: () => 'SECRET', sleep: async () => {} }, 'GET', `${API}/y`), (e) => !e.message.includes('SECRET') && e.message.includes('<redacted>'));
  assert.equal(redact('a SECRET b SECRET', 'SECRET'), 'a <redacted> b <redacted>');
});

test('call: gives up after the retries of a persistent 429', async () => {
  const resp = { status: 429, ok: false, headers: { get: () => null }, text: async () => 'no' };
  const sleeps = [];
  await assert.rejects(call({ fetchFn: async () => resp, getToken: () => 't', sleep: async (s) => sleeps.push(s), retries: 2 }, 'GET', `${API}/z`), /HTTP 429/);
  assert.deepEqual(sleeps, [60, 60]);
});

test('the token is read from the Keychain with the service name in argv, never printed', () => {
  const src = readFileSync(join(here, 'circleci.mjs'), 'utf8');
  assert.match(src, /execFileSync\('security', \['find-generic-password', '-s', KEYCHAIN_SERVICE, '-w'\]/);
  assert.ok(!/console\.(log|error)\([^)]*[tT]oken\)/.test(src), 'no console call prints a token variable');
  assert.ok(!/env\.[A-Z_]*TOKEN/.test(src), 'no token from the environment');
});

const ctxOf = (fx, extra = {}) => { const sleeps = []; return { sleeps, ctx: { golden: g, fetchFn: fixtureFetch(fx.api), getToken: () => 'fixture-token', sleep: async (s) => sleeps.push(s), now: () => Date.parse(fx.now), log: () => {}, ...extra } }; };

const wfRoute = (fx) => `GET /pipeline/${fx.pipelineId}/workflow`;
const wfIdOf = (fx) => fx.api.routes[wfRoute(fx)].items[0].id;
const jobNo = (fx, name) => fx.api.routes[`GET /workflow/${wfIdOf(fx)}/job`].items.find((j) => j.name === name).job_number;

test('wait: a finished pipeline of the fixture ends at once with exit 0', async () => {
  const fx = loadFixture('premise-tests');
  const { ctx } = ctxOf(fx);
  assert.equal((await waitPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, intervalS: MIN_POLL_S })).code, 0);
});

test('wait: polls no faster than 120 s whatever interval is asked', async () => {
  const fx = loadFixture('premise-tests');
  let polls = 0;
  const routes = { ...fx.api.routes };
  const wf = routes[wfRoute(fx)];
  const base = fixtureFetch({ ...fx.api, routes });
  const fetchFn = async (url, init) => {
    if (String(url).endsWith(`/pipeline/${fx.pipelineId}/workflow`) && ++polls === 1) return { status: 200, ok: true, headers: { get: () => null }, text: async () => JSON.stringify({ items: [{ ...wf.items[0], status: 'running' }] }) };
    return base(url, init);
  };
  const { ctx, sleeps } = ctxOf(fx, { fetchFn });
  const r = await waitPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, intervalS: 5 });
  assert.equal(r.code, 0);
  assert.deepEqual(sleeps, [MIN_POLL_S]);
});

test('wait: no workflow after the grace time is exit 4, a timeout exit 3', async () => {
  const empty = { routes: { 'GET /pipeline/p/workflow': { items: [] } } };
  let t = 0;
  const mk = () => ({ golden: g, fetchFn: fixtureFetch(empty), getToken: () => 't', sleep: async () => { t += 130 * 1000; }, now: () => t, log: () => {} });
  assert.equal((await waitPipeline(mk(), { slug: 's', pipelineId: 'p', noWorkflowS: 300, timeoutS: 99999 })).code, 4);
  t = 0;
  assert.equal((await waitPipeline(mk(), { slug: 's', pipelineId: 'p', noWorkflowS: 99999, timeoutS: 200 })).code, 3);
});

test('wait: a queue over 10 minutes stops the pilot and cancels the workflow', async () => {
  const fx = loadFixture('webkit-sim-queued');
  const calls = [];
  const base = fixtureFetch(fx.api);
  const { ctx } = ctxOf(fx, { fetchFn: async (u, i) => { calls.push(`${i?.method ?? 'GET'} ${String(u).replace(API, '')}`); return base(u, i); } });
  const r = await waitPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId });
  assert.equal(r.code, 5);
  assert.ok(calls.includes('POST /workflow/wf-3/cancel'));
});

test('wait: a failed workflow is exit 1', async () => {
  const fx = loadFixture('premise-tests');
  const api = JSON.parse(JSON.stringify(fx.api));
  api.routes[wfRoute(fx)].items[0].status = 'failed';
  const { ctx } = ctxOf(fx, { fetchFn: fixtureFetch(api) });
  assert.equal((await waitPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId })).code, 1);
});

test('fetch + compare over the premise-tests fixture: equal verdicts, no finding, spans in the span format', async () => {
  const fx = loadFixture('premise-tests');
  const { ctx } = ctxOf(fx);
  const out = mkdtempSync(join(tmpdir(), 'fwcc-'));
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out });
  assert.equal(doc.sha, fx.sha);
  assert.match(doc.sha, /^[0-9a-f]{40}$/);
  for (const r of doc.runs) assert.equal(r.sha, fx.sha);
  assert.deepEqual(doc.runs.map((r) => r.job), ['engine-chromium', 'engine-playwright-webkit', 'verdict']);
  assert.deepEqual(doc.runs.map((r) => r.durMs), [38791, 51645, 10149]);
  assert.deepEqual(doc.runs.map((r) => r.queueMs), [40259, 13929, 33868]);
  const gh = githubRuns(g, fx.github, fx.github.digests);
  const cmp = comparePairs(g, gh, doc.runs);
  assert.equal(cmp.code, 0);
  assert.deepEqual(cmp.rows.map((r) => r.credits), [4, 6, 2]);
  assert.match(renderComparison(cmp.rows), /engine-chromium \(github: engine \(chromium\)\): verdicts equal; duration 0\.99x GitHub/);
  const steps = new Set(doc.spans.filter((s) => s.tool === 'circleci/engine-chromium').map((s) => s.step));
  for (const s of ['queue', 'checkout', 'node', 'pnpm', 'cache restore', 'deps install', 'test', 'upload (after the last step)', 'job']) assert.ok(steps.has(s), s);
  // the verdict job's own `fw premises` span (tool fw) joins the file with its keys in another order
  for (const s of doc.spans) assert.deepEqual(Object.keys(s).sort(), ['commit', 'durMs', 'exit', 'host', 'load', 'startMs', 'step', 'tool']);
  assert.equal(JSON.parse(readFileSync(join(out, 'run.json'), 'utf8')).schema, 'fw.circleci-run/1');
  assert.equal(doc.storage.stops.length, 0);
});

test('the recorded arm.large.gen2 pipeline: same digests, credits at 12 a minute, class name mapped from the API form', async () => {
  const fx = loadFixture('premise-tests-large');
  const { ctx } = ctxOf(fx);
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: mkdtempSync(join(tmpdir(), 'fwcc-')) });
  assert.deepEqual(doc.runs.map((r) => r.class), ['arm.large.gen2', 'arm.large.gen2', 'arm.large.gen2']);
  assert.deepEqual(doc.runs.map((r) => r.durMs), [36475, 52637, 9882]);
  const cmp = comparePairs(g, githubRuns(g, fx.github, fx.github.digests), doc.runs);
  assert.equal(cmp.code, 0);
  assert.deepEqual(cmp.rows.map((r) => r.credits), [8, 11, 2]);
  assert.equal(fx.sha, loadFixture('premise-tests').sha, 'both pipelines ran the commit of the one GitHub twin');
});

test('the recorded webkit-sim stall (pipeline 36): CircleCI fails, GitHub passes, so the pair is a finding (exit 1) with the job exit status kept (130)', async () => {
  const fx = loadFixture('webkit-sim-stall');
  const { ctx } = ctxOf(fx);
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: mkdtempSync(join(tmpdir(), 'fwcc-')) });
  assert.deepEqual(doc.runs.map((r) => [r.job, r.conclusion, r.durMs]), [['webkit-sim', 'fail', 826521]]);
  assert.equal(doc.spans.find((s) => s.step === 'determinism session').exit, 130);
  const cmp = comparePairs(g, githubRuns(g, fx.github, fx.github.digests), doc.runs);
  assert.equal(cmp.code, 1);
  assert.equal(cmp.rows[0].finding, true);
  assert.equal(cmp.rows[0].credits, 2756);
});

test('the recorded fixtures carry no token, e-mail, home path or account name', () => {
  for (const n of ['premise-tests', 'premise-tests-large', 'webkit-sim', 'webkit-sim-stall']) {
    const text = readFileSync(join(ROOT, 'scripts', 'circleci-fixtures', `${n}.json`), 'utf8');
    // CI accounts (runner, root, ...) are not a person; a real account name is matched as a whole word
    const me = userInfo().username;
    const named = !/^(runner|root|user|circleci|ubuntu|admin|ci)$/i.test(me) && me.length >= 4 && new RegExp(`\\b${me.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i').test(text);
    assert.ok(!text.includes('/Users/') && !named, n);
    assert.deepEqual([...new Set(text.match(/[\w.+-]+@[\w-]+\.[\w.-]+/g) ?? [])], ['noreply@anthropic.com'], n);
    assert.ok(!/Circle-Token|"token"/i.test(text), n);
  }
});

test('a digest that differs is a finding (exit 1); a missing side is not a pair (exit 2)', async () => {
  const fx = loadFixture('premise-tests');
  const { ctx } = ctxOf(fx);
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: mkdtempSync(join(tmpdir(), 'fwcc-')) });
  const bad = githubRuns(g, fx.github, { ...fx.github.digests, 'engine (chromium)': 'deadbeef' });
  const cmp = comparePairs(g, bad, doc.runs);
  assert.equal(cmp.code, 1);
  assert.match(renderComparison(cmp.rows), /engine-chromium \(github: engine \(chromium\)\): FINDING verdicts differ/);
  assert.equal(comparePairs(g, githubRuns(g, { ...fx.github, headSha: 'other' }, fx.github.digests), doc.runs).code, 2);
  assert.equal(comparePairs(g, githubRuns(g, { ...fx.github, jobs: fx.github.jobs.slice(1) }, fx.github.digests), doc.runs).code, 2);
});

test('fetch refuses an artifact path that leaves the output directory', async () => {
  const fx = loadFixture('premise-tests');
  const api = JSON.parse(JSON.stringify(fx.api));
  api.routes[`GET /project/${fx.slug}/${jobNo(fx, 'engine-chromium')}/artifacts`].items[0].path = '../../evil.json';
  const { ctx } = ctxOf(fx, { fetchFn: fixtureFetch(api) });
  await assert.rejects(fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: mkdtempSync(join(tmpdir(), 'fwcc-')) }), /leaves the output directory/);
});

test('dry run: prints the requests with the token redacted, and the fixture comparison', async () => {
  const lines = [];
  const r = await dryRun({ golden: g, lane: 'webkit-sim', branch: 'ci/x', log: (l) => lines.push(l), tmp: mkdtempSync(join(tmpdir(), 'fwcc-')) });
  const text = lines.join('\n');
  assert.match(text, /POST https:\/\/circleci\.com\/api\/v2\/project\/<project-slug>\/pipeline\/run/);
  assert.match(text, /Circle-Token: <redacted>/);
  assert.ok(!text.includes('fixture-token'));
  assert.match(text, /webkit-sim \(github: sim \(original, 430, 1, 458c852eb8545981506c1b1374ca3d4072de3b2a, v1\)\): verdicts equal; duration 0\.18x GitHub; queue github 114s \(run start to job start\), circleci 64s; credits 1025/);
  assert.equal(r.cmp.code, 0);
});

test('premiseDigest: order of tests and of files does not matter, a changed verdict does', () => {
  const a = mkdtempSync(join(tmpdir(), 'fwd-')), b = mkdtempSync(join(tmpdir(), 'fwd-'));
  mkdirSync(join(a, 'x'));
  writeFileSync(join(a, 'x', 'c.json'), JSON.stringify({ results: [{ testId: 't1', ok: true }, { testId: 't2', ok: false }] }));
  writeFileSync(join(b, 'c.json'), JSON.stringify({ results: [{ testId: 't2', ok: false }, { testId: 't1', ok: true }], browser: 'other' }));
  assert.equal(premiseDigest(a), premiseDigest(b));
  writeFileSync(join(b, 'c.json'), JSON.stringify({ results: [{ testId: 't2', ok: true }, { testId: 't1', ok: true }] }));
  assert.notEqual(premiseDigest(a), premiseDigest(b));
  assert.equal(premiseDigest(join(a, 'missing')), null);
});

test('timings: the in-job step wraps span.sh lines with job, class, commit and digest', () => {
  const d = timingsDoc({ spansText: '{"tool":"circleci/x","step":"test","startMs":1,"durMs":2,"exit":0,"commit":"abc","load":0,"host":"ci"}\nnot json\n', job: 'x', cls: 'arm.medium.gen2', sha: 'abc', digest: null });
  assert.equal(d.spans.length, 1);
  assert.equal(d.class, 'arm.medium.gen2');
  const dir = mkdtempSync(join(tmpdir(), 'fwt-'));
  writeFileSync(join(dir, 'spans.jsonl'), '{"tool":"t","step":"s","startMs":1,"durMs":2,"exit":0,"commit":"","load":0,"host":"ci"}\n');
  execFileSync('node', [join(here, 'circleci.mjs'), 'timings', '--spans', join(dir, 'spans.jsonl'), '--out', join(dir, 't.json'), '--job', 'j', '--class', 'c', '--sha', 's']);
  assert.equal(JSON.parse(readFileSync(join(dir, 't.json'), 'utf8')).job, 'j');
});

test('cli: a trigger without a project slug is a usage error (64), a dry trigger needs none; route prints the provider', async () => {
  const logs = [];
  const root = mkdtempSync(join(tmpdir(), 'fwroot-'));
  assert.equal(await main(['trigger', '--lane', 'premise-tests', '--branch', 'ci/x'], { root, env: {}, log: (l) => logs.push(l) }), 64);
  assert.equal(await main(['trigger', '--lane', 'premise-tests', '--branch', 'main', '--dry'], { root, env: {}, log: (l) => logs.push(l) }), 64);
  assert.equal(await main(['trigger', '--lane', 'premise-tests', '--branch', 'ci/x', '--class', 'arm.xlarge', '--dry'], { root, env: {}, log: (l) => logs.push(l) }), 64);
  assert.equal(await main(['trigger', '--lane', 'premise-tests', '--branch', 'ci/x', '--dry'], { root, env: {}, log: (l) => logs.push(l) }), 0);
  assert.equal(await main(['wait', '--pipeline', 'p', '--interval', '5'], { root, env: { FW_CIRCLECI_SLUG: 's' }, log: (l) => logs.push(l) }), 64);
  assert.equal(await main(['route', '--lane', 'premise-tests', '--platform', 'linux-arm', '--class', 'arm.medium.gen2', '--est-ms', '600000', '--credits-left', '100', '--allow', 'premise-tests'], { root, env: {}, log: (l) => logs.push(l) }), 0);
  assert.equal(logs.at(-1), 'circleci');
  assert.ok(logs.join('\n').includes('"definition_id": "<definition-id>"'));
});

test('urls are built from the pieces, no token', () => {
  assert.equal(urls.job('s', 4), `${API}/project/s/job/4`);
  assert.equal(urls.pipelines('s', 'ci/x y'), `${API}/project/s/pipeline?branch=ci%2Fx%20y`);
});

test('a digest job without a digest on a side is not a pair (exit 2), and the digest decides over the step conclusion', async () => {
  const fx = loadFixture('premise-tests');
  const { ctx } = ctxOf(fx);
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: mkdtempSync(join(tmpdir(), 'fwcc-')) });
  const none = comparePairs(g, githubRuns(g, fx.github, {}), doc.runs);
  assert.equal(none.code, 2);
  assert.match(renderComparison(none.rows), /engine-chromium: not a pair \(digest missing on a side\)/);
  assert.equal(none.rows.find((r) => r.job === 'verdict').comparable, true);
  const failed = githubRuns(g, { ...fx.github, jobs: fx.github.jobs.map((j) => (j.name === 'engine (chromium)' ? { ...j, conclusion: 'failure' } : j)) }, fx.github.digests);
  assert.equal(comparePairs(g, failed, doc.runs).code, 0, 'equal digests are no finding although the GitHub step conclusion differs');
});

test('githubDigests downloads premises-<engine> of the run once and digests it; a failed download leaves the digest missing', () => {
  const fx = loadFixture('premise-tests');
  const base = mkdtempSync(join(tmpdir(), 'fwgd-'));
  const calls = [];
  const download = (id, art, dir) => { calls.push([id, art]); mkdirSync(dir, { recursive: true }); writeFileSync(join(dir, 'c.json'), JSON.stringify({ results: [{ testId: 't1', ok: true }] })); };
  const run = { ...fx.github, databaseId: 77 };
  const d = githubDigests(g, run, base, download);
  assert.deepEqual(calls.map((c) => c.join(' ')).sort(), ['77 premises-chromium', '77 premises-playwright-webkit']);
  assert.equal(d['engine (chromium)'], premiseDigest(join(base, 'premises-chromium')));
  assert.ok(!('verdict' in d));
  githubDigests(g, run, base, download);
  assert.equal(calls.length, 2, 'a second call reuses the directory');
  const bad = githubDigests(g, run, mkdtempSync(join(tmpdir(), 'fwgd-')), () => { throw new Error('no artifact'); });
  assert.equal(bad['engine (chromium)'], null);
  assert.equal(premisesArtifact('engine (playwright-webkit)'), 'premises-playwright-webkit');
  assert.equal(premisesArtifact('verdict'), null);
});

test('the sim matrix job of a real GitHub run pairs by prefix and VM', () => {
  const run = { headSha: 'a'.repeat(40), createdAt: '2026-10-20T00:00:00Z', jobs: [
    { name: 'plan', conclusion: 'success' },
    { name: 'sim (rewrite, 430, 1, 40a8d4c1deadbeef, v1)', conclusion: 'success', startedAt: '2026-10-20T00:01:00Z', completedAt: '2026-10-20T00:02:00Z' },
    { name: 'sim (original, 430, 1, 40a8d4c1deadbeef, v2)', conclusion: 'success', startedAt: '2026-10-20T00:01:00Z', completedAt: '2026-10-20T00:02:00Z' },
    { name: 'sim (original, 430, 1, 40a8d4c1deadbeef, v1)', conclusion: 'success', startedAt: '2026-10-20T00:01:00Z', completedAt: '2026-10-20T00:03:00Z' },
    { name: 'sim (original, 390, 2, 40a8d4c1deadbeef, v1)', conclusion: 'failure', startedAt: '2026-10-20T00:01:00Z', completedAt: '2026-10-20T00:03:00Z' }] };
  const rs = githubRuns(g, run);
  assert.deepEqual(rs.map((r) => [r.job, r.githubJob, r.durMs]), [['webkit-sim', 'sim (original, 430, 1, 40a8d4c1deadbeef, v1)', 120000]]);
});

test('pagination: next_page_token is followed on every list and a token past the page limit fails loudly', async () => {
  const pages = { '': { items: [1], next_page_token: 'a' }, a: { items: [2], next_page_token: 'b' }, b: { items: [3], next_page_token: null } };
  const urlsSeen = [];
  const fetchFn = async (url) => { urlsSeen.push(url); const t = new URL(url).searchParams.get('page-token') ?? ''; return { status: 200, ok: true, headers: { get: () => null }, text: async () => JSON.stringify(pages[t]) }; };
  const ctx = { fetchFn, getToken: () => 't', sleep: async () => {} };
  assert.deepEqual(await listAll(ctx, `${API}/x?branch=b`), [1, 2, 3]);
  assert.deepEqual(urlsSeen.map((u) => new URL(u).searchParams.get('page-token')), [null, 'a', 'b']);
  await assert.rejects(listAll(ctx, `${API}/x`, { maxPages: 2 }), /next_page_token still set after 2 pages/);
});

test('fetch reads every page of the job list and the artifact list', async () => {
  const fx = loadFixture('premise-tests');
  const base = fixtureFetch(fx.api);
  const jobs = fx.api.routes[`GET /workflow/${wfIdOf(fx)}/job`].items;
  const fetchFn = async (url, init) => {
    const u = new URL(String(url));
    if (u.pathname.endsWith(`/workflow/${wfIdOf(fx)}/job`)) {
      const page = u.searchParams.get('page-token');
      const body = page ? { items: jobs.slice(1), next_page_token: null } : { items: jobs.slice(0, 1), next_page_token: 'p2' };
      return { status: 200, ok: true, headers: { get: () => null }, text: async () => JSON.stringify(body) };
    }
    return base(url, init);
  };
  const { ctx } = ctxOf(fx, { fetchFn });
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: mkdtempSync(join(tmpdir(), 'fwcc-')) });
  assert.equal(doc.runs.length, 3);
});

test('an artifact download goes through the same path: a 429 waits Retry-After, the token goes to CircleCI hosts only', async () => {
  const seen = [];
  const sleeps = [];
  let n = 0;
  const fetchFn = async (url, init) => {
    seen.push({ url, init });
    n++;
    return n === 1 ? { status: 429, ok: false, headers: { get: (k) => (k.toLowerCase() === 'retry-after' ? '9' : null) }, text: async () => 'slow' }
      : { status: 200, ok: true, headers: { get: () => null }, arrayBuffer: async () => Buffer.from('abc'), text: async () => 'abc' };
  };
  const ctx = { fetchFn, getToken: () => 'SECRET', sleep: async (x) => sleeps.push(x) };
  assert.equal((await callBytes(ctx, 'https://output.circle-artifacts.com/x/y.json?sig=1')).toString(), 'abc');
  assert.deepEqual(sleeps, [9]);
  assert.equal(seen[1].init.headers['Circle-Token'], 'SECRET');
  seen.length = 0;
  await callBytes(ctx, 'https://example.org/z.bin');
  assert.ok(!('Circle-Token' in seen[0].init.headers));
  await assert.rejects(callBytes({ fetchFn: async () => ({ status: 500, ok: false, headers: { get: () => null }, text: async () => 'boom' }), getToken: () => 'SECRET', sleep: async () => {} }, 'https://output.circle-artifacts.com/a?sig=SECRETQ'), (e) => !e.message.includes('sig=') && !e.message.includes('SECRET'));
});

test('parseLoose accepts raw control characters inside strings and nothing else', () => {
  assert.deepEqual(parseLoose('{"a": "x\ny\tz", "b": [1,\n2]}'), { a: 'x\ny\tz', b: [1, 2] });
  assert.deepEqual(parseLoose('{"a": "q\\"w\ne"}'), { a: 'q"w\ne' });
  assert.throws(() => parseLoose('{"a": '));
});

test('wait --branch skips pipelines a push created (webhook), which hold no workflow', () => {
  assert.equal(isPilotPipeline({ trigger: { type: 'webhook' } }), false);
  assert.equal(isPilotPipeline({ trigger: { type: 'api' } }), true);
});

test('storage: the ledger adds cache, workspace and artifact bytes over all pilot pipelines; over the 1 GB-month stop at retention is exit 5 from fetch and wait', async () => {
  const fx = loadFixture('premise-tests');
  const dir = mkdtempSync(join(tmpdir(), 'fwled-'));
  const ledgerPath = join(dir, 'ledger.json');
  const { ctx } = ctxOf(fx, { ledgerPath });
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: join(dir, 'o') });
  const b = readLedger(ledgerPath).pipelines[fx.pipelineId];
  assert.equal(b.artifacts, doc.storage.artifacts);
  assert.equal(b.cache, 9856615, 'pipeline 15: one job stored a 9.3 MiB archive, the other found the key (skipped)');
  assert.ok(b.workspace > 0, 'the engine jobs report the workspace they persisted');
  assert.equal(doc.storage.ledgerBytes, b.artifacts + b.cache + b.workspace);
  assert.equal(doc.storage.milli, storageNow(g, ledgerRows(readLedger(ledgerPath)), ctx.now()));
  assert.ok(doc.storage.milli <= storageMilli(doc.storage.ledgerBytes, 30));
  writeFileSync(ledgerPath, JSON.stringify({ pipelines: { old: { artifacts: 0, cache: 1200000000, workspace: 0 } } }));
  assert.deepEqual((await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: join(dir, 'o1') })).storage.stops, []);
  writeFileSync(ledgerPath, JSON.stringify({ pipelines: { old: { artifacts: 0, cache: 2400000000, workspace: 0 } } }));
  const doc2 = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: join(dir, 'o2') });
  assert.deepEqual(doc2.storage.stops, ['storage']);
  const calls = [];
  const base = fixtureFetch({ ...fx.api, routes: { ...fx.api.routes, [`POST /workflow/${wfIdOf(fx)}/cancel`]: {} } });
  const w = await waitPipeline({ ...ctx, fetchFn: async (u, i) => { calls.push(`${i?.method ?? 'GET'} ${String(u).replace(API, '')}`); return base(u, i); } }, { slug: fx.slug, pipelineId: fx.pipelineId });
  assert.equal(w.code, 5);
  assert.ok(calls.includes(`POST /workflow/${wfIdOf(fx)}/cancel`));
  calls.length = 0;
  const wl = await waitPipeline({ ...ctx, storageStop: false, fetchFn: async (u, i) => { calls.push(`${i?.method ?? 'GET'} ${String(u).replace(API, '')}`); return base(u, i); } }, { slug: fx.slug, pipelineId: fx.pipelineId });
  assert.equal(wl.code, 0);
  assert.ok(!calls.some((c) => c.startsWith('POST ')));
  const logs = [];
  const root = dir;
  mkdirSync(join(root, '.local'), { recursive: true });
  writeFileSync(join(root, '.local', 'circleci-ledger.json'), JSON.stringify({ pipelines: { old: { artifacts: 0, cache: 2400000000, workspace: 0 } } }));
  assert.equal(await main(['fetch', '--pipeline', fx.pipelineId, '--out', join(dir, 'o3')], { root, env: { FW_CIRCLECI_SLUG: fx.slug }, ctx: { fetchFn: fixtureFetch(fx.api), getToken: () => 't', sleep: async () => {} }, log: (l) => logs.push(l) }), 5);
});

test('wait: a cancelled workflow is not a pass (exit 4, Lean waitStep)', async () => {
  const fx = loadFixture('premise-tests');
  const api = JSON.parse(JSON.stringify(fx.api));
  api.routes[wfRoute(fx)].items[0].status = 'canceled';
  const { ctx } = ctxOf(fx, { fetchFn: fixtureFetch(api) });
  assert.equal((await waitPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId })).code, 4);
});

test('timings.json carries the bytes a job persisted to the workspace, not the cache (the ledger reads the save step)', () => {
  const d = timingsDoc({ spansText: '', job: 'j', cls: 'c', sha: 's', digest: null, workspaceBytes: 7 });
  assert.deepEqual(d.bytes, { workspace: 7 });
});

// ------------------------------------------------------------------------------------------ cache saves (circleci-cache-accounting)

test('cacheSaved and cachePipeline: every golden row (Lean cacheSavedBytes, cachePipelineBytes)', () => {
  for (const r of rowsOf('cacheSaved')) assert.equal(cacheSavedBytes(r.request.save), r.response.bytes, r.name);
  for (const r of rowsOf('cachePipeline')) assert.equal(cachePipelineBytes(r.request.saves), r.response.bytes, r.name);
  assert.throws(() => cacheSavedBytes({ kind: 'weird' }));
});

test('jobMap: savesCache per row, and savesCacheJob (Lean) is false for a job outside the map', () => {
  for (const r of g.jobMap) assert.equal(savesCacheJob(g, r.circleci), r.savesCache, r.circleci);
  assert.deepEqual(g.jobMap.filter((r) => r.savesCache).map((r) => r.circleci), ['engine-chromium', 'engine-playwright-webkit']);
  assert.equal(savesCacheJob(g, 'probe'), false);
  assert.deepEqual(g.landJobs, landLegs().map((l) => `land-${l}`));
  for (const j of g.landJobs) assert.equal(savesCacheJob(g, j), true, j);
  assert.equal(savesCacheJob(g, 'land-nope'), false);
});

const saveText = (name, n) => loadFixture(name).api.files[`https://action-output.example/${name}/job-${n}/saving-cache`].map((x) => x.message).join('');

test('parseCacheSave: the recorded outputs of pipelines 15 and 16; anything else is an error', () => {
  assert.deepEqual(parseCacheSave(saveText('premise-tests', 10)), { kind: 'skipped' });
  assert.deepEqual(parseCacheSave(saveText('premise-tests', 11)), { kind: 'stored', tenthsMiB: 93 });
  assert.deepEqual(parseCacheSave(saveText('premise-tests-large', 13)), { kind: 'skipped' });
  assert.deepEqual(parseCacheSave('Total size uploaded: 512.0 KiB'), { kind: 'stored', tenthsMiB: 5 });
  assert.deepEqual(parseCacheSave('Total size uploaded: 1.2 GiB'), { kind: 'stored', tenthsMiB: 12288 });
  assert.throws(() => parseCacheSave('Creating cache archive...'), /neither a skip nor a size/);
  assert.throws(() => parseCacheSave(''), /neither a skip nor a size/);
});

test('readCacheSave: no save step is absent; a failed save step is an error', async () => {
  const fx = loadFixture('premise-tests');
  const url = `https://circleci.com/api/v1.1/project/${fx.slug}/11`;
  const withSteps = (steps) => ({ fetchFn: fixtureFetch({ ...fx.api, routes: { ...fx.api.routes, [`GET ${url}`]: { steps } } }), getToken: () => 't', sleep: async () => {} });
  const act = (name, status) => ({ name: 'x', actions: [{ name, status }] });
  const read = (steps) => readCacheSave(withSteps(steps), { slug: fx.slug, jobNumber: 11 });
  assert.deepEqual(await read([act('premise tests', 'success')]), { kind: 'absent' });
  assert.deepEqual(await read([act('Saving cache', 'not_run')]), { kind: 'absent' });
  await assert.rejects(read([act('Saving cache', 'failed')]), /unknown/);
  await assert.rejects(read([act('Saving cache', 'success')]), /no output/);
  await assert.rejects(read([act('Saving cache', 'success'), act('Saving cache', 'success')]), /at most one/);
});

test('the ledger over a series: only real saves count (pipeline 15 stored once, 16 skipped twice, a halted pipeline has no save step)', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'fwseries-'));
  const ledgerPath = join(dir, 'ledger.json');
  const p15 = loadFixture('premise-tests'), p16 = loadFixture('premise-tests-large');
  const d15 = await fetchPipeline(ctxOf(p15, { ledgerPath }).ctx, { slug: p15.slug, pipelineId: p15.pipelineId, out: join(dir, 'a') });
  const d16 = await fetchPipeline(ctxOf(p16, { ledgerPath }).ctx, { slug: p16.slug, pipelineId: p16.pipelineId, out: join(dir, 'b') });
  assert.deepEqual(d15.storage.cacheSaves.map((x) => [x.job, x.kind]), [['engine-chromium', 'skipped'], ['engine-playwright-webkit', 'stored']]);
  assert.deepEqual(d16.storage.cacheSaves.map((x) => x.kind), ['skipped', 'skipped']);
  assert.equal(d15.storage.cache, 9856615);
  assert.equal(d16.storage.cache, 0);
  // the new job shape: the cache gate halts the job, so the job has no save step at all
  const halted = JSON.parse(JSON.stringify(p16));
  for (const [k, v] of Object.entries(halted.api.routes)) if (k.startsWith('GET https://circleci.com/api/v1.1/')) v.steps = v.steps.filter((st) => !st.actions.some((a) => a.name === 'Saving cache'));
  halted.pipelineId = 'halted-pipeline';
  halted.api.routes = Object.fromEntries(Object.entries(halted.api.routes).map(([k, v]) => [k.replace(p16.pipelineId, halted.pipelineId), v]));
  const d17 = await fetchPipeline(ctxOf(halted, { ledgerPath }).ctx, { slug: halted.slug, pipelineId: halted.pipelineId, out: join(dir, 'c') });
  assert.deepEqual(d17.storage.cacheSaves.map((x) => x.kind), ['absent', 'absent']);
  assert.equal(d17.storage.cache, 0);
  const l = readLedger(ledgerPath).pipelines;
  assert.equal(l[p15.pipelineId].cache + l[p16.pipelineId].cache + l['halted-pipeline'].cache, 9856615);
  assert.deepEqual(d17.storage.stops, []);
  // the old accounting counted du of the store at every job: 2 x 53637120 bytes = 108 thousandths per pipeline
  assert.equal(storageMilli(2 * 53637120, 30), 108);
  assert.ok(d17.storage.milli < 20, `ledger after three pipelines: ${d17.storage.milli} thousandths`);
});

// --------------------------------------------------------------------------------------- the cache gate in the job script

/** Run `job.sh <step>` with a temporary HOME and job dir; `circleci-agent` is a stub that records its arguments. */
function jobStep(step, { marker, dir }) {
  const home = join(dir, 'home'), fwDir = join(dir, 'fw'), bin = join(dir, 'bin');
  mkdirSync(join(home, '.fw-cache'), { recursive: true });
  mkdirSync(bin, { recursive: true });
  writeFileSync(join(bin, 'circleci-agent'), `#!/bin/sh\necho "$@" >> "${join(dir, 'agent.log')}"\n`);
  chmodSync(join(bin, 'circleci-agent'), 0o755);
  if (marker !== undefined) writeFileSync(join(home, '.fw-cache', 'lock-sha256'), `${marker}\n`);
  const env = { PATH: `${bin}${delimiter}${dirname(process.execPath)}${delimiter}/usr/bin${delimiter}/bin${delimiter}/sbin`, HOME: home, FW_JOB_DIR: fwDir };
  return execFileSync('sh', [join(ROOT, '.circleci', 'job.sh'), step], { env, encoding: 'utf8' });
}

const lockSha = createHash('sha256').update(readFileSync(join(ROOT, 'pnpm-lock.yaml'))).digest('hex');

test('cache gate: a restored marker that names this lockfile halts the job before save_cache; anything else writes the marker', () => {
  const fresh = () => mkdtempSync(join(tmpdir(), 'fwgate-'));
  // hit: the marker is this lockfile's hash
  let dir = fresh();
  jobStep('cache-probe', { marker: lockSha, dir });
  assert.ok(existsSync(join(dir, 'fw', 'cache-current')));
  jobStep('cache-gate', { marker: lockSha, dir });
  assert.equal(readFileSync(join(dir, 'agent.log'), 'utf8').trim(), 'step halt');
  // miss: nothing restored
  dir = fresh();
  jobStep('cache-probe', { dir });
  assert.ok(!existsSync(join(dir, 'fw', 'cache-current')));
  jobStep('cache-gate', { dir });
  assert.ok(!existsSync(join(dir, 'agent.log')), 'no halt on a miss');
  assert.equal(readFileSync(join(dir, 'home', '.fw-cache', 'lock-sha256'), 'utf8').trim(), lockSha, 'the marker is written for the save');
  // stale: the restored marker names another lockfile
  dir = fresh();
  jobStep('cache-probe', { marker: 'f'.repeat(64), dir });
  assert.ok(!existsSync(join(dir, 'fw', 'cache-current')));
  jobStep('cache-gate', { marker: 'f'.repeat(64), dir });
  assert.ok(!existsSync(join(dir, 'agent.log')));
  assert.equal(readFileSync(join(dir, 'home', '.fw-cache', 'lock-sha256'), 'utf8').trim(), lockSha);
});

test('config: the engine jobs save the pnpm cache once, after the gate; the verdict job only restores', () => {
  const cfg = readFileSync(join(ROOT, '.circleci', 'config.yml'), 'utf8');
  const jobs = cfg.slice(cfg.indexOf('\njobs:'), cfg.indexOf('\nworkflows:'));
  const engine = jobs.slice(jobs.indexOf('\n  engine:'), jobs.indexOf('\n  verdict:'));
  const verdict = jobs.slice(jobs.indexOf('\n  verdict:'), jobs.indexOf('\n  webkit-sim:'));
  assert.equal((engine.match(/- save_cache:/g) ?? []).length, 1);
  assert.ok(engine.indexOf('cache-probe') > engine.indexOf('restore_cache') && engine.indexOf('cache-probe') < engine.indexOf('deps install'));
  assert.ok(engine.indexOf('cache-gate') > engine.indexOf('- finish') && engine.indexOf('cache-gate') < engine.indexOf('- save_cache:'));
  assert.ok(!/save_cache/.test(verdict) && /restore_cache/.test(verdict));
  const keys = [...cfg.matchAll(/pnpm-store-v\d+-\{\{ checksum "pnpm-lock\.yaml" \}\}/g)].map((m) => m[0]);
  assert.equal(new Set(keys).size, 1, 'one key for restore and save');
  assert.match(keys[0], /pnpm-store-v2-/);
  assert.match(engine, /~\/\.fw-cache/);
});

// ------------------------------------------------------------------------------------------------------------------ key check

/** A fake CircleCI: `routes` maps "METHOD path" to a body or { status, body }; every call is recorded; an unknown path is 404. */
function fakeApi(routes) {
  const calls = [];
  const fetchFn = async (url, init = {}) => {
    const u = String(url);
    const path = u.startsWith(API) ? u.slice(API.length) : u.replace('https://circleci.com', '');
    calls.push(`${init.method ?? 'GET'} ${path}`);
    const hit = routes[`${init.method ?? 'GET'} ${path}`];
    const status = hit === undefined ? 404 : hit.status ?? 200;
    const body = hit === undefined ? { message: 'not found' } : hit.body ?? hit;
    return { status, ok: status < 400, headers: { get: () => null }, text: async () => JSON.stringify(body) };
  };
  return { calls, ctx: { fetchFn, getToken: () => 't', sleep: async () => {} } };
}

const cloneRoutes = (status) => ({
  'GET /project/s/pipeline': { items: [{ id: 'p1' }] },
  'GET /pipeline/p1/workflow': { items: [{ id: 'w1' }] },
  'GET /workflow/w1/job': { items: [{ job_number: 7, name: 'engine-chromium' }, { name: 'verdict' }] },
  'GET /api/v1.1/project/s/7': { steps: [{ actions: [{ name: 'Spin up environment', status: 'success' }, { name: CHECKOUT_STEP, status }] }] },
});

test('key check: a readable list decides, counts only usable kinds, and reads nothing else', async () => {
  const keys = (items) => fakeApi({ 'GET /project/s/checkout-key': { items } });
  let a = keys([{ type: 'deploy-key' }]);
  assert.deepEqual(await keyCheck(a.ctx, { slug: 's' }), { verdict: 'ok', proceed: true, keys: 1, checkout: null });
  assert.deepEqual(a.calls, ['GET /project/s/checkout-key']);
  a = keys([{ type: 'github-oauth-key' }]);
  assert.equal((await keyCheck(a.ctx, { slug: 's' })).verdict, 'missing');
  a = keys([]);
  const r = await keyCheck(a.ctx, { slug: 's' });
  assert.deepEqual([r.verdict, r.proceed, a.calls.length], ['missing', false, 1]);
});

test('key check: a 403 key list falls back to the newest finished clone; only GETs are sent', async () => {
  const run = async (status) => {
    const a = fakeApi({ 'GET /project/s/checkout-key': { status: 403, body: { message: 'Permission denied' } }, ...cloneRoutes(status) });
    return { r: await keyCheck(a.ctx, { slug: 's' }), calls: a.calls };
  };
  let { r, calls } = await run('success');
  assert.deepEqual([r.verdict, r.proceed, r.keys, r.checkout], ['ok', true, null, true]);
  assert.ok(calls.every((c) => c.startsWith('GET ')));
  ({ r } = await run('failed'));
  assert.deepEqual([r.verdict, r.proceed, r.checkout], ['missing', false, false]);
  ({ r } = await run('running'));
  assert.deepEqual([r.verdict, r.proceed, r.checkout], ['unknown', false, null]);
});

test('key check: an unreadable list and a project with no pipeline is unknown; any other API error is thrown, not a verdict', async () => {
  const a = fakeApi({ 'GET /project/s/checkout-key': { status: 403, body: {} }, 'GET /project/s/pipeline': { items: [] } });
  assert.equal((await keyCheck(a.ctx, { slug: 's' })).verdict, 'unknown');
  const b = fakeApi({ 'GET /project/s/checkout-key': { status: 500, body: {} } });
  await assert.rejects(readKeyList(b.ctx, { slug: 's' }), /HTTP 500/);
});

test('key check: the exit codes and the advice name no pipeline start', () => {
  assert.deepEqual(['ok', 'missing', 'unknown'].map(keyExit), [0, 6, 7]);
  assert.match(keyAdvice({ verdict: 'missing', keys: 0 }), /no pipeline was started/);
  assert.match(keyAdvice({ verdict: 'unknown', keys: null }), /no pipeline was started/);
});

test('cli: key-check and trigger stop before the POST when the key is missing, and trigger posts when it is there', async () => {
  const root = mkdtempSync(join(tmpdir(), 'fwroot-'));
  const env = { FW_CIRCLECI_SLUG: 's', FW_CIRCLECI_DEFINITION_ID: 'd' };
  const logs = [];
  const post = { 'POST /project/s/pipeline/run': { id: 'new', number: 9, state: 'created' } };
  let a = fakeApi({ 'GET /project/s/checkout-key': { items: [] }, ...post });
  assert.equal(await main(['trigger', '--lane', 'premise-tests', '--branch', 'ci/x'], { root, env, ctx: a.ctx, log: (l) => logs.push(l) }), 6);
  assert.ok(!a.calls.some((c) => c.startsWith('POST')));
  assert.match(logs.join('\n'), /no pipeline was started/);
  a = fakeApi({ 'GET /project/s/checkout-key': { items: [{ type: 'deploy-key' }] }, ...post });
  assert.equal(await main(['key-check'], { root, env, ctx: a.ctx, log: (l) => logs.push(l) }), 0);
  assert.ok(!a.calls.some((c) => c.startsWith('POST')));
  assert.equal(await main(['trigger', '--lane', 'premise-tests', '--branch', 'ci/x'], { root, env, ctx: a.ctx, log: (l) => logs.push(l) }), 0);
  assert.ok(a.calls.includes('POST /project/s/pipeline/run'));
});

test('land lane: the trigger request carries the legs and the class, --legs is checked against lean/land-legs.txt', async () => {
  const r = triggerRequest({ slug: 's', definitionId: 'd', branch: 'ci/land-x', lane: 'land', cls: 'arm.medium.gen2', legs: ['check-sh', 'chromium'] });
  assert.deepEqual(r.body.parameters, { lane: 'land', resource_class: 'arm.medium.gen2', legs: 'check-sh,chromium' });
  assert.deepEqual(triggerRequest({ slug: 's', definitionId: 'd', branch: 'ci/x', lane: 'premise-tests', legs: ['chromium'] }).body.parameters, { lane: 'premise-tests' });
  assert.deepEqual(landLegs(), ['check-sh', 'suites-a', 'suites-b', 'chromium', 'playwright-webkit']);
  const root = mkdtempSync(join(tmpdir(), 'fwroot-'));
  const logs = [];
  const run = (a) => main(a, { root, env: {}, log: (l) => logs.push(l) });
  assert.equal(await run(['trigger', '--lane', 'land', '--branch', 'ci/x', '--dry']), 64, 'a land trigger needs legs');
  assert.equal(await run(['trigger', '--lane', 'land', '--branch', 'ci/x', '--legs', 'nope', '--dry']), 64);
  assert.equal(await run(['trigger', '--lane', 'premise-tests', '--branch', 'ci/x', '--legs', 'chromium', '--dry']), 64);
  assert.equal(await run(['trigger', '--lane', 'land', '--branch', 'ci/x', '--legs', 'check-sh,chromium', '--dry']), 0);
  assert.match(logs.join('\n'), /"legs": "check-sh,chromium"/);
});

test('land lane: landLane reads the record a land job writes and nothing else', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fwlane-'));
  const f = join(dir, 'lane.json');
  assert.equal(landLane(null), null);
  assert.equal(landLane(f), null);
  writeFileSync(f, '{"leg":"suites-a","sha":"abc","digest":"d1","engine":"false","rc":0}\n');
  assert.deepEqual(landLane(f), { leg: 'suites-a', sha: 'abc', digest: 'd1', engine: 'false', rc: 0 });
  writeFileSync(f, '{"leg":"suites-a"}');
  assert.equal(landLane(f), null);
  writeFileSync(f, 'not json');
  assert.equal(landLane(f), null);
});

test('land lane: the engine leg runs engine_libs and engine_browser in subshells, so their cd does not move the browser suite', () => {
  // engine_libs does `cd packages/gate-breakpoints`; called in the shell of land_engine it moved the suite's cwd and the first live run
  // of an engine leg died with exit 2 on `cd packages/e2e-preview` (the premise jobs call them as separate steps, where it does not matter).
  const job = readFileSync(join(ROOT, '.circleci', 'job.sh'), 'utf8');
  const body = /^land_engine\(\) \{[\s\S]*?^\}/m.exec(job)?.[0];
  assert.ok(body, 'land_engine found');
  for (const fn of ['engine_libs', 'engine_browser']) {
    const calls = body.split('\n').filter((l) => new RegExp(`\\b${fn}\\b`).test(l) && !l.trimStart().startsWith('#'));
    assert.equal(calls.length, 1, `${fn} is called once`);
    assert.match(calls[0], new RegExp(`^\\s*\\(.*\\b${fn}\\)\\s*$`), `${fn} runs in a subshell`);
  }
});

test('land lane: the pinned elan in job.sh is the pin of the setup-lean action, every leg has its workflow', () => {
  const job = readFileSync(join(ROOT, '.circleci', 'job.sh'), 'utf8');
  const action = readFileSync(join(ROOT, '.github', 'actions', 'setup-lean', 'action.yml'), 'utf8');
  for (const k of ['ELAN_VERSION', 'ELAN_SHA256']) {
    const a = new RegExp(`${k}[=:] ?(\\S+)`).exec(action)?.[1], b = new RegExp(`^${k}=(\\S+)`, 'm').exec(job)?.[1];
    assert.ok(a && a === b, `${k}: setup-lean ${a}, job.sh ${b}`);
  }
  const cfg = readFileSync(join(ROOT, '.circleci', 'config.yml'), 'utf8');
  for (const leg of landLegs()) {
    assert.ok(cfg.includes(`name: land-${leg}`) && cfg.includes(`leg: ${leg}`), `config.yml has a workflow for ${leg}`);
  }
  assert.equal(cfg.split('pattern: "^ci/.*"').length - 1, landLegs().length, 'each land workflow is guarded on ci/ branches');
  assert.match(cfg, /enum: \[check-sh, suites-a, suites-b, chromium, playwright-webkit\]/);
});

test('land lane: fetchPipeline puts the lane record of each land job into run.json', async () => {
  const sha = 'a'.repeat(40);
  const api = {
    'GET /pipeline/p1': { vcs: { revision: sha } },
    'GET /pipeline/p1/workflow': { items: [{ id: 'w1' }] },
    'GET /workflow/w1/job': { items: [{ name: 'land-suites-a', job_number: 7, status: 'success' }] },
    'GET /project/s/job/7': { name: 'land-suites-a', status: 'success', started_at: '2026-10-21T10:00:00Z', stopped_at: '2026-10-21T10:10:00Z', queued_at: '2026-10-21T09:59:00Z', duration: 600000, executor: { resource_class: 'arm-medium-gen2' } },
    'GET /project/s/7/artifacts': { items: [{ path: 'tmp/fw/artifacts/lane.json', url: 'https://x.test/lane.json' }] },
      'GET https://circleci.com/api/v1.1/project/s/7': { steps: [{ actions: [{ name: 'Checkout code', status: 'success' }] }] },
  };
  const body = `{"leg":"suites-a","sha":"${sha}","digest":"dd","engine":"false","rc":0}\n`;
  const ctx = { golden: loadGolden(), getToken: () => 't', sleep: async () => {}, now: () => 0, log: () => {}, fetchFn: async (url) => {
    if (String(url).startsWith('https://x.test/')) return new Response(body, { status: 200 });
    const key = `GET ${String(url).replace(API, '').split('?')[0]}`;
    if (!(key in api)) return new Response('{}', { status: 404 });
    return new Response(JSON.stringify(api[key]), { status: 200, headers: { 'content-type': 'application/json' } });
  } };
  const out = mkdtempSync(join(tmpdir(), 'fwland-'));
  const doc = await fetchPipeline(ctx, { slug: 's', pipelineId: 'p1', out });
  assert.deepEqual(doc.storage.cacheSaves, [{ job: 'land-suites-a', number: 7, kind: 'absent' }]);
  assert.equal(doc.storage.cache, 0);
  assert.deepEqual(doc.lanes, [{ job: 'land-suites-a', conclusion: 'pass', leg: 'suites-a', sha, digest: 'dd', engine: 'false', rc: 0 }]);
});

test('creditsSoFar: a fetch writes its credits and time into the ledger, and the sum is a rolling 30 days', async () => {
  const fx = loadFixture('premise-tests');
  const dir = mkdtempSync(join(tmpdir(), 'fwcred-'));
  const ledgerPath = join(dir, 'ledger.json');
  const now = Date.UTC(2026, 9, 21);
  const { ctx } = ctxOf(fx, { ledgerPath, now: () => now });
  await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: join(dir, 'o') });
  const b = readLedger(ledgerPath).pipelines[fx.pipelineId];
  assert.equal(b.at, now);
  assert.ok(b.credits >= 0);
  assert.equal(creditsSoFar({ ledgerPath }, now), b.credits);
  assert.equal(creditsSoFar({ ledgerPath }, now + 29 * 86400000), b.credits);
  assert.equal(creditsSoFar({ ledgerPath }, now + 31 * 86400000), 0, 'older than 30 days: out of the month');
  assert.equal(creditsSoFar({}, now), 0, 'no ledger path: nothing counted');
  writeFileSync(ledgerPath, JSON.stringify({ pipelines: { old: { artifacts: 1, cache: 0, workspace: 0 } } }));
  assert.equal(creditsSoFar({ ledgerPath }, now), 0, 'a pipeline fetched before credits were kept counts 0');
});

test('wait: a workflow whose job list answers 404 is "no jobs yet" (seen right after a trigger); another error still stops the wait', async () => {
  const fx = loadFixture('premise-tests');
  const base = fixtureFetch(fx.api);
  const jobPath = `/workflow/${wfIdOf(fx)}/job`;
  const failing = (status) => async (u, i) => (String(u).startsWith(`${API}${jobPath}`) ? { status, ok: false, headers: { get: () => null }, text: async () => '{"message":"x"}' } : base(u, i));
  const w = await waitPipeline(ctxOf(fx, { fetchFn: failing(404) }).ctx, { slug: fx.slug, pipelineId: fx.pipelineId });
  assert.equal(w.code, 0);
  assert.deepEqual(w.jobs, []);
  await assert.rejects(waitPipeline(ctxOf(fx, { fetchFn: failing(500) }).ctx, { slug: fx.slug, pipelineId: fx.pipelineId }), /HTTP 500/);
});

// ------------------------------------------------------------------------------ the Lake cache of the land job (circleci-lean-cache)

const landJob = () => {
  const cfg = readFileSync(join(ROOT, '.circleci', 'config.yml'), 'utf8');
  return cfg.slice(cfg.indexOf('\n  land:'), cfg.indexOf('\nworkflows:'));
};

test('land lane: the Lake cache is restored in every leg before the build and saved once, after the gate', () => {
  const land = landJob();
  assert.equal((land.match(/- save_cache:/g) ?? []).length, 1);
  assert.equal((land.match(/- restore_cache:/g) ?? []).length, 1);
  const at = (s) => land.indexOf(s);
  assert.ok(at('job.sh lake-key') < at('- restore_cache:') && at('- restore_cache:') < at('job.sh lake-probe') && at('job.sh lake-probe') < at('job.sh land-fwcore'), 'key, restore, probe, then the build');
  assert.ok(at('- finish') < at('job.sh lake-gate') && at('job.sh lake-gate') < at('- save_cache:'), 'the gate comes after finish and before the save');
  // one key for restore and save: toolchain + manifest, then the sources; the second restore key is the toolchain + manifest prefix
  const keys = [...land.matchAll(/lake-v\d+-arm64-\{\{ checksum "\/tmp\/fw\/lake-tm\.key" \}\}-(\{\{ checksum "\/tmp\/fw\/lake-src\.key" \}\})?/g)].map((m) => m[0]);
  assert.equal(keys.length, 3);
  assert.equal(keys[0], keys[2], 'restore (exact) and save use the same key');
  assert.ok(keys[1].length < keys[0].length && keys[0].startsWith(keys[1]), 'the fallback is a prefix of the exact key');
  assert.match(land, /~\/\.fw-lake/);
  // job.sh: the cached directory, the Lake variable and the marker are one place
  const job = readFileSync(join(ROOT, '.circleci', 'job.sh'), 'utf8');
  assert.match(job, /^lake_dir=\$HOME\/\.fw-lake$/m);
  assert.match(job, /^export LAKE_CACHE_DIR=\$lake_dir\/cache$/m);
});

test('land lane: the Lake key hashes the files setup-lean hashes (toolchain, manifest, lakefile, lean/*.lean, Fw, FwTest)', () => {
  const action = readFileSync(join(ROOT, '.github', 'actions', 'setup-lean', 'action.yml'), 'utf8');
  const hashed = [...action.matchAll(/hashFiles\(([^)]*)\)/g)].map((m) => m[1].split(',').map((x) => x.trim().replace(/'/g, '')).join(' '));
  assert.deepEqual([...new Set(hashed)], ['lean/lean-toolchain lean/lake-manifest.json', 'lean/lakefile.toml lean/*.lean lean/Fw/** lean/FwTest/**']);
  const job = readFileSync(join(ROOT, '.circleci', 'job.sh'), 'utf8');
  const body = /^lake_key\(\) \{[\s\S]*?^\}/m.exec(job)?.[0];
  assert.ok(body);
  for (const f of ['lean/lean-toolchain', 'lean/lake-manifest.json', 'lean/lakefile.toml', 'lean/*.lean', 'lean/Fw', 'lean/FwTest']) assert.ok(body.includes(f), f);
});

test('land lane: lake-key writes the hash strings of the key', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fwlake-'));
  const read = (n) => readFileSync(join(dir, 'fw', n), 'utf8').trim();
  const out = jobStep('lake-key', { dir });
  assert.match(out, /lake key: toolchain\+manifest [0-9a-f]{8}, sources [0-9a-f]{8}/);
  assert.match(read('lake-tm.key'), /^[0-9a-f]{64}$/);
  assert.match(read('lake-src.key'), /^[0-9a-f]{64}$/);
  assert.equal(read('lake-full.key'), `${read('lake-tm.key')}-${read('lake-src.key')}`);
  const tm = createHash('sha256').update(readFileSync(join(ROOT, 'lean', 'lean-toolchain'))).update(readFileSync(join(ROOT, 'lean', 'lake-manifest.json'))).digest('hex');
  assert.equal(read('lake-tm.key'), tm, 'toolchain then manifest, as `cat | sha256sum`');
});

test('lake cache gate: the exact key restored halts the job before save_cache; an older entry or none writes the marker for the save', () => {
  const lakeMarker = (dir) => join(dir, 'home', '.fw-lake', 'key');
  const full = (dir) => readFileSync(join(dir, 'fw', 'lake-full.key'), 'utf8').trim();
  const withMarker = (dir, text) => { mkdirSync(join(dir, 'home', '.fw-lake'), { recursive: true }); writeFileSync(lakeMarker(dir), `${text}\n`); };
  const fresh = () => { const d = mkdtempSync(join(tmpdir(), 'fwlake-')); jobStep('lake-key', { dir: d }); return d; };
  // 1. the exact key was restored: halt, marker untouched
  let dir = fresh();
  withMarker(dir, full(dir));
  assert.match(jobStep('lake-probe', { dir }), /exact key was restored/);
  assert.ok(existsSync(join(dir, 'fw', 'lake-current')));
  jobStep('lake-gate', { dir });
  assert.match(readFileSync(join(dir, 'agent.log'), 'utf8'), /step halt/);
  assert.equal(readFileSync(lakeMarker(dir), 'utf8').trim(), full(dir));
  // 2. an older entry (a marker of another key) was restored: no halt, the marker becomes the current key
  dir = fresh();
  withMarker(dir, 'f'.repeat(64));
  assert.match(jobStep('lake-probe', { dir }), /older entry/);
  assert.ok(!existsSync(join(dir, 'fw', 'lake-current')));
  jobStep('lake-gate', { dir });
  assert.ok(!existsSync(join(dir, 'agent.log')), 'no halt');
  assert.equal(readFileSync(lakeMarker(dir), 'utf8').trim(), full(dir));
  // 3. nothing restored: the marker is written for the save, no halt
  dir = fresh();
  assert.match(jobStep('lake-probe', { dir }), /nothing restored/);
  jobStep('lake-gate', { dir });
  assert.ok(!existsSync(join(dir, 'agent.log')));
  assert.equal(readFileSync(lakeMarker(dir), 'utf8').trim(), full(dir));
});
