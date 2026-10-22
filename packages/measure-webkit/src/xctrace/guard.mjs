import { spawn as nodeSpawn, execFileSync } from 'node:child_process';
import { lstatSync, mkdirSync, readdirSync, rmSync, statfsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { probeAct, mayRecord } from '../safari-local-reduce.mjs';

export function dirMB(dir) {
  let bytes = 0;
  try { const st = lstatSync(dir); if (!st.isDirectory()) return Math.ceil(st.size / 1048576); } catch { return 0; }
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

// Foundation (so xctrace) asks `confstr(_CS_DARWIN_USER_TEMP_DIR)` first and reads TMPDIR only when that fails
// (swift-foundation String+Path.swift:491-510@9539423), so the recorder's kernel traces land here whatever TMPDIR says.
export function userTempDir(run = execFileSync) {
  try { const d = String(run('getconf', ['DARWIN_USER_TEMP_DIR'], { encoding: 'utf8', timeout: 5000 })).trim(); return d || null; } catch { return null; }
}

export const isKtrace = (name) => /^instruments.*\.ktrace$/.test(name);

export function listKtraces(dir) {
  if (!dir) return [];
  try { return readdirSync(dir).filter(isKtrace); } catch { return []; }
}

export const freeMB = (dir) => { const s = statfsSync(dir); return Math.floor((Number(s.bavail) * Number(s.bsize)) / 1048576); };

export const pidAlive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } };

export function assertOwnDir(workDir, tmp = [tmpdir(), process.env.TMPDIR].filter(Boolean)) {
  const w = resolve(workDir);
  for (const t of tmp) { const r = resolve(t); if (w === r || w.startsWith(r + sep)) throw new Error(`work dir ${w} is inside the temp folder ${r}; give an output dir of your own`); }
  return w;
}

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

export function makeGuard({ workDir, ppid = process.ppid, getPpid = () => process.ppid, spawn = nodeSpawn, kill = process.kill.bind(process), everyMs = 2000, now = Date.now, sizeMB = dirMB, free = freeMB, userTmp = userTempDir(), list = listKtraces, clockMs = Date.now }) {
  const tmpDir = join(workDir, 'tmp');
  mkdirSync(tmpDir, { recursive: true });
  const live = new Set();
  const alive = () => getPpid() === ppid;
  let seen = new Set(list(userTmp));
  let since = clockMs() - 1000;
  const mark = () => { seen = new Set(list(userTmp)); since = clockMs() - 1000; };
  const mine = () => list(userTmp).filter((n) => {
    if (seen.has(n)) return false;
    try { return lstatSync(join(userTmp, n)).birthtimeMs >= since; } catch { return false; }
  }).map((n) => join(userTmp, n));
  const userMB = () => mine().reduce((a, p) => a + sizeMB(p), 0);
  const group = (pid, sig) => { try { kill(-pid, sig); } catch {} };

  async function exec(cmd, args, { limitS }) {
    if (!alive()) throw new Error('the parent process is gone: nothing is started');
    const child = spawn(cmd, args, { detached: true, cwd: workDir, env: { ...process.env, TMPDIR: tmpDir }, stdio: ['ignore', 'pipe', 'pipe'] });
    live.add(child.pid);
    let exited = false;
    child.on('exit', () => { exited = true; group(child.pid, 'SIGKILL'); live.delete(child.pid); });
    let out = '', err = '', interrupted = false, killed = null, maxMB = 0;
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    const t0 = now();
    const look = () => {
      if (exited) return;
      const traceMB = sizeMB(workDir) + userMB();
      maxMB = Math.max(maxMB, traceMB);
      const s = { elapsedS: Math.floor((now() - t0) / 1000), limitS, traceMB, parentAlive: alive() };
      const act = probeAct(s);
      if (act === 'kill' && !killed) { killed = s; group(child.pid, 'SIGKILL'); }
      else if (act === 'interrupt' && !interrupted && !killed) { interrupted = true; group(child.pid, 'SIGINT'); }
    };
    const timer = setInterval(look, everyMs);
    const code = await new Promise((res) => { child.on('close', (c, sig) => res(c ?? sig)); child.on('error', (e) => { err += e.message; res('error'); }); });
    clearInterval(timer);
    live.delete(child.pid);
    return { code, out, err, interrupted, killed, maxMB };
  }

  return {
    workDir, tmpDir, exec, alive,
    killAll: () => { for (const pid of live) group(pid, 'SIGKILL'); live.clear(); },
    wipe: () => {
      for (const p of mine()) rmSync(p, { recursive: true, force: true });
      rmSync(workDir, { recursive: true, force: true }); mkdirSync(tmpDir, { recursive: true });
      mark();
    },
    leaked: mine,
    roomOk: () => mayRecord(free(workDir)),
    watchParent(onOrphan, ms = everyMs) {
      const t = setInterval(() => { if (!alive()) { clearInterval(t); onOrphan(); } }, ms);
      return () => clearInterval(t);
    },
  };
}
