import { spawn as nodeSpawn, spawnSync } from 'node:child_process';
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// Pinned thermal state: rules (twins of Fw.Device.Thermal, golden device/thermal.jsonl) and the condition owner process.
const GOLDEN = readFileSync(new URL('../../contracts/golden/device/thermal.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
export const PIN = Object.freeze(GOLDEN.find((l) => l.kind === 'pinconsts'));

export const RANK = Object.freeze({ Nominal: 0, Fair: 1, Serious: 2, Critical: 3 });
export const pinTarget = (t) => t === 'Fair' || t === 'Serious';
export const profileOf = (t) => (t === 'Fair' ? 'ThermalFair' : t === 'Serious' ? 'ThermalSerious' : null);

export function pinWhy(target, held, lock, state, entered, waitedS) {
  if (!pinTarget(target)) return 'badTarget';
  if (lock === 'locked') return 'locked';
  if (!held) return 'notHeld';
  if (state === null || state === undefined) return waitedS < PIN.pinWaitMaxS ? 'unreadable' : 'timeout';
  if (state === 'Critical') return 'critical';
  if (RANK[target] < RANK[state]) return 'above';
  if (state === target) return 'onTarget';
  if (entered) return 'below';
  return waitedS < PIN.pinWaitMaxS ? 'rising' : 'timeout';
}
export const whyPin = (why) => (why === 'onTarget' ? 'go' : why === 'unreadable' || why === 'rising' ? 'wait' : 'stop');
export const pinGate = (target, held, lock, state, entered, waitedS) => whyPin(pinWhy(target, held, lock, state, entered, waitedS));

export function lanesRun(verdicts) {
  let n = 0;
  for (const v of verdicts) { if (v !== 'go') break; n++; }
  return n;
}
export const laneGates = (target, readings) => readings.map((r) => pinGate(target, r.held, r.lock, r.state, true, 0));
export const visitOk = (verdicts) => verdicts.length === 3 && verdicts.every((v) => v === 'go');
export const blockValid = (target, states) => pinTarget(target) && states.every((s) => s === target);

export function stopAct(alive, sent, sinceS) {
  if (!alive) return 'done';
  if (sent === 'none') return 'term';
  if (sent === 'term') return sinceS < PIN.stopGraceS ? 'wait' : 'kill';
  return sinceS < PIN.killGraceS ? 'wait' : 'stuck';
}
export const MAY_BE_ALIVE = Object.freeze({ idle: false, starting: true, held: true, stopping: true, stopped: false });
export const closeAct = (phase) => (MAY_BE_ALIVE[phase] ? 'stopOwner' : 'nothing');
export function endVerdict(target, ownerGone, back) {
  if (!ownerGone) return 'stuck';
  if (back === null || back === undefined) return 'unread';
  return RANK[back] < RANK[target] ? 'cleared' : 'heatRemains';
}
export const conditionSet = (ownerGone) => !ownerGone;
export const clearWait = (target, back, waitedS) => waitedS < PIN.clearWaitMaxS && !(back !== null && back !== undefined && RANK[back] < RANK[target]);
export const mayKill = (recPid, curPid, recStart, curStart) => recPid === curPid && recStart !== '' && recStart === curStart;

export const WHY_TEXT = Object.freeze({
  badTarget: 'the target thermal state cannot be induced (Fair or Serious only)',
  locked: 'the phone is locked: unlock it and keep it awake',
  notHeld: 'the condition owner process is not running, so the induced state is gone',
  unreadable: 'the thermal state could not be read',
  critical: 'the phone reports Critical (real heat above the induced floor)',
  above: 'the reported thermal state is above the target',
  below: 'the reported thermal state fell below the target',
  rising: 'the reported thermal state has not reached the target yet',
  timeout: 'the reported thermal state did not reach the target in time',
  onTarget: 'the reported thermal state is the target',
});

export class PinStop extends Error {
  constructor(why, phase, reading) {
    super(`pinned thermal state refused at ${phase}: ${WHY_TEXT[why]}${reading?.state ? ` (reads ${reading.state})` : ''}`);
    this.why = why;
    this.phase = phase;
    this.pin = true;
  }
}

/** pid, state letter and start time of a process, or null when there is no such process. */
export function psInfo(pid, { run = spawnSync } = {}) {
  const r = run('ps', ['-o', 'stat=,lstart=', '-p', String(pid)], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' } });
  const m = /^\s*(\S+)\s+(.+?)\s*$/.exec(r.stdout || '');
  return m ? { stat: m[1], start: m[2] } : null;
}

/** The condition list says whether a profile exists in group ThermalCondition. */
export function profileListed(listJson, profile) {
  const groups = typeof listJson === 'string' ? JSON.parse(listJson) : listJson;
  return Array.isArray(groups) && groups.some((g) => g.identifier === 'ThermalCondition' && (g.profiles ?? []).some((p) => p.identifier === profile));
}

const OWNER_FILE = 'pin-owner.json';
const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));

/** One process we start holds the induced condition: `pymobiledevice3 developer dvt condition set <profile> --userspace`.
 *  It is signalled only after its recorded pid and start time match the live process. */
export class ConditionOwner {
  constructor({ dir, log = () => {}, cli = process.env.FW_PYMD3 || 'pymobiledevice3', spawn = nodeSpawn, run = spawnSync, ps = psInfo, kill = process.kill.bind(process), now = Date.now, sleep = sleepMs } = {}) {
    Object.assign(this, { dir, log, cli, spawn, run, ps, kill, now, sleep });
    this.phase = 'idle';
    this.rec = null;
    this.recFile = join(dir, OWNER_FILE);
  }

  list() {
    const r = this.run(this.cli, ['developer', 'dvt', 'condition', 'list', '--userspace'], { encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024 });
    if (r.status !== 0) throw new Error(`condition list exited ${r.status ?? r.error?.code ?? 'none'}`);
    return JSON.parse(r.stdout);
  }

  save(patch) {
    this.rec = { ...this.rec, ...patch };
    mkdirSync(this.dir, { recursive: true });
    writeFileSync(this.recFile, JSON.stringify(this.rec, null, 1) + '\n');
  }

  /** The process we recorded is still the same live process. */
  alive() {
    if (!this.rec || this.rec.stoppedAt) return false;
    const p = this.ps(this.rec.pid);
    return p !== null && !p.stat.startsWith('Z') && mayKill(this.rec.pid, this.rec.pid, this.rec.start, p.start);
  }

  signal(sig) {
    if (!this.alive()) return false;
    try { this.kill(this.rec.pid, sig); return true; } catch { return false; }
  }

  async start({ profile, target }) {
    if (!profile) throw new Error(`no profile for ${target}`);
    this.phase = 'starting';
    if (!profileListed(this.list(), profile)) throw new Error(`condition list has no ${profile} in ThermalCondition`);
    mkdirSync(this.dir, { recursive: true });
    const out = openSync(join(this.dir, 'pin-owner.log'), 'a');
    let child;
    try {
      child = this.spawn(this.cli, ['developer', 'dvt', 'condition', 'set', profile, '--userspace'], { detached: true, stdio: ['ignore', out, out] });
    } finally { closeSync(out); }
    child.unref?.();
    child.on?.('error', () => {});
    const p = this.ps(child.pid);
    if (!p) { try { child.kill?.('SIGTERM'); } catch { /* the handle is ours */ } throw new Error('the condition owner process is not running right after the spawn'); }
    this.rec = null;
    this.save({ pid: child.pid, start: p.start, profile, target, spawnedAt: new Date(this.now()).toISOString(), stoppedAt: null });
    this.log(`condition owner started: pid ${child.pid}, ${profile}`);
    return this.rec;
  }

  /** Stop an owner a crashed run left behind, if the recorded pid and start time still match. */
  async recover() {
    if (!existsSync(this.recFile)) return false;
    const rec = JSON.parse(readFileSync(this.recFile, 'utf8'));
    if (rec.stoppedAt) return false;
    this.rec = rec;
    if (!this.alive()) { this.save({ stoppedAt: new Date(this.now()).toISOString(), stoppedBy: 'recover-gone' }); return false; }
    this.log(`an owner from an earlier run is alive (pid ${rec.pid}); stopping it`);
    const r = await this.stop();
    if (!r.gone) throw new Error(`the owner from an earlier run (pid ${rec.pid}) did not stop`);
    return true;
  }

  /** TERM first, KILL after the grace, until the process is gone or reported stuck. */
  async stop() {
    this.phase = 'stopping';
    let sent = 'none', sentAt = null;
    const signals = [];
    for (;;) {
      const sinceS = sentAt === null ? 0 : (this.now() - sentAt) / 1000;
      const act = stopAct(this.alive(), sent, sinceS);
      if (act === 'done') break;
      if (act === 'stuck') { this.log(`condition owner pid ${this.rec.pid} did not exit after SIGKILL`); return { gone: false, signals }; }
      if (act === 'term' || act === 'kill') {
        const sig = act === 'term' ? 'SIGTERM' : 'SIGKILL';
        this.signal(sig);
        signals.push(sig);
        sent = act;
        sentAt = this.now();
      } else await this.sleep(250);
    }
    this.phase = 'stopped';
    if (this.rec) this.save({ stoppedAt: new Date(this.now()).toISOString(), signals });
    return { gone: true, signals };
  }

  /** Last resort when the process exits: one identity-checked SIGTERM, no waiting. */
  termSync() { if (MAY_BE_ALIVE[this.phase]) this.signal('SIGTERM'); }
}
