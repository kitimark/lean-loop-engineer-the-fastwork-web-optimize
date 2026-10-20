import { test } from 'node:test';
import assert from 'node:assert/strict';
import { faultPlan, armFault, FAULTS } from '../src/fault.mjs';

test('no fault unless FW_WK_FAULT is set; unknown names and bad delays are refused', () => {
  assert.equal(faultPlan({}), null);
  assert.equal(faultPlan({ FW_WK_FAULT: '' }), null);
  assert.deepEqual(faultPlan({ FW_WK_FAULT: 'kill-safari' }), { kind: 'kill-safari', afterMs: 120000, everyMs: 2000 });
  assert.equal(faultPlan({ FW_WK_FAULT: 'kill-proxy', FW_WK_FAULT_AFTER_S: '30' }).afterMs, 30000);
  assert.throws(() => faultPlan({ FW_WK_FAULT: 'kill-everything' }), /kill-safari, kill-proxy/);
  assert.throws(() => faultPlan({ FW_WK_FAULT: 'kill-proxy', FW_WK_FAULT_AFTER_S: '-1' }), /seconds/);
  assert.deepEqual([...FAULTS], ['kill-safari', 'kill-proxy']);
});

test('the fault waits, then kills again and again until stopped', async () => {
  const lines = [];
  let n = 0;
  const f = armFault({ kind: 'kill-proxy', afterMs: 20, everyMs: 10 }, { kill: () => { n++; }, log: (s) => lines.push(s), now: () => 'T' });
  await new Promise((r) => setTimeout(r, 5));
  assert.equal(n, 0);
  await new Promise((r) => setTimeout(r, 80));
  f.stop();
  const seen = n;
  assert.ok(seen >= 3);
  await new Promise((r) => setTimeout(r, 40));
  assert.equal(n, seen, 'stopped');
  assert.ok(lines[0].includes('first kill at T'));
});
