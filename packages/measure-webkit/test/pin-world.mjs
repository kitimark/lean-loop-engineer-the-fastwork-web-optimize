import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ConditionOwner } from '../src/device-thermal-pin.mjs';

export const T0 = 1_800_000_000_000;
export const fakeWorld = ({ dieOn = ['SIGTERM'], listOk = true, spawnLives = true, ackOnTerm = true, heldAfterS = 0 } = {}) => {
  const w = { t: T0, procs: new Map(), signals: [], spawned: [], runs: [], nextPid: 4000, log: '', heldAt: new Map() };
  const ps = (pid) => (w.procs.has(pid) ? { stat: 'S', start: w.procs.get(pid) } : null);
  w.opts = {
    python: '/fake/python',
    readLog: () => w.log + [...w.heldAt].filter(([, at]) => w.t >= at).map(([pid]) => `fw-pin held pid=${pid}\n`).join(''),
    now: () => w.t,
    sleep: async (ms) => { w.t += ms; },
    ps,
    kill: (pid, sig) => {
      if (!w.procs.has(pid)) { const e = new Error('ESRCH'); e.code = 'ESRCH'; throw e; }
      w.signals.push(sig);
      if (sig === 'SIGTERM' && ackOnTerm && dieOn.includes(sig)) w.log += `fw-pin cleared pid=${pid}\n`;
      if (dieOn.includes(sig)) w.procs.delete(pid);
    },
    run: (cmd, args) => { w.runs.push(args); return listOk ? { status: 0, stdout: JSON.stringify([{ identifier: 'ThermalCondition', profiles: [{ identifier: 'ThermalSerious' }, { identifier: 'ThermalFair' }] }]), stderr: '' } : { status: 1, stdout: '', stderr: 'x' }; },
    spawn: (cmd, args, opts) => {
      const pid = w.nextPid++;
      w.spawned.push({ cmd, args, opts });
      if (spawnLives) { w.procs.set(pid, `start-${pid}`); w.heldAt.set(pid, w.t + heldAfterS * 1000); }
      return { pid, unref() {}, on() {}, kill() { w.procs.delete(pid); } };
    },
  };
  return w;
};
export const mkOwner = (w) => {
  const dir = mkdtempSync(join(tmpdir(), 'pin-'));
  return { dir, owner: new ConditionOwner({ dir, ...w.opts }) };
};
