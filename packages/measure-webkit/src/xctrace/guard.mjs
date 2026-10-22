// Bounded child processes of the xctrace probe (mac-safari-measure; incident inc-tmp-trace-leak: the probe left 27 kernel traces of 5-8 GB in
// the user temp folder and ran on for 41 minutes after its parent had gone). Every child runs in its own process group with TMPDIR inside the
// probe's own work directory, is looked at every `everyMs`, and is interrupted or killed as Lean's `probeAct` says (time past the recording's
// own limit, trace bytes over the cap, the parent process gone). Glue only: the decisions are Lean (Fw.Sup.Measure.probeAct, mayRecord).
import { spawn as nodeSpawn } from 'node:child_process';
import { lstatSync, mkdirSync, readdirSync, rmSync, statfsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { probeAct, mayRecord } from '../safari-local-reduce.mjs';

/** Size in MB (rounded up) of everything under `dir`; 0 when it does not exist. */
export function dirMB(dir) {
  let bytes = 0;
  const walk = (d) => {
    let names;
    try { names = readdirSync(d); } catch { return; }
    for (const n of names) {
      const p = join(d, n);
      let st;
      try { st = lstatSync(p); } catch { continue; }
      if (st.isDirectory()) walk(p); else bytes += st.size;
    }
  };
  walk(dir);
  return Math.ceil(bytes / 1048576);
}

/** Free MB of the volume holding `dir`. */
export const freeMB = (dir) => { const s = statfsSync(dir); return Math.floor((Number(s.bavail) * Number(s.bsize)) / 1048576); };

/** Whether a process with this pid exists. */
export const pidAlive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } };

/** The work directory must not sit in the user temp folder: a trace left there is nobody's to clean. */
export function assertOwnDir(workDir, tmp = [tmpdir(), process.env.TMPDIR].filter(Boolean)) {
  const w = resolve(workDir);
  for (const t of tmp) { const r = resolve(t); if (w === r || w.startsWith(r + sep)) throw new Error(`work dir ${w} is inside the temp folder ${r}; give an output dir of your own`); }
  return w;
}

/** Remove work dirs of earlier probes whose process is gone (a probe that was killed cannot clean up after itself). Returns the names removed. */
export function sweepStale(root, alive = pidAlive) {
  let names;
  try { names = readdirSync(root); } catch { return []; }
  const gone = [];
  for (const n of names) {
    const m = /^work-(\d+)$/.exec(n);
    if (m && !alive(Number(m[1]))) { rmSync(join(root, n), { recursive: true, force: true }); gone.push(n); }
  }
  return gone;
}

/**
 * A guard over the work directory `workDir`. `ppid` is the parent the probe started under; `getPpid` is read at every look.
 * @returns {{workDir:string, tmpDir:string, exec:Function, killAll:Function, wipe:Function, roomOk:Function, alive:Function, watchParent:Function}}
 */
export function makeGuard({ workDir, ppid = process.ppid, getPpid = () => process.ppid, spawn = nodeSpawn, kill = process.kill.bind(process), everyMs = 2000, now = Date.now, sizeMB = dirMB, free = freeMB }) {
  const tmpDir = join(workDir, 'tmp');
  mkdirSync(tmpDir, { recursive: true });
  const live = new Set();
  const alive = () => getPpid() === ppid;
  const group = (pid, sig) => { try { kill(-pid, sig); } catch { /* the group is gone */ } };

  /**
   * Run `cmd` in its own process group; `limitS` is the time the command is meant to take (the recorder's `--time-limit`).
   * @returns {{code:any, out:string, err:string, interrupted:boolean, killed:object|null, maxMB:number}} `killed` is the look that made Lean say kill
   */
  async function exec(cmd, args, { limitS }) {
    if (!alive()) throw new Error('the parent process is gone: nothing is started');
    const child = spawn(cmd, args, { detached: true, cwd: workDir, env: { ...process.env, TMPDIR: tmpDir }, stdio: ['ignore', 'pipe', 'pipe'] });
    live.add(child.pid);
    let out = '', err = '', interrupted = false, killed = null, maxMB = 0;
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    const t0 = now();
    const look = () => {
      const traceMB = sizeMB(workDir);
      maxMB = Math.max(maxMB, traceMB);
      const s = { elapsedS: Math.floor((now() - t0) / 1000), limitS, traceMB, parentAlive: alive() };
      const act = probeAct(s);
      if (act === 'kill' && !killed) { killed = s; group(child.pid, 'SIGKILL'); }
      else if (act === 'interrupt' && !interrupted && !killed) { interrupted = true; group(child.pid, 'SIGINT'); }
    };
    const timer = setInterval(look, everyMs);
    const code = await new Promise((res) => { child.on('close', (c, sig) => res(c ?? sig)); child.on('error', (e) => { err += e.message; res('error'); }); });
    clearInterval(timer);
    group(child.pid, 'SIGKILL'); // helpers the command left behind
    live.delete(child.pid);
    return { code, out, err, interrupted, killed, maxMB };
  }

  return {
    workDir, tmpDir, exec, alive,
    killAll: () => { for (const pid of live) group(pid, 'SIGKILL'); live.clear(); },
    /** Delete everything the probe wrote (traces, kernel traces in TMPDIR) and make the empty TMPDIR again. */
    wipe: () => { rmSync(workDir, { recursive: true, force: true }); mkdirSync(tmpDir, { recursive: true }); },
    roomOk: () => mayRecord(free(workDir)),
    /** Call `onOrphan` once when the probe's parent is gone. Returns the stop function. */
    watchParent(onOrphan, ms = everyMs) {
      const t = setInterval(() => { if (!alive()) { clearInterval(t); onOrphan(); } }, ms);
      return () => clearInterval(t);
    },
  };
}
