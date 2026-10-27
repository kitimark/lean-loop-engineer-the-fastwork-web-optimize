import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  END_MARGIN_S, SCROLL_NEED_S, PASS_NEED_S, NAV_WAIT_MS, LOAD_CEIL_CENTI, gateBoundS, retryFits, tabNeedS, tabFits, afterFailure, hostOk, afterPass, centi, stepGate,
  lagMs, blocked, frozen, clockStart, silenceMs, silenceStalled, failsIn, relaunchPlan,
} from '../src/sim-host.mjs';
import { inspectorReply } from '../src/inspector.mjs';
import { onePassRetrying } from '../src/determinism.mjs';
import { navigateTab } from '../src/wip.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/sim-host.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);

test('sim-host: constants are the Lean golden values', () => {
  const c = ops('constants')[0];
  assert.equal(END_MARGIN_S, c.endMarginS);
  assert.equal(LOAD_CEIL_CENTI, c.loadCeilCenti);
  assert.equal(SCROLL_NEED_S, c.scrollNeedS);
  assert.equal(PASS_NEED_S, c.passNeedS);
  assert.equal(NAV_WAIT_MS, c.navWaitMs);
  assert.ok([SCROLL_NEED_S, PASS_NEED_S, NAV_WAIT_MS].every((n) => Number.isInteger(n) && n > 0));
});

test('sim-host: the tab wait model (no deployed gate) replays the Lean vectors', () => {
  assert.ok(ops('tab').length >= 30);
  for (const g of ops('tab')) {
    assert.equal(tabNeedS(g.waitMs), g.needS, JSON.stringify(g));
    assert.equal(tabFits(g.elapsedS, g.waitMs, g.boundS), g.fits, JSON.stringify(g));
  }
});

test('sim-host: gate bound, retry fit, failure and host decisions replay the Lean vectors', () => {
  assert.ok(ops('gate').length >= 3 && ops('fits').length >= 30 && ops('failure').length >= 20 && ops('host').length >= 7);
  for (const g of ops('gate')) assert.equal(gateBoundS(g.stepMin), g.boundS);
  for (const g of ops('fits')) assert.equal(retryFits(g.elapsedS, g.needS, g.boundS), g.fits, JSON.stringify(g));
  for (const g of ops('failure')) assert.equal(afterFailure(g.tries, g.maxTries, g.elapsedS, g.needS, g.boundS), g.retry, JSON.stringify(g));
  for (const g of ops('host')) assert.equal(hostOk(g.loadCenti), g.ok, JSON.stringify(g));
});

test('sim-host: a pass is counted only on a fit host, and a refused host never yields a count', () => {
  assert.ok(ops('pass').length >= 30);
  for (const g of ops('pass')) {
    const v = afterPass(g.startCenti, g.endCenti, g.tries, g.maxTries, g.elapsedS, g.needS, g.boundS);
    assert.equal(v, g.verdict, JSON.stringify(g));
    assert.equal(v === 'count', g.counted);
    if (v === 'count') assert.ok(hostOk(g.startCenti) && hostOk(g.endCenti));
  }
});

test('sim-host: the step clock follows FW_MEASURE_T0_MS and FW_WK_STEP_MIN, and is unbounded without them', () => {
  const g = stepGate({ FW_MEASURE_T0_MS: '1000', FW_WK_STEP_MIN: '35' }, () => 61000);
  assert.equal(g.boundS, 2040);
  assert.equal(g.elapsedS(), 60);
  for (const env of [{}, { FW_MEASURE_T0_MS: '1000' }, { FW_WK_STEP_MIN: '35' }, { FW_MEASURE_T0_MS: 'x', FW_WK_STEP_MIN: '35' }, { FW_MEASURE_T0_MS: '1', FW_WK_STEP_MIN: '0' }]) {
    assert.equal(stepGate(env).boundS, null, JSON.stringify(env));
  }
  assert.equal(centi(1015.92), 101592);
});

const mkCtx = () => ({ check: async () => {}, c: { evaluate: async () => 'http://x/' }, setClient() {}, url: 'http://x/' });

test('onePassRetrying: a failed pass is not repeated when the repeat would end past the step bound', async () => {
  const env = { ...process.env };
  process.env.FW_MEASURE_T0_MS = String(Date.now() - 1700 * 1000);
  process.env.FW_WK_STEP_MIN = '35';
  try {
    const log = [];
    const ctx = mkCtx();
    ctx.c.evaluate = async () => { throw new Error('stalled'); };
    await assert.rejects(onePassRetrying(ctx, { log: (s) => log.push(s) }), /stalled/);
    assert.ok(log.some((l) => /no retry fits/.test(l)), log.join('\n'));
  } finally {
    for (const k of ['FW_MEASURE_T0_MS', 'FW_WK_STEP_MIN']) { if (env[k] === undefined) delete process.env[k]; else process.env[k] = env[k]; }
  }
});

