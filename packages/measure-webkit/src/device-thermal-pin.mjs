import { spawn as nodeSpawn, spawnSync } from 'node:child_process';
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/thermal.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
export const PIN = Object.freeze(GOLDEN.find((l) => l.kind === 'pinconsts'));
export const DROP = Object.freeze(GOLDEN.find((l) => l.kind === 'dropconsts'));

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
export function endVerdict(target, ownerGone, acked, back) {
  if (!ownerGone) return 'stuck';
  if (!acked) return 'unconfirmed';
  if (back === null || back === undefined) return 'unread';
  return RANK[back] < RANK[target] ? 'cleared' : 'heatRemains';
}
export const conditionSet = (ownerGone, acked) => !(ownerGone && acked);
export const recoverAct = (hasRecord, alive, acked) => (!hasRecord ? 'nothing' : alive ? 'stopOwner' : acked ? 'nothing' : 'clearCycle');
export const clearWait = (target, back, waitedS) => waitedS < PIN.clearWaitMaxS && !(back !== null && back !== undefined && RANK[back] < RANK[target]);
export const mayKill = (recPid, curPid, recStart, curStart) => recPid === curPid && recStart !== '' && recStart === curStart;


/** Lean `termGate`: whether the stop may send its first SIGTERM (the owner has acknowledged its set). */
export function termGate(alive, setAcked, waitedS) {
  if (!alive) return 'gone';
  if (setAcked) return 'go';
  return waitedS < DROP.setWaitMaxS ? 'wait' : 'late';
}
/** Lean `droppedClear`: the phone reads the state it had before the pin, and that state is below the target. */
export function droppedClear(target, before, back) {
  if (before === null || before === undefined || back === null || back === undefined) return false;
  return back === before && RANK[back] < RANK[target];
}
const dropCleared = (target, usbDropped, ownerGone, acked, before, back) => usbDropped && ownerGone && !acked && droppedClear(target, before, back);
/** Lean `endVerdictDrop`. */
export const endVerdictDrop = (target, usbDropped, ownerGone, acked, before, back) =>
  (dropCleared(target, usbDropped, ownerGone, acked, before, back) ? 'clearedDrop' : endVerdict(target, ownerGone, acked, back));
/** Lean `conditionSetDrop`. */
export const conditionSetDrop = (target, usbDropped, ownerGone, acked, before, back) =>
  conditionSet(ownerGone, acked) && !dropCleared(target, usbDropped, ownerGone, acked, before, back);
/** Lean `recoverActD`: `d` is a USB drop with the phone already reading its pre-pin state. */
export const recoverActD = (hasRecord, alive, acked, d) => (hasRecord && !alive && !acked && d ? 'nothing' : recoverAct(hasRecord, alive, acked));
/** Lean `fallbackAct`: the stop command found no control server. */
export function fallbackAct(sessionAlive, sent, sinceS) {
  if (!sessionAlive) return 'recover';
  if (!sent) return 'term';
  return sinceS < DROP.sessionWaitS ? 'wait' : 'recover';
}

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
const USB_DROP = /userspace tunnel transport closed|ConnectionTerminatedError|DTX service channel is closed/;
const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));

/** The owner process: set the condition, hold the connection, and on SIGTERM clear it on that same connection, wait for a
 *  reply after the clear, print the acknowledgement and exit. MEASURED: a clear from another connection does nothing and an
 *  owner ended without this clear leaves the induced state on the phone. The imports are the pinned pymobiledevice3 11.44.0. */
export const OWNER_PY = `
import asyncio, os, signal, sys
from pymobiledevice3.remote import userspace_tunnel
from pymobiledevice3.services.dvt.instruments.condition_inducer import ConditionInducer
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider

async def main(profile):
    pid = os.getpid()
    rsd = await userspace_tunnel.establish_userspace_rsd(serial=None)
    async with DvtProvider(rsd) as dvt, ConditionInducer(dvt) as ci:
        await ci.set(profile)
        print("fw-pin held pid=%d" % pid, flush=True)
        stop = asyncio.Event()
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, stop.set)
        await stop.wait()
        await ci.clear()
        await ci.list()
        print("fw-pin cleared pid=%d" % pid, flush=True)

asyncio.run(main(sys.argv[1]))
`;

const pipxPython = (run) => {
  const r = run('pipx', ['environment', '--value', 'PIPX_LOCAL_VENVS'], { encoding: 'utf8' });
  if (r.status !== 0 || !r.stdout.trim()) throw new Error('pipx environment failed; set FW_PYMD3_PYTHON to the pymobiledevice3 venv python');
  return join(r.stdout.trim(), 'pymobiledevice3', 'bin', 'python');
};

/** One process we start holds the induced condition (OWNER_PY, run with the pymobiledevice3 venv python).
 *  It is signalled only after its recorded pid and start time match the live process. */
