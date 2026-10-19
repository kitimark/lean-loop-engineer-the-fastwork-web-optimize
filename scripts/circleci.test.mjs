// scripts/circleci.test.mjs: the CircleCI glue against the Lean golden (packages/contracts/golden/ci/provider.jsonl, Lean
// Fw.Ci.Provider), the recorded-shape fixtures and the static facts of .circleci/. Run: node --test scripts/circleci.test.mjs
// No network, no Keychain: the API is a fixture and the token is a fake.
import { strict as assert } from 'node:assert';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { API, MIN_POLL_S, ROOT, call, circleConclusion, comparePairs, compare, credits, dryRun, fetchPipeline, fixtureFetch, githubConclusion, githubRuns, loadFixture, loadGolden, main, premiseDigest, redact, renderComparison, route, stops, storageMilli, timingsDoc, triggerRequest, urls, waitPipeline } from './circleci.mjs';

const g = loadGolden();
const here = dirname(fileURLToPath(import.meta.url));
const rowsOf = (op) => g.byOp[op] ?? [];
const toRun = (r) => ({ ...r, class: r.class });

test('the golden has every op the glue replays, and no more', () => {
  assert.deepEqual([...new Set(g.rows.map((r) => r.op))].sort(), ['compare', 'constants', 'credits', 'jobMap', 'rates', 'route', 'stop', 'storage']);
  assert.ok(g.rows.length >= 50);
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

test('wait: a finished pipeline of the fixture ends at once with exit 0', async () => {
  const fx = loadFixture('premise-tests');
  const { ctx } = ctxOf(fx);
  assert.equal((await waitPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, intervalS: MIN_POLL_S })).code, 0);
});

test('wait: polls no faster than 120 s whatever interval is asked', async () => {
  const fx = loadFixture('premise-tests');
  let polls = 0;
  const routes = { ...fx.api.routes };
  const wf = routes['GET /pipeline/pipe-1/workflow'];
  const base = fixtureFetch({ ...fx.api, routes });
  const fetchFn = async (url, init) => {
    if (String(url).endsWith('/pipeline/pipe-1/workflow') && ++polls === 1) return { status: 200, ok: true, headers: { get: () => null }, text: async () => JSON.stringify({ items: [{ ...wf.items[0], status: 'running' }] }) };
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
  api.routes['GET /pipeline/pipe-1/workflow'].items[0].status = 'failed';
  const { ctx } = ctxOf(fx, { fetchFn: fixtureFetch(api) });
  assert.equal((await waitPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId })).code, 1);
});

test('fetch + compare over the premise-tests fixture: equal verdicts, no finding, spans in the span format', async () => {
  const fx = loadFixture('premise-tests');
  const { ctx } = ctxOf(fx);
  const out = mkdtempSync(join(tmpdir(), 'fwcc-'));
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out, sha: fx.sha });
  assert.deepEqual(doc.runs.map((r) => r.job), ['engine-chromium', 'engine-playwright-webkit', 'verdict']);
  assert.deepEqual(doc.runs.map((r) => r.durMs), [150000, 180000, 45000]);
  assert.deepEqual(doc.runs.map((r) => r.queueMs), [9000, 8000, 5000]);
  const gh = githubRuns(g, fx.github, fx.github.digests);
  const cmp = comparePairs(g, gh, doc.runs);
  assert.equal(cmp.code, 0);
  assert.deepEqual(cmp.rows.map((r) => r.credits), [15, 18, 5]);
  assert.match(renderComparison(cmp.rows), /engine-chromium: verdicts equal; duration 1\.50x GitHub/);
  const steps = new Set(doc.spans.filter((s) => s.tool === 'circleci/engine-chromium').map((s) => s.step));
  for (const s of ['queue', 'checkout', 'node', 'pnpm', 'cache restore', 'deps install', 'test', 'upload (after the last step)', 'job']) assert.ok(steps.has(s), s);
  for (const s of doc.spans) assert.deepEqual(Object.keys(s), ['tool', 'step', 'startMs', 'durMs', 'exit', 'commit', 'load', 'host']);
  assert.equal(JSON.parse(readFileSync(join(out, 'run.json'), 'utf8')).schema, 'fw.circleci-run/1');
  assert.equal(doc.storage.stops.length, 0);
});

test('a digest that differs is a finding (exit 1); a missing side is not a pair (exit 2)', async () => {
  const fx = loadFixture('premise-tests');
  const { ctx } = ctxOf(fx);
  const doc = await fetchPipeline(ctx, { slug: fx.slug, pipelineId: fx.pipelineId, out: mkdtempSync(join(tmpdir(), 'fwcc-')), sha: fx.sha });
  const bad = githubRuns(g, fx.github, { ...fx.github.digests, 'engine (chromium)': 'deadbeef' });
  const cmp = comparePairs(g, bad, doc.runs);
  assert.equal(cmp.code, 1);
  assert.match(renderComparison(cmp.rows), /engine-chromium: FINDING verdicts differ/);
  assert.equal(comparePairs(g, githubRuns(g, { ...fx.github, headSha: 'other' }, fx.github.digests), doc.runs).code, 2);
  assert.equal(comparePairs(g, githubRuns(g, { ...fx.github, jobs: fx.github.jobs.slice(1) }, fx.github.digests), doc.runs).code, 2);
});

test('fetch refuses an artifact path that leaves the output directory', async () => {
  const fx = loadFixture('premise-tests');
  const api = JSON.parse(JSON.stringify(fx.api));
  api.routes[`GET /project/${fx.slug}/1/artifacts`].items[0].path = '../../evil.json';
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
  assert.match(text, /webkit-sim: verdicts equal; duration 0\.50x GitHub; queue github 60s, circleci 85s; credits 2000/);
  assert.equal(r.cmp.code, 0);
});

test('the GitHub and CircleCI statuses map to the Lean conclusions', () => {
  assert.deepEqual(['success', 'failed', 'infrastructure_fail', 'timedout', 'canceled', 'not_run', 'queued'].map(circleConclusion), ['pass', 'fail', 'fail', 'fail', 'not-run', 'not-run', 'not-run']);
  assert.deepEqual(['success', 'failure', 'timed_out', 'cancelled', 'skipped', null].map(githubConclusion), ['pass', 'fail', 'fail', 'not-run', 'not-run', 'not-run']);
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
