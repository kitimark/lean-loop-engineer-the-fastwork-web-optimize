import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  END_MARGIN_S, SCROLL_RETRY_S, PASS_RETRY_S, LOAD_CEIL_CENTI, gateBoundS, retryFits, afterFailure, hostOk, afterPass, centi, stepGate,
} from '../src/sim-host.mjs';
import { onePassRetrying } from '../src/determinism.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/sim-host.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);

test('sim-host: constants match Lean', () => {
  const c = ops('constants')[0];
  assert.equal(END_MARGIN_S, c.endMarginS);
  assert.equal(LOAD_CEIL_CENTI, c.loadCeilCenti);
  assert.equal(SCROLL_RETRY_S, c.scrollRetryS);
  assert.equal(PASS_RETRY_S, c.passRetryS);
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
