// Timing spans of the WKTR lane (task wktr-fixture-speed). A span is the wall time in ms between two named marks of one
// pass; they are written to spans-<variant>-<pass>.json (never into counts-*.json, so no class sees them) and to the log.
// Wall time of a CI VM; nothing here is phone time and nothing here decides anything.
import { performance } from 'node:perf_hooks';

/** A recorder: `mark(name)` adds the time since the previous mark to `name`; `spans()` returns {name: ms}. */
export function recorder() {
  const t0 = performance.now();
  let last = t0;
  const out = {};
  return {
    mark(name) { const t = performance.now(); out[name] = (out[name] || 0) + Math.round(t - last); last = t; },
    spans() { return { ...out }; },
    sinceStart() { return Math.round(performance.now() - t0); },
  };
}

/** Run `fn` (sync or async) and book its wall time under `name` in `rec`. */
export async function timed(rec, name, fn) {
  rec.mark('_gap');
  try { return await fn(); } finally { rec.mark(name); }
}
