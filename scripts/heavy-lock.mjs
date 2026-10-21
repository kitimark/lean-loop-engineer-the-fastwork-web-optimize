#!/usr/bin/env node
// Heavy-job lock for lean/scripts/check.sh and scripts/fwcore-build.sh (task local-mem-budget).
//
//   node scripts/heavy-lock.mjs run [--kind <name>] -- <command> [args...]
//
// Runs <command> once the machine can take one more heavy job: FIFO queue, a cap of concurrent holders
// derived from the CPU count, free memory for the job plus a reserve, and swap below a limit. An idle
// machine always admits. FW_HEAVY_LOCK=off skips the lock; FW_HEAVY_HELD=1 (set for the child) makes nested
// calls run directly.
//
// TS/JS STAND-IN: `decide` and `prune` mirror `Fw.Sched.Heavy.verdict` / `prune`
// (lean/Fw/Sched/Heavy.lean, proved there). scripts/heavy-lock.test.mjs replays
// packages/contracts/golden/sched/heavy.jsonl against them; replace by `fwcore` when it serves
// `sched.heavy`. The rest (files, ps, memory_pressure, sysctl) is I/O glue and holds no decision logic.
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, watch, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/** Defaults equal `Fw.Sched.Heavy.Params`. */
export const DEFAULT_PARAMS = { capMax: 2, cpusPerJob: 4, jobMB: 5000, reserveMB: 2048, swapPct: 60 };

export function cap(p, cpus) {
  return Math.max(1, Math.min(p.capMax, Math.floor(cpus / p.cpusPerJob)));
}

export function swapHigh(p, o) {
  return o.swapTotalMB > 0 && p.swapPct * o.swapTotalMB <= 100 * o.swapUsedMB;
}

/** `Fw.Sched.Heavy.verdict`: `n` live holders, `rank` askers ahead in the queue. */
export function decide(p, o, n, rank) {
  if (rank > 0) return { verdict: 'wait', why: 'queued', ahead: rank };
  if (n === 0) return { verdict: 'admit' };
  const c = cap(p, o.cpus);
  if (c <= n) return { verdict: 'wait', why: 'cap', running: n, limit: c };
  if (swapHigh(p, o)) return { verdict: 'wait', why: 'swap' };
  if (o.freeMB < p.jobMB + p.reserveMB) {
    return { verdict: 'wait', why: 'memory', needMB: p.jobMB + p.reserveMB, freeMB: o.freeMB };
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

async function acquire(kind) {
  const root = lockDir();
  const hd = path.join(root, 'holders');
  const qd = path.join(root, 'queue');
  mkdirSync(hd, { recursive: true });
  mkdirSync(qd, { recursive: true });
  const me = { pid: process.pid, start: startOf(process.pid) ?? 0, kind };
  const ticket = path.join(qd, `${String(Date.now()).padStart(15, '0')}-${process.pid}.json`);
  writeFileSync(ticket, JSON.stringify(me));
  const params = {
    ...DEFAULT_PARAMS,
    ...(process.env.FW_HEAVY_CAP ? { capMax: Number(process.env.FW_HEAVY_CAP) } : {}),
  };
  const maxWaitMs = Number(process.env.FW_HEAVY_MAX_WAIT_S ?? 1800) * 1000;
  const t0 = Date.now();
  let lastSaid = '';
  let lastAt = 0;
  for (;;) {
    const holders = dropStale(readEntries(hd));
    const queue = dropStale(readEntries(qd));
    const rank = queue.findIndex((q) => q.pid === me.pid);
    const d = decide(params, observe(), holders.length, rank < 0 ? 0 : rank);
    if (d.verdict === 'admit') {
      writeFileSync(path.join(hd, `${me.pid}.json`), JSON.stringify(me));
      rmSync(ticket, { force: true });
      if (Date.now() - t0 > 1000) console.error(`heavy-lock: admitted after ${Math.round((Date.now() - t0) / 1000)} s`);
      return () => rmSync(path.join(hd, `${me.pid}.json`), { force: true });
    }
    if (Date.now() - t0 > maxWaitMs) {
      console.error(`heavy-lock: waited ${Math.round(maxWaitMs / 1000)} s (${describe(d)}); running anyway`);
      rmSync(ticket, { force: true });
      return () => {};
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
  if (process.env.FW_HEAVY_LOCK !== 'off' && !process.env.FW_HEAVY_HELD) release = await acquire(kind);
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
