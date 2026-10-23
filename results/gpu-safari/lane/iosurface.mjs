// IOSurface regions of the Simulator's WebKit GPU and WebContent processes, read with `vmmap -summary <pid>` (read-only, no Instruments).
// vmmap's IOSurface row: VIRTUAL RESIDENT DIRTY SWAPPED VOLATILE NONVOL EMPTY REGION COUNT. The count and the virtual size follow the surfaces the
// compositor holds; they are a proxy for allocation per state, not an allocation trace (a transient inside a push is not seen).
import { execFileSync, spawnSync } from 'node:child_process';

const UNIT = { K: 1024, M: 1024 ** 2, G: 1024 ** 3 };
/** "277.5M" -> bytes, "0K" -> 0. */
export function bytesOf(tok) {
  const m = /^([0-9.]+)([KMG])?$/.exec(tok);
  if (!m) return null;
  return Math.round(Number(m[1]) * (m[2] ? UNIT[m[2]] : 1));
}

/** The IOSurface row of a `vmmap -summary` text, or null when the process has none. */
export function parseIOSurface(text) {
  const line = text.split('\n').find((l) => /^IOSurface\s/.test(l));
  if (!line) return null;
  const t = line.trim().split(/\s+/);
  if (t.length < 9) return null;
  const [virtual, resident, dirty, swapped, , , empty] = t.slice(1, 8).map(bytesOf);
  return { virtualBytes: virtual, residentBytes: resident, dirtyBytes: dirty, swappedBytes: swapped, emptyBytes: empty, regions: Number(t[8]) };
}

/** Simulator service pids by the base64 service name in their command line (WebKit.GPU, WebKit.WebContent); host processes are not read. */
export function simServicePids(psText) {
  const want = { gpu: 'com.apple.WebKit.GPU', content: 'com.apple.WebKit.WebContent' };
  const out = { gpu: [], content: [] };
  for (const l of psText.split('\n')) {
    if (!l.includes('SimulatorRuntime')) continue;
    const pid = Number(l.trim().split(/\s+/)[0]);
    const b64 = l.trim().split(/\s+/).pop();
    let name = '';
    try { name = JSON.parse(Buffer.from(b64, 'base64').toString('utf8')).serviceName ?? ''; } catch { continue; }
    for (const [k, v] of Object.entries(want)) if (name === v) out[k].push(pid);
  }
  return out;
}

/** One sample: the IOSurface row of each Simulator service process (the lowest pid of each kind when several). Never throws: a failed read is `{ error }`. */
export function iosurfaceSample({ ps = () => execFileSync('ps', ['-axo', 'pid,command'], { encoding: 'utf8', maxBuffer: 1 << 26 }), vmmap = (pid) => spawnSync('vmmap', ['-summary', String(pid)], { encoding: 'utf8', timeout: 60000 }) } = {}) {
  const out = {};
  let pids;
  try { pids = simServicePids(ps()); } catch (e) { return { error: `ps: ${e.message}` }; }
  for (const [k, list] of Object.entries(pids)) {
    if (!list.length) { out[k] = { error: 'no process' }; continue; }
    const pid = Math.max(...list);
    const r = vmmap(pid);
    if (r.status !== 0 || !r.stdout) { out[k] = { pid, error: `vmmap exit ${r.status}` }; continue; }
    out[k] = { pid, ...(parseIOSurface(r.stdout) ?? { regions: 0, virtualBytes: 0 }) };
  }
  return out;
}
