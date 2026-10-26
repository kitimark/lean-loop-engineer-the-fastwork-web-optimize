import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cpuTimes, idlePct, loadStamp, resetLoadStamp } from '../src/load.mjs';

const cpu = (idle, busy) => ({ times: { user: busy, nice: 0, sys: 0, idle, irq: 0 } });

test('load: the stamp starts no child process and returns at once', () => {
  const src = readFileSync(new URL('../src/load.mjs', import.meta.url), 'utf8');
  assert.ok(!/child_process|spawn|exec/.test(src.replace(/^\/\/.*$/gm, '')), 'no child process in the load stamp code');
});

test('load: idle percent between two readings, null when no time passed', () => {
  const a = cpuTimes([cpu(100, 100), cpu(100, 100)]);
  const b = cpuTimes([cpu(160, 140), cpu(180, 120)]);
  assert.deepEqual(a, { idle: 200, total: 400 });
  assert.equal(idlePct(a, b), 70);
  assert.equal(idlePct(a, a), null);
});

test('load: first stamp has no idle share, the next one the share since the previous', () => {
  resetLoadStamp();
  let n = 0;
  const readings = [[cpu(0, 0)], [cpu(75, 25)]];
  const opts = { now: () => 1700000000000, loadavg: () => [87.456, 0, 0], cpus: () => readings[n++] };
  const s1 = loadStamp(opts), s2 = loadStamp(opts);
  assert.equal(s1.idle, null);
  assert.equal(s2.idle, 75);
  assert.equal(s1.load1, 87.46);
  assert.equal(s1.cpus, 1);
  assert.equal(s1.ts, '2023-11-14T22:13:20.000Z');
  resetLoadStamp();
});
