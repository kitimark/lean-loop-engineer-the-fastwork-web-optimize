import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ConditionOwner } from '../src/device-thermal-pin.mjs';

export const T0 = 1_800_000_000_000;
export const fakeWorld = ({ dieOn = ['SIGTERM'], listOk = true, spawnLives = true } = {}) => {
  const w = { t: T0, procs: new Map(), signals: [], spawned: [], runs: [], nextPid: 4000 };
  const ps = (pid) => (w.procs.has(pid) ? { stat: 'S', start: w.procs.get(pid) } : null);
  w.opts = {
    now: () => w.t,
    sleep: async (ms) => { w.t += ms; },
    ps,
    kill: (pid, sig) => {
      if (!w.procs.has(pid)) { const e = new Error('ESRCH'); e.code = 'ESRCH'; throw e; }
      w.signals.push(sig);
      if (dieOn.includes(sig)) w.procs.delete(pid);
    },
    run: (cmd, args) => { w.runs.push(args); return listOk ? { status: 0, stdout: JSON.stringify([{ identifier: 'ThermalCondition', profiles: [{ identifier: 'ThermalSerious' }, { identifier: 'ThermalFair' }] }]), stderr: '' } : { status: 1, stdout: '', stderr: 'x' }; },
    spawn: (cmd, args, opts) => {
      const pid = w.nextPid++;
      w.spawned.push({ cmd, args, opts });
      if (spawnLives) w.procs.set(pid, `start-${pid}`);
      return { pid, unref() {}, on() {}, kill() { w.procs.delete(pid); } };
    },
  };
  return w;
};
export const mkOwner = (w) => {
  const dir = mkdtempSync(join(tmpdir(), 'pin-'));
  return { dir, owner: new ConditionOwner({ dir, ...w.opts }) };
};
