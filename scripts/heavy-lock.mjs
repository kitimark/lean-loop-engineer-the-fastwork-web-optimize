#!/usr/bin/env node
// Heavy-job lock for lean/scripts/check.sh and scripts/fwcore-build.sh (task local-mem-budget).
//
//   node scripts/heavy-lock.mjs run [--kind <name>] -- <command> [args...]
//
// Runs <command> once the machine can take one more heavy job: FIFO queue, a cap of concurrent holders
// derived from the CPU count, free memory for the job plus a reserve, and swap below a limit. An idle
// machine always admits. FW_HEAVY_LOCK=off skips the lock; after FW_HEAVY_MAX_WAIT_S seconds (default 1800, Lean `maxWaitS`) the job is refused with exit 75 and the reason (never run anyway); FW_HEAVY_HELD=1 (set for the child) makes nested
// calls run directly.
//
// TS/JS STAND-IN: `decide` and `prune` mirror `Fw.Sched.Heavy.verdict` / `prune`
// (lean/Fw/Sched/Heavy.lean, proved there). scripts/heavy-lock.test.mjs replays
// packages/contracts/golden/sched/heavy.jsonl against them; replace by `fwcore` when it serves
// `sched.heavy`. The rest (files, ps, memory_pressure, sysctl) is I/O glue and holds no decision logic.
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, watch, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/** Defaults equal `Fw.Sched.Heavy.Params`. */
export const DEFAULT_PARAMS = { capMax: 2, cpusPerJob: 4, jobMB: 5000, reserveMB: 2048, swapPct: 60, maxWaitS: 1800 };

export function cap(p, cpus) {
  return Math.max(1, Math.min(p.capMax, Math.floor(cpus / p.cpusPerJob)));
}

export function swapHigh(p, o) {
  return o.swapTotalMB > 0 && p.swapPct * o.swapTotalMB <= 100 * o.swapUsedMB;
}

/** `Fw.Sched.Heavy.waitOr`: wait, or after `maxWaitS` seconds waited, time out. */
function waitOr(p, waited, w) {
  return { verdict: p.maxWaitS <= waited ? 'timeout' : 'wait', ...w };
}

/** `Fw.Sched.Heavy.verdict`: `n` live holders, `rank` askers ahead in the queue, `waited` seconds waited. */
export function decide(p, o, n, rank, waited = 0) {
  if (rank > 0) return waitOr(p, waited, { why: 'queued', ahead: rank });
  if (n === 0) return { verdict: 'admit' };
  const c = cap(p, o.cpus);
  if (c <= n) return waitOr(p, waited, { why: 'cap', running: n, limit: c });
  if (swapHigh(p, o)) return waitOr(p, waited, { why: 'swap' });
  if (o.freeMB < p.jobMB + p.reserveMB) {
    return waitOr(p, waited, { why: 'memory', needMB: p.jobMB + p.reserveMB, freeMB: o.freeMB });
  }
  return { verdict: 'admit' };
}

/** `Fw.Sched.Heavy.prune`: keep holders whose pid and start time both match a live process. */
export function prune(live, holders) {
  return holders.filter((h) => live.some((l) => l.pid === h.pid && l.start === h.start));
}

export function describe(w) {
  switch (w.why) {
    case 'queued': return `${w.ahead} heavy job(s) queued ahead`;
    case 'cap': return `${w.running} heavy job(s) running, cap ${w.limit}`;
    case 'swap': return 'swap is heavily used';
    case 'memory': return `free memory ${w.freeMB} MB, need ${w.needMB} MB`;
    default: return 'waiting';
  }
}

// ---- I/O glue ----

function startOf(pid) {
  try {
    const s = execFileSync('ps', ['-o', 'lstart=', '-p', String(pid)], { encoding: 'utf8' }).trim();
    if (!s) return null;
    const t = Date.parse(s);
    return Number.isNaN(t) ? null : Math.floor(t / 1000);
  } catch {
    return null;
  }
}

function observe() {
  const cpus = os.cpus().length;
  let freeMB = Math.floor(os.freemem() / 1048576);
  try {
    const out = execFileSync('memory_pressure', [], { encoding: 'utf8' });
    const m = /free percentage:\s*(\d+)%/.exec(out);
    if (m) freeMB = Math.floor((Number(m[1]) / 100) * (os.totalmem() / 1048576));
  } catch { /* not macOS: keep os.freemem */ }
  let swapUsedMB = 0;
  let swapTotalMB = 0;
  try {
    const out = execFileSync('sysctl', ['-n', 'vm.swapusage'], { encoding: 'utf8' });
    const t = /total = ([\d.]+)M/.exec(out);
    const u = /used = ([\d.]+)M/.exec(out);
    if (t && u) { swapTotalMB = Math.floor(Number(t[1])); swapUsedMB = Math.floor(Number(u[1])); }
  } catch { /* no swap info */ }
  return { cpus, freeMB, swapUsedMB, swapTotalMB };
}

