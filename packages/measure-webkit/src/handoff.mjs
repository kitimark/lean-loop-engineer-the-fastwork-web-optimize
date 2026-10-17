// Hand raw counts to fwcore (the Lean-proved decision core) and print what it says. This file only builds requests
// and reads replies: `screen` and `ticks` are Fw.Screen.screen and Fw.Frames.tickAt (lean/README.md). Nothing here
// decides anything.
//
//   screen: base/var = per-step count vectors [[nat]] (one row per scroll step, columns COUNT_TYPES), the step index is the
//           anchor (both runs scroll to the same y at the same step).
//   ticks : hz 60 and dtNs = the start-to-start gaps of consecutive `Composite` records in the run, in ns. These are
//           SIMULATOR-HOST times (a Mac running the Simulator): a demonstration of the wire format, not phone time.
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { resolve, join, dirname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { COUNT_TYPES, zones } from './reduce.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));

/** The fwcore binary: $FWCORE, else lean/.lake/build/bin/fwcore of this checkout or of the main checkout. */
export function fwcoreBin(env = process.env) {
  if (env.FWCORE) return resolve(env.FWCORE);
  const cands = [];
  let d = HERE;
  for (let i = 0; i < 8; i++) { cands.push(join(d, 'lean', '.lake', 'build', 'bin', 'fwcore')); d = dirname(d); }
  const marker = `${sep}.claude${sep}worktrees${sep}`;
  const at = HERE.indexOf(marker);
  if (at > 0) cands.push(join(HERE.slice(0, at), 'lean', '.lake', 'build', 'bin', 'fwcore'));
  const found = cands.find((p) => existsSync(p));
  if (!found) throw new Error('fwcore not found: set FWCORE (build with `lake build` in lean/)');
  return found;
}

/** Send JSON-line requests to one fwcore process, return the parsed replies in order (LEAN_ABORT_ON_PANIC=1 as lean/README.md says). */
export function fwcoreCall(requests, bin = fwcoreBin()) {
  return new Promise((ok, bad) => {
    const p = spawn(bin, [], { env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, stdio: ['pipe', 'pipe', 'pipe'] });
    let out = '', err = '';
    p.stdout.on('data', (d) => { out += d; });
    p.stderr.on('data', (d) => { err += d; });
    p.on('error', bad);
    p.on('close', (code) => {
      if (err) return bad(new Error(`fwcore stderr (an incident): ${err}`));
      if (code !== 0) return bad(new Error(`fwcore exited ${code}`));
      ok(out.split('\n').filter(Boolean).map((l) => JSON.parse(l)));
    });
    p.stdin.end(requests.map((r) => JSON.stringify(r)).join('\n') + '\n');
  });
}

/**
 * Count vectors at three granularities (the frames of the screen): `step` = one row per scroll step; `zone` = one row
 * per 500 px of scroll (sums of the steps); `total` = a single row for the whole run. Columns COUNT_TYPES, plain nats
 * (paintArea is not a count and is left out).
 */
export function stepVectors(scroll, gran = 'step', cols = null) {
  const pick = cols ? cols.map((c) => { const j = COUNT_TYPES.indexOf(c); if (j < 0) throw new Error(`unknown count type ${c}`); return j; }) : COUNT_TYPES.map((_, j) => j);
  const rows = scroll.reduced.perStep.map((row) => pick.map((j) => row[j]));
  if (gran === 'step') return rows;
  if (gran === 'zone') return zones(scroll.ys, scroll.reduced.perStep, scroll.reduced.perStepPaintArea).map((z) => pick.map((j) => z.counts[j]));
  if (gran === 'total') return [pick.map((_, k) => rows.reduce((a, r) => a + r[k], 0))];
  throw new Error(`granularity ${gran}`);
}

/** Gaps (ns, integer) between the starts of consecutive Composite rows between the first and last step mark. */
export function compositeGapsNs(scroll) {
  const t = scroll.records.filter((r) => r[0] === 'Composite' && r[1] >= scroll.marks[0] && r[1] < scroll.endTime).map((r) => r[1]).sort((a, b) => a - b);
  const gaps = [];
  for (let i = 1; i < t.length; i++) gaps.push(Math.round((t[i] - t[i - 1]) * 1e9));
  return gaps;
}

export const GRANS = ['step', 'zone', 'total'];

/**
 * fwcore `screen` for every (base pass, var pass) pair at every granularity, the same for base-vs-base pairs (i < j:
 * the noise floor, since two runs of one config are "equal" in principle) and var-vs-var pairs, plus `ticks` (hz 60) on
 * each run's Composite gaps (simulator-host time, not phone time).
 * @returns {{tally:object, ticks:object}} tally[gran] = { cross, baseNoise, varNoise } = {verdict: n}
 */
export async function screenAndTicks(baseScrolls, varScrolls, cols = null) {
  const reqs = [], meta = [];
  const add = (kind, gran, a, b) => {
    const id = `${kind}-${gran}-${reqs.length}`;
    reqs.push({ id, op: 'screen', base: stepVectors(a, gran, cols), var: stepVectors(b, gran, cols) });
    meta.push({ id, kind, gran });
  };
  for (const gran of GRANS) {
    for (const a of baseScrolls) for (const b of varScrolls) add('cross', gran, a, b);
    for (let i = 0; i < baseScrolls.length; i++) for (let j = i + 1; j < baseScrolls.length; j++) add('baseNoise', gran, baseScrolls[i], baseScrolls[j]);
    for (let i = 0; i < varScrolls.length; i++) for (let j = i + 1; j < varScrolls.length; j++) add('varNoise', gran, varScrolls[i], varScrolls[j]);
  }
  varScrolls.forEach((sc, i) => reqs.push({ id: `ticks-var-${i}`, op: 'ticks', hz: 60, dtNs: compositeGapsNs(sc), thresholdsNs: [34000000] }));
  baseScrolls.forEach((sc, i) => reqs.push({ id: `ticks-base-${i}`, op: 'ticks', hz: 60, dtNs: compositeGapsNs(sc), thresholdsNs: [34000000] }));
  const replies = await fwcoreCall(reqs);
  const byId = Object.fromEntries(replies.map((r) => [r.id, r]));
  const tally = {};
  for (const m of meta) {
    const r = byId[m.id];
    const verdict = r.screen ?? `error: ${r.error}`; // an error reply (e.g. "not aligned") is an answer, kept
    const t = ((tally[m.gran] ??= {})[m.kind] ??= {});
    t[verdict] = (t[verdict] || 0) + 1;
  }
  const ticks = Object.fromEntries(Object.entries(byId).filter(([k]) => k.startsWith('ticks')).map(([k, r]) => [k, { composites: r.ticks.length + 1, ticksTotal: r.ticks.reduce((a, x) => a + x, 0), gapsAbove34ms: r.above?.[0] }]));
  return { countTypes: COUNT_TYPES, tally, ticks, requestsSent: reqs.length };
}
