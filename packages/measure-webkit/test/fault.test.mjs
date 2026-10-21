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

test('the fault waits, then kills again and again until stopped', (t) => {
  // Mock timers: real ones lag under load (land 776c69c3 saw fewer than 3 kills in 80 ms at load ~30).
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
  const lines = [];
  let n = 0;
  const f = armFault({ kind: 'kill-proxy', afterMs: 20, everyMs: 10 }, { kill: () => { n++; }, log: (s) => lines.push(s), now: () => 'T' });
  t.mock.timers.tick(19);
  assert.equal(n, 0);
  t.mock.timers.tick(1);
  assert.equal(n, 1);
  t.mock.timers.tick(30);
  assert.equal(n, 4);
  f.stop();
  t.mock.timers.tick(40);
  assert.equal(n, 4, 'stopped');
  assert.ok(lines[0].includes('first kill at T'));
});
