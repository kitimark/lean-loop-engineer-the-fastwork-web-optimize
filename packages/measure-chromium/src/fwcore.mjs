// fwcore client for the counts lane (host side only; the container has no Lean). Every reduction and class decision
// past raw per-frame counts is Lean's (lean/Fw/Measure): this module only moves JSON lines.
//   call([{op, ...}, ...]) -> replies in order; a reply with `error` throws.
// The binary is lean/.lake/build/bin/fwcore (FW_CORE_BIN overrides), spawned with LEAN_ABORT_ON_PANIC=1.
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');

export function fwcoreBin() {
  const p = process.env.FW_CORE_BIN ?? join(ROOT, 'lean/.lake/build/bin/fwcore');
  if (!existsSync(p)) throw new Error(`fwcore not found at ${p}; build it with: cd lean && lake build`);
  return p;
}

/** Send requests (objects with `op`), return the replies (ids stripped). Throws on any `error` reply. */
export function call(requests) {
  const input = requests.map((r, i) => JSON.stringify({ ...r, id: i })).join('\n') + '\n';
  const r = spawnSync(fwcoreBin(), [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 30 });
  if (r.status !== 0) throw new Error(`fwcore exited with ${r.status ?? r.signal}: ${r.stderr}`);
  if (r.stderr.length) console.error(`fwcore stderr (incident): ${r.stderr}`);
  const replies = r.stdout.toString().trim().split('\n').map((l) => JSON.parse(l));
  if (replies.length !== requests.length) throw new Error(`fwcore: ${replies.length} replies for ${requests.length} requests`);
  return replies.map((x, i) => {
    if (x.id !== i) throw new Error(`fwcore: reply ${i} has id ${x.id}`);
    if (x.error !== undefined) throw new Error(`fwcore ${requests[i].op}: ${x.error}`);
    const { id, ...rest } = x;
    return rest;
  });
}

/** Per-zone sums of raw frames (Lean `Fw.Measure.zoneSums`). */
export const zoneSums = (frames, zoneHeightPx) => call([{ op: 'measure.zoneSums', zoneHeightPx, frames }])[0].zones;

/** Determinism class of every count type over >= 2 runs (Lean `Fw.Measure.classifyAll`). */
export const classify = (runs, kMax, tMax) => call([{ op: 'measure.classify', mode: 'frames', kMax, tMax, runs }])[0].classes;