function lockDir() {
  const common = execFileSync('git', ['rev-parse', '--git-common-dir'], { encoding: 'utf8' }).trim();
  return path.join(path.resolve(common), 'fw-heavy');
}

function readEntries(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const f of readdirSync(dir).sort()) {
    try { out.push({ file: path.join(dir, f), ...JSON.parse(readFileSync(path.join(dir, f), 'utf8')) }); } catch { /* racing writer */ }
  }
  return out;
}

function dropStale(entries) {
  const live = [];
  for (const e of entries) {
    const s = startOf(e.pid);
    if (s !== null && prune([{ pid: e.pid, start: s }], [e]).length === 1) live.push(e);
    else rmSync(e.file, { force: true });
  }
  return live;
}

/** Write `entry` to `dir/name` atomically (temp file in `root`, then rename), so a reader never sees half of it. */
function putAtomic(root, dir, name, entry) {
  const tmp = path.join(root, `.tmp-${process.pid}-${Date.now()}`);
  writeFileSync(tmp, JSON.stringify(entry));
  renameSync(tmp, path.join(dir, name));
}

async function acquire(kind) {
  const root = lockDir();
  const hd = path.join(root, 'holders');
  const qd = path.join(root, 'queue');
  mkdirSync(hd, { recursive: true });
  mkdirSync(qd, { recursive: true });
  const start = startOf(process.pid);
  if (start === null) throw new Error('cannot read this process\'s start time (ps lstart), so the lock cannot identify its holder');
  const me = { pid: process.pid, start, kind };
  const enqueue = () => {
    const name = `${String(Date.now()).padStart(15, '0')}-${process.pid}.json`;
    putAtomic(root, qd, name, me);
    return path.join(qd, name);
  };
  let ticket = enqueue();
  const params = {
    ...DEFAULT_PARAMS,
    ...(process.env.FW_HEAVY_CAP ? { capMax: Number(process.env.FW_HEAVY_CAP) } : {}),
    ...(process.env.FW_HEAVY_MAX_WAIT_S ? { maxWaitS: Number(process.env.FW_HEAVY_MAX_WAIT_S) } : {}),
  };
  const t0 = Date.now();
  let lastSaid = '';
  let lastAt = 0;
  for (;;) {
    const holders = dropStale(readEntries(hd));
    const queue = dropStale(readEntries(qd));
    let rank = queue.findIndex((q) => q.pid === me.pid);
    if (rank < 0) { ticket = enqueue(); rank = queue.length; } // the ticket was lost: go to the back of the queue, never to the head
    const waited = Math.floor((Date.now() - t0) / 1000);
    const d = decide(params, observe(), holders.length, rank, waited);
    if (d.verdict === 'admit') {
      putAtomic(root, hd, `${me.pid}.json`, me);
      rmSync(ticket, { force: true });
      if (waited >= 1) console.error(`heavy-lock: admitted after ${waited} s`);
      return () => rmSync(path.join(hd, `${me.pid}.json`), { force: true });
    }
    if (d.verdict === 'timeout') {
      rmSync(ticket, { force: true });
      throw new Error(`waited ${waited} s (limit ${params.maxWaitS} s), ${describe(d)}; not running the job (set FW_HEAVY_LOCK=off to skip the lock)`);
    }
    const say = describe(d);
    if (say !== lastSaid || Date.now() - lastAt > 30000) {
      console.error(`heavy-lock: waiting, ${say}`);
      lastSaid = say;
      lastAt = Date.now();
    }
    await new Promise((resolve) => {
      const timer = setTimeout(() => { w.close(); resolve(); }, 2000);
      const w = watch(hd, () => { clearTimeout(timer); w.close(); resolve(); });
    });
  }
}

async function main(argv) {
  const dash = argv.indexOf('--');
  if (argv[0] !== 'run' || dash < 0 || dash === argv.length - 1) {
    console.error('usage: heavy-lock.mjs run [--kind <name>] -- <command> [args...]');
    return 2;
  }
  const ki = argv.indexOf('--kind');
  const kind = ki >= 0 && ki < dash ? argv[ki + 1] : 'heavy';
  const cmd = argv.slice(dash + 1);
  let release = () => {};
  if (process.env.FW_HEAVY_LOCK !== 'off' && !process.env.FW_HEAVY_HELD) {
    try { release = await acquire(kind); } catch (e) { console.error(`heavy-lock: ${e.message}`); return 75; }
  }
  const child = spawn(cmd[0], cmd.slice(1), { stdio: 'inherit', env: { ...process.env, FW_HEAVY_HELD: '1' } });
  const fwd = (sig) => () => child.kill(sig);
  for (const s of ['SIGINT', 'SIGTERM']) process.on(s, fwd(s));
  return await new Promise((resolve) => {
    child.on('exit', (code, sig) => { release(); resolve(code ?? (sig ? 128 : 1)); });
    child.on('error', (e) => { release(); console.error(`heavy-lock: ${e.message}`); resolve(127); });
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then((c) => process.exit(c));
}
