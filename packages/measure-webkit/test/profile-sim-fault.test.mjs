import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { isSocketTosFault, guardSocketFault } from '../src/profile/sim-cadence.mjs';

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
