import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { isSocketTosFault, guardSocketFault, driverEnd } from '../src/profile/sim-cadence.mjs';

const tos = Object.assign(new Error('setTypeOfService EINVAL'), { code: 'EINVAL', syscall: 'setTypeOfService', errno: -22 });

test('only the setTypeOfService EINVAL socket fault is a request-level fault', () => {
  assert.equal(isSocketTosFault(tos), true);
  assert.equal(isSocketTosFault(Object.assign(new Error('x'), { code: 'EINVAL', syscall: 'connect' })), false);
  assert.equal(isSocketTosFault(new Error('boom')), false);
  assert.equal(isSocketTosFault(null), false);
});

test('the guard logs the socket fault and keeps running, ends the process on any other error, and is removed by its release', () => {
  const proc = Object.assign(new EventEmitter(), { exitCode: null, exit(c) { this.exitCode = c; } });
  const logs = [];
  const release = guardSocketFault((l) => logs.push(l), proc);
  proc.emit('uncaughtException', tos);
  assert.equal(proc.exitCode, null);
  assert.match(logs[0], /ignored a socket fault/);
  const err = console.error;
  console.error = () => {};
  try { proc.emit('uncaughtException', new Error('boom')); } finally { console.error = err; }
  assert.equal(proc.exitCode, 1);
  release();
  assert.equal(proc.listenerCount('uncaughtException'), 0);
});

test('driverEnd: the driver off before the walk is touch-driver-not-ready, off during it is lost-mid-walk, never when not asked or on (Lean driverEnd)', () => {
  assert.deepEqual(driverEnd(true, false, 'no ready file after 480 s', 'start'), { fault: 'touch-driver-not-ready', cut: 'fault touch-driver-not-ready: no ready file after 480 s' });
  assert.deepEqual(driverEnd(true, false, 'swipeLate', 'walk'), { fault: 'lost-mid-walk', cut: 'fault lost-mid-walk: swipeLate' });
  for (const ph of ['start', 'walk']) {
    assert.equal(driverEnd(true, true, null, ph), null);
    assert.equal(driverEnd(false, false, 'x', ph), null);
    assert.equal(driverEnd(false, true, null, ph), null);
  }
});
