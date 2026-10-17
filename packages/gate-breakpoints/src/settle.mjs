// The gate's settle decisions, Node side: a TypeScript-free twin of lean/Fw/Gate/Settle.lean. Every function here is checked
// against packages/contracts/golden/gate/settle.jsonl (generated from Lean; test/settle.test.mjs). The page-side loop
// (page.mjs settleInPage) carries its own copies of `settled` and `quiet`, which the same test extracts and replays.
//   settled   Fw.Gate.Settle.settled        nothing animates, enough real frames, enough quiet frames, pointer not in a hover target
//   quiet     Fw.Gate.Settle.quiet          same number of values, each moved by at most eps (millionths)
//   waitTrace Fw.Gate.Settle.wait           first settled observation inside the budget, else unsettled
//   report    Fw.Gate.Settle.report         pass / fail only when both arms settled, else unsettled
// No decision beyond what Lean proves is made here.

/** Fw.Gate.Settle.gatePolicy: two frames after the resize, three quiet frames, quiet = moved by at most 0.0001, 10000 ms. */
export const GATE_POLICY = Object.freeze({ minFrames: 2, minStable: 3, eps: 100, timeoutMs: 10000 });

/** Values to Lean's integer millionths. */
export const micro = (x) => Math.round(x * 1e6);

/** Fw.Gate.Settle.settled. o = { running, frames, stable, hoverInside, t }. */
export function settled(p, o) {
  return o.running === 0 && p.minFrames <= o.frames && p.minStable <= o.stable && !o.hoverInside;
}

/** Fw.Gate.Settle.quiet on integer millionths. */
export function quiet(eps, u, v) {
  return u.length === v.length && u.every((a, i) => Math.abs(a - v[i]) <= eps);
}

/** Fw.Gate.Settle.nextStable. */
export const nextStable = (eps, s, u, v) => (quiet(eps, u, v) ? s + 1 : 0);

/** Fw.Gate.Settle.wait over a finite trace: past its end the budget has run out. Returns 'settled@i' or 'unsettled'. */
export function waitTrace(p, trace) {
  for (let i = 0; i < trace.length && i <= p.timeoutMs; i++) {
    if (p.timeoutMs < trace[i].t) return 'unsettled';
    if (settled(p, trace[i])) return `settled@${i}`;
  }
  return 'unsettled';
}

/** Fw.Gate.Settle.report from the two arms' outcomes ('settled@i' / 'unsettled') and whether their values are equal. */
export function report(a, b, equal) {
  if (a.startsWith('settled') && b.startsWith('settled')) return equal ? 'pass' : 'fail';
  return 'unsettled';
}

/** Fw.Gate.Settle.rendered: no ancestor (itself included) skips its subtree. `skips` is one boolean per ancestor. */
export const rendered = (skips) => !skips.some(Boolean);

/**
 * Fw.Gate.Settle.cell: a probe on a node that is not rendered in either arm is 'notRendered' (never pass, never fail); otherwise
 * Lean's report. ra, rb: whether the node is rendered in the original / the rewrite.
 */
export function cell(ra, rb, a, b, equal) {
  if (!(ra && rb)) return 'notRendered';
  return report(a, b, equal);
}
