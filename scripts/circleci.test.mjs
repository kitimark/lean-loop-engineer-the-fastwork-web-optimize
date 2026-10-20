// scripts/circleci.test.mjs: the CircleCI glue against the Lean golden (packages/contracts/golden/ci/provider.jsonl, Lean
// Fw.Ci.Provider), the recorded-shape fixtures and the static facts of .circleci/. Run: node --test scripts/circleci.test.mjs
// No network, no Keychain: the API is a fixture and the token is a fake.
import { strict as assert } from 'node:assert';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir, userInfo } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { classOfApi, API, MIN_POLL_S, ROOT, call, callBytes, comparePairs, compare, credits, digestJob, dryRun, fetchPipeline, fixtureFetch, githubDigests, githubRuns, isPilotPipeline, jobOfGithub, listAll, loadFixture, loadGolden, main, ofCircleStatus, ofGithubConclusion, parseLoose, premiseDigest, premisesArtifact, readLedger, redact, renderComparison, route, stops, storageMilli, timingsDoc, triggerRequest, urls, waitPipeline, waitStep } from './circleci.mjs';

const g = loadGolden();
const here = dirname(fileURLToPath(import.meta.url));
const rowsOf = (op) => g.byOp[op] ?? [];
const toRun = (r) => ({ ...r, class: r.class });

test('the golden has every op the glue replays, and no more', () => {
  assert.deepEqual([...new Set(g.rows.map((r) => r.op))].sort(), ['circleStatus', 'classOfApi', 'compare', 'constants', 'credits', 'ghJob', 'githubConclusion', 'jobMap', 'rates', 'route', 'stop', 'storage', 'wait']);
  assert.ok(g.rows.length >= 120);
});

test('credits: every golden row', () => {
  for (const r of rowsOf('credits')) assert.equal(credits(g, r.request.class, r.request.durMs), r.response.credits, r.name);
});

test('storage: every golden row', () => {
  for (const r of rowsOf('storage')) assert.equal(storageMilli(r.request.bytes, r.request.days), r.response.milli, r.name);
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
  assert.ok(!/save_cache[\s\S]*lake/i.test(cfg), 'no Lake cache');
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

test('storage: the ledger adds cache, workspace and artifact bytes over all pilot pipelines; over 1 GB-month is exit 5 from fetch and wait', async () => {
  const fx = loadFixture('premise-tests');
  const dir = mkdtempSync(join(tmpdir(), 'fwled-'));
  const ledgerPath = join(dir, 'ledger.json');
  const { ctx } = ctxOf(fx, { ledgerPath });
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: join(dir, 'o') });
  const b = readLedger(ledgerPath).pipelines[fx.pipelineId];
  assert.equal(b.artifacts, doc.storage.artifacts);
  assert.ok(b.cache > 0 && b.workspace > 0, 'the engine jobs report what they saved');
  assert.equal(doc.storage.ledgerBytes, b.artifacts + b.cache + b.workspace);
  assert.equal(doc.storage.milli, storageMilli(doc.storage.ledgerBytes, 30));
  // an earlier pilot pipeline of 1.2 GB: the next fetch stops, and so does a wait before any job runs
  writeFileSync(ledgerPath, JSON.stringify({ pipelines: { old: { artifacts: 0, cache: 1200000000, workspace: 0 } } }));
  const doc2 = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: join(dir, 'o2') });
  assert.deepEqual(doc2.storage.stops, ['storage']);
  const calls = [];
  const base = fixtureFetch({ ...fx.api, routes: { ...fx.api.routes, [`POST /workflow/${wfIdOf(fx)}/cancel`]: {} } });
  const w = await waitPipeline({ ...ctx, fetchFn: async (u, i) => { calls.push(`${i?.method ?? 'GET'} ${String(u).replace(API, '')}`); return base(u, i); } }, { slug: fx.slug, pipelineId: fx.pipelineId });
  assert.equal(w.code, 5);
  assert.ok(calls.includes(`POST /workflow/${wfIdOf(fx)}/cancel`));
  const logs = [];
  const root = dir;
  mkdirSync(join(root, '.local'), { recursive: true });
  writeFileSync(join(root, '.local', 'circleci-ledger.json'), JSON.stringify({ pipelines: { old: { artifacts: 0, cache: 1200000000, workspace: 0 } } }));
  assert.equal(await main(['fetch', '--pipeline', fx.pipelineId, '--out', join(dir, 'o3')], { root, env: { FW_CIRCLECI_SLUG: fx.slug }, ctx: { fetchFn: fixtureFetch(fx.api), getToken: () => 't', sleep: async () => {} }, log: (l) => logs.push(l) }), 5);
});

test('wait: a cancelled workflow is not a pass (exit 4, Lean waitStep)', async () => {
  const fx = loadFixture('premise-tests');
  const api = JSON.parse(JSON.stringify(fx.api));
  api.routes[wfRoute(fx)].items[0].status = 'canceled';
  const { ctx } = ctxOf(fx, { fetchFn: fixtureFetch(api) });
  assert.equal((await waitPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId })).code, 4);
});

test('timings.json carries the bytes a job saved', () => {
  const d = timingsDoc({ spansText: '', job: 'j', cls: 'c', sha: 's', digest: null, cacheBytes: 5, workspaceBytes: 7 });
  assert.deepEqual(d.bytes, { cache: 5, workspace: 7 });
});
