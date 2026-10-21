// xctrace-ci-probe: the I/O around `xcrun xctrace` (glue; no decision logic). Every call has a deadline and its own process group,
// because xctrace hung without any output when the Simulator device was shut down (probe, 2026-10-22).
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, statSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { sleep } from '../sim.mjs';
import { recordArgs, WANTED_SCHEMA } from './arms.mjs';

// every recorder this process started: killed (whole process group) when the process ends, so no xctrace outlives the harness
const LIVE = new Map();
/** Signal a recorder's process group. A group started under `sudo` belongs to root, so it is signalled through `sudo -n kill`. */
function killGroup(pid, sig, sudo) {
  try { process.kill(-pid, sig); return; } catch { /* gone, or root's */ }
  if (sudo) spawnSync('sudo', ['-n', 'kill', `-${sig.replace('SIG', '')}`, '--', `-${pid}`], { timeout: 5000 });
}
process.on('exit', () => { for (const [pid, sudo] of LIVE) killGroup(pid, 'SIGKILL', sudo); });

const START_RE = /Ctrl-C|recording started|tracing started|Recording\.\.\./i;

/** Run a command to the end under a deadline; the process is killed at the deadline. Returns {status, stdout, stderr, timedOut}. */
export function runBounded(cmd, args, { timeoutMs = 120000, maxBuffer = 256 * 1024 * 1024 } = {}) {
  const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: timeoutMs, killSignal: 'SIGKILL', maxBuffer });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '', timedOut: r.error?.code === 'ETIMEDOUT' };
}

/**
 * Start one recording. Resolves when xctrace says it is recording (or after `startMs`, with started=false).
 * `stop()` sends SIGINT (the Ctrl-C of the xctrace docs) to the group, waits `stopMs`, then kills the group.
 */
export async function startRecording(arm, { udid, out, sudo = false, startMs = 60000, stopMs = 90000, limitS = 90, log }) {
  const args = recordArgs(arm, { udid, out, limitS });
  const [cmd, argv] = sudo ? ['sudo', ['-n', 'xcrun', ...args]] : ['xcrun', args];
  const child = spawn(cmd, argv, { detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let text = '', exited = null;
  const feed = (b) => { text += b.toString(); };
  child.stdout.on('data', feed);
  child.stderr.on('data', feed);
  LIVE.set(child.pid, sudo);
  const done = new Promise((res) => child.on('close', (code, sig) => { exited = { code, sig }; LIVE.delete(child.pid); res(exited); }));
  const t0 = Date.now();
  while (!exited && !START_RE.test(text) && Date.now() - t0 < startMs) await sleep(250);
  const started = !exited && START_RE.test(text);
  log(`  xctrace ${arm.id}${sudo ? ' (sudo)' : ''}: ${started ? 'recording' : exited ? `exited early (${exited.code ?? exited.sig})` : 'no start line'} after ${Date.now() - t0} ms`);
  const group = (sig) => killGroup(child.pid, sig, sudo);
  return {
    started, startedAt: Date.now(), get output() { return text; }, get exited() { return exited; },
    async stop() {
      if (!exited) group('SIGINT');
      // a recorder that never said it was recording gets 5 s after SIGINT, not the full stop time
      const r = await Promise.race([done, sleep(started ? stopMs : 5000).then(() => null)]);
      if (!r) { group('SIGKILL'); await Promise.race([done, sleep(5000)]); return { ...(exited ?? {}), killed: true }; }
      return { ...r, killed: false };
    },
  };
}

/** `xctrace export --toc` and the wanted tables of run 1 into `dir`. Returns {schemas, tables:[{schema, file, bytes, status}]}. */
export function exportTrace(trace, dir, { log, exportMs = 120000, sudo = false } = {}) {
  mkdirSync(dir, { recursive: true });
  const x = (args, file) => {
    const [cmd, argv] = sudo ? ['sudo', ['-n', 'xcrun', 'xctrace', 'export', ...args]] : ['xcrun', ['xctrace', 'export', ...args]];
    return runBounded(cmd, [...argv, '--output', file], { timeoutMs: exportMs });
  };
  const tocFile = join(dir, 'toc.xml');
  const t = x(['--input', trace, '--toc'], tocFile);
  log(`  export toc: status ${t.status}${t.timedOut ? ' (timed out)' : ''} ${t.stderr.trim().split('\n').slice(-1)[0] ?? ''}`);
  let toc = '';
  try { toc = readFileSync(tocFile, 'utf8'); } catch { /* none */ }
  const schemas = [...new Set([...toc.matchAll(/<table\b[^>]*\bschema="([^"]+)"/g)].map((m) => m[1]))];
  writeFileSync(join(dir, 'schemas.txt'), schemas.join('\n') + '\n');
  const tables = [];
  for (const schema of schemas.filter((s) => WANTED_SCHEMA.test(s))) {
    const file = join(dir, `${schema}.xml`);
    const r = x(['--input', trace, '--xpath', `/trace-toc/run[@number="1"]/data/table[@schema="${schema}"]`], file);
    let bytes = 0;
    try { bytes = statSync(file).size; } catch { /* none */ }
    tables.push({ schema, file: `${schema}.xml`, bytes, status: r.status, timedOut: r.timedOut });
  }
  log(`  exported ${tables.length} of ${schemas.length} tables (${tables.map((q) => `${q.schema}:${q.bytes}`).join(' ')})`);
  return { schemas, tables };
}