test('navigateTab: a tab wait late in the step is still started (Lean SimHost.deployed has tab need 0)', async () => {
  const env = { ...process.env };
  process.env.FW_MEASURE_T0_MS = String(Date.now() - 2039 * 1000);
  process.env.FW_WK_STEP_MIN = '35';
  try {
    const fresh = { evaluate: async (e) => (e.includes('__fwNav === undefined') ? true : e.includes('readyState') ? 'complete' : 'nav'), close: async () => {} };
    const c = { evaluate: async () => 'nav', close: async () => {} };
    assert.equal(await navigateTab(c, 'http://x/', { waitMs: 480000, openTabFn: async () => fresh }), fresh);
  } finally {
    for (const k of ['FW_MEASURE_T0_MS', 'FW_WK_STEP_MIN']) { if (env[k] === undefined) delete process.env[k]; else process.env[k] = env[k]; }
  }
});

test('onePassRetrying: a pass retry decided 1 s after the last admitted second of a 35 min step is refused (PASS_NEED_S from the golden)', async () => {
  const env = { ...process.env };
  process.env.FW_MEASURE_T0_MS = String(Date.now() - (gateBoundS(35) - PASS_NEED_S + 1) * 1000);
  process.env.FW_WK_STEP_MIN = '35';
  try {
    const log = [];
    const ctx = mkCtx();
    ctx.c.evaluate = async () => { throw new Error('stalled'); };
    await assert.rejects(onePassRetrying(ctx, { log: (s) => log.push(s) }), /stalled/);
    assert.ok(log.some((l) => /pass attempt 1 failed and no retry fits/.test(l)), log.join('\n'));
  } finally {
    for (const k of ['FW_MEASURE_T0_MS', 'FW_WK_STEP_MIN']) { if (env[k] === undefined) delete process.env[k]; else process.env[k] = env[k]; }
  }
});

test('sim-host: the stall verdict skips a freeze (a late tick with no host call) and replays the Lean vectors', () => {
  assert.ok(ops('silence').length >= 10);
  for (const g of ops('silence')) {
    assert.equal(lagMs(g.tickMs, g.sinceMs), g.lagMs, JSON.stringify(g));
    assert.equal(blocked(g.tickMs, g.sinceMs), g.blocked, JSON.stringify(g));
    assert.equal(frozen(g.tickMs, g.sinceMs, g.hostCalls), g.frozen, JSON.stringify(g));
    assert.equal(clockStart(g.nowMs, g.lastOutMs, g.tickMs, g.sinceMs, g.hostCalls), g.clockStart, JSON.stringify(g));
    const silence = silenceMs(g.nowMs, g.lastOutMs, g.tickMs, g.sinceMs, g.hostCalls);
    assert.equal(silence, g.silenceMs, JSON.stringify(g));
    assert.equal(silenceStalled(silence, g.limitMs), g.stalled, JSON.stringify(g));
  }
  const run1 = ops('silence').find((g) => g.nowMs === 731000 && g.hostCalls === 0 && g.sinceMs === 705000);
  assert.deepEqual([run1.frozen, run1.stalled], [true, false], 'run 40364461242 job 1 would have gone on');
});

test('sim-host: failed probes before a freeze do not count, and the inspector reply follows the Lean vectors', () => {
  assert.ok(ops('streak').length >= 8);
  for (const g of ops('streak')) {
    const r = inspectorReply({ relaunched: false, fails: failsIn(g.frozen, g.fails), socket: g.socket, proxy: g.proxy, page: g.page });
    assert.equal(r.fails, g.next, JSON.stringify(g));
    assert.equal(r.dead, g.dead, JSON.stringify(g));
  }
});

test('sim-host: the relaunch after a reboot has no terminate step; the plan sums are the Lean totals', () => {
  assert.equal(ops('plan').length, 2);
  for (const g of ops('plan')) {
    assert.deepEqual(relaunchPlan(g.fresh), g.steps);
    assert.equal(relaunchPlan(g.fresh).reduce((a, x) => a + x.ms, 0), g.totalMs);
  }
  assert.equal(relaunchPlan(true).some((x) => x.name === 'terminate Safari'), false);
  assert.equal(relaunchPlan(false)[0].name, 'terminate Safari');
  assert.deepEqual(relaunchPlan(false).slice(1), relaunchPlan(true));
});