export class ConditionOwner {
  constructor({ dir, log = () => {}, cli = process.env.FW_PYMD3 || 'pymobiledevice3', python = process.env.FW_PYMD3_PYTHON || null, spawn = nodeSpawn, run = spawnSync, ps = psInfo, kill = process.kill.bind(process), now = Date.now, sleep = sleepMs, readLog } = {}) {
    Object.assign(this, { dir, log, cli, python, spawn, run, ps, kill, now, sleep });
    this.readLog = readLog ?? (() => (existsSync(join(dir, 'pin-owner.log')) ? readFileSync(join(dir, 'pin-owner.log'), 'utf8') : ''));
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

  /** The owner printed that it set the condition (the moment its clear handler exists). */
  setAcked(pid = this.rec?.pid) { return pid !== undefined && this.readLog().includes(`fw-pin held pid=${pid}`); }

  /** The owner's log says its connection to the phone closed (USB unplugged, phone asleep). Log text is I/O; the rule
   *  that uses it is `endVerdictDrop`. */
  usbDropped() { return USB_DROP.test(this.readLog().slice(this.rec?.logFrom ?? 0)); }

  /** The owner printed its clear acknowledgement (after a reply from the phone). */
  acked(pid = this.rec?.pid) { return pid !== undefined && this.readLog().includes(`fw-pin cleared pid=${pid}`); }

  signal(sig) {
    if (!this.alive()) return false;
    try { this.kill(this.rec.pid, sig); return true; } catch { return false; }
  }

  async start({ profile, target, before = null }) {
    if (!profile) throw new Error(`no profile for ${target}`);
    this.phase = 'starting';
    if (!profileListed(this.list(), profile)) throw new Error(`condition list has no ${profile} in ThermalCondition`);
    mkdirSync(this.dir, { recursive: true });
    const py = this.python ?? pipxPython(this.run);
    const logFrom = this.readLog().length;
    const out = openSync(join(this.dir, 'pin-owner.log'), 'a');
    let child;
    try {
      child = this.spawn(py, ['-c', OWNER_PY, profile], { detached: true, stdio: ['ignore', out, out] });
    } finally { closeSync(out); }
    child.unref?.();
    child.on?.('error', () => {});
    const p = this.ps(child.pid);
    if (!p) { try { child.kill?.('SIGTERM'); } catch { /* the handle is ours */ } throw new Error('the condition owner process is not running right after the spawn'); }
    this.rec = null;
    this.save({ pid: child.pid, start: p.start, profile, target, before, logFrom, spawnedAt: new Date(this.now()).toISOString(), stoppedAt: null, acked: false, usbDropped: false });
    this.log(`condition owner started: pid ${child.pid}, ${profile}`);
    return this.rec;
  }

  /** From the record an earlier run left (Lean recoverAct): stop a live owner, or run one set-and-clear cycle for an owner
   *  that ended without acknowledging its clear. */
  async recover({ read = () => null } = {}) {
    if (!existsSync(this.recFile)) return false;
    const rec = JSON.parse(readFileSync(this.recFile, 'utf8'));
    this.rec = rec;
    const alive = this.alive();
    const acked = rec.acked === true || this.acked(rec.pid);
    const dropped = rec.usbDropped === true || this.usbDropped();
    let d = false;
    if (!alive && !acked && dropped) { try { d = droppedClear(rec.target, rec.before ?? null, read() ?? null); } catch { d = false; } }
    const act = recoverActD(true, alive, acked, d);
    if (act === 'nothing') { if (!rec.stoppedAt) this.save({ stoppedAt: new Date(this.now()).toISOString(), stoppedBy: acked ? 'recover-gone' : 'recover-dropped', acked, usbDropped: dropped }); return false; }
    let done = false;
    if (act === 'stopOwner') {
      this.log(`an owner from an earlier run is alive (pid ${rec.pid}); stopping it`);
      const r = await this.stop();
      if (!r.gone) throw new Error(`the owner from an earlier run (pid ${rec.pid}) did not stop`);
      done = r.acked;
    }
    if (!done) {
      this.log(`the owner from an earlier run ended without confirming its clear; one set-and-clear cycle (${rec.profile})`);
      await this.start({ profile: rec.profile, target: rec.target, before: rec.before ?? null });
      const r = await this.stop();
      if (!r.gone || !r.acked) throw new Error('the clear cycle for the earlier run did not confirm; stop and check the phone by hand');
    }
    return true;
  }

  /** TERM first, KILL after the grace, until the process is gone or reported stuck. */
  async stop() {
    this.phase = 'stopping';
    let sent = 'none', sentAt = null;
    const signals = [];
    const w0 = this.now();
    for (;;) {
      const sinceS = sentAt === null ? 0 : (this.now() - sentAt) / 1000;
      const act = stopAct(this.alive(), sent, sinceS);
      if (act === 'done') break;
      if (act === 'term') {
        const g = termGate(true, this.setAcked(), Math.floor((this.now() - w0) / 1000));
        if (g === 'wait') { await this.sleep(250); continue; }
        if (g === 'late') this.log(`condition owner pid ${this.rec.pid} did not acknowledge its set in ${DROP.setWaitMaxS} s; signalling it anyway, the clear stays unconfirmed`);
      }
      if (act === 'stuck') { this.log(`condition owner pid ${this.rec.pid} did not exit after SIGKILL`); return { gone: false, acked: false, signals }; }
      if (act === 'term' || act === 'kill') {
        const sig = act === 'term' ? 'SIGTERM' : 'SIGKILL';
        this.signal(sig);
        signals.push(sig);
        sent = act;
        sentAt = this.now();
      } else await this.sleep(250);
    }
    this.phase = 'stopped';
    const acked = this.rec === null || this.acked();
    const usbDropped = this.rec !== null && this.usbDropped();
    if (this.rec) this.save({ stoppedAt: new Date(this.now()).toISOString(), signals, acked, usbDropped });
    return { gone: true, acked, signals, usbDropped };
  }

  /** Last resort when the process exits: one identity-checked SIGTERM, no waiting. */
  termSync() { if (MAY_BE_ALIVE[this.phase]) this.signal('SIGTERM'); }
}
