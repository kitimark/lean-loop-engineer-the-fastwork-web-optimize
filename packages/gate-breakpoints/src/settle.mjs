// The gate's settle decisions, Node side: a TypeScript-free twin of lean/Fw/Gate/Settle.lean. Every function here is checked
// against packages/contracts/golden/gate/settle.jsonl (generated from Lean; test/settle.test.mjs). The page-side loop
// (page.mjs settleInPage) carries its own copies of `settled` and `quiet`, which the same test extracts and replays.
//   settled   Fw.Gate.Settle.settled        nothing animates, enough real frames, enough quiet frames, pointer not in a hover target
//   quiet     Fw.Gate.Settle.quiet          same number of values, each moved by at most eps (millionths)
//   spent     Fw.Gate.Settle.spent          the time or the frame budget is spent at an observation
//   waitTrace Fw.Gate.Settle.wait           first settled observation inside the budget, else unsettled
//   idlePolicy Fw.Gate.Settle.idlePolicy    the mount stage's idle wait: nothing runs, under the arm's cap and the frame budget
//   fold      Fw.Gate.Settle.fold           a sample is unsettled when any of its waits is
//   report    Fw.Gate.Settle.report         pass / fail only when both arms settled, else unsettled
// No decision beyond what Lean proves is made here.

/**
 * Fw.Gate.Settle.gatePolicy: two frames after the resize, three quiet frames, quiet = moved by at most 0.0001, 30000 ms, at most
 * 60 real frames (gate-shard-balance: run 39101532038's settled waits all settled within 25 frames; its unsettled ones ran 30 s).
 */
export const GATE_POLICY = Object.freeze({ minFrames: 2, minStable: 3, eps: 100, timeoutMs: 30000, maxFrames: 60 });

/** Fw.Gate.Settle.idlePolicy: no frame or quiet minimum, the arm's time cap, the gate's frame budget. */
export const idlePolicy = (p, capMs) => Object.freeze({ ...p, minFrames: 0, minStable: 0, timeoutMs: capMs });

/** Fw.Gate.Settle.spent: more than timeoutMs milliseconds or more than maxFrames real frames. */
export const spent = (p, o) => p.timeoutMs < o.t || p.maxFrames < o.frames;

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
    if (spent(p, trace[i])) return 'unsettled';
    if (settled(p, trace[i])) return `settled@${i}`;
  }
  return 'unsettled';
}

/** Fw.Gate.Settle.fold: the first wait's outcome folded with the later ones ('settled@i' / 'unsettled'), left to right. */
export const fold = (first, extra) => extra.reduce((a, w) => (a === 'unsettled' || w === 'unsettled' ? 'unsettled' : a), first);

/** Fw.Gate.Settle.report from the two arms' outcomes ('settled@i' / 'unsettled') and whether their values are equal. */
export function report(a, b, equal) {
  if (a.startsWith('settled') && b.startsWith('settled')) return equal ? 'pass' : 'fail';
  return 'unsettled';
}

/**
 * Fw.Gate.Exit.staleComparable: the hysteresis pair (the arm after a sweep, a fresh load at the same final environment) is
 * compared only when both its waits settled. 'missing' (a record made without the wait) is read as unsettled (Fw.Gate.Exit.outcomeOfWire).
 */
export const staleComparable = (after, fresh) => report(after, fresh, true) === 'pass';

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

/**
 * Fw.Gate.Settle.viewFor: whether the probes of an engine bring a skipped part into view and read it again. `sw` is the value of
 * FW_GATE_VIEW (undefined when unset): '1' on, '0' off, anything else no switch. Without a switch Chromium reads again (its
 * getComputedStyle reads stale used auto margins in a skipped subtree) and WebKit does not (the scroll flips the commission scene).
 * `name` is the launcher name; an unknown one reads nothing again.
 */
export function viewFor(sw, name) {
  if (sw === '1') return true;
  if (sw === '0') return false;
  return name === 'chromium';
}

/** Fw.Gate.Settle.view: the reading the gate keeps for a node. `bring`: the node's part was brought into view and read again. */
export const view = (bring, first, again) => (bring ? again : first);

/**
 * Fw.Gate.Settle.viewCell: the cell of one node from the two arms' first and second readings ({ skipped, val }); the kept
 * readings decide rendered / equal. a, b: the arms' settle outcomes.
 */
export function viewCell(bo, br, fo, go, fr, gr, a, b) {
  const o = view(bo, fo, go), r = view(br, fr, gr);
  return cell(!o.skipped, !r.skipped, a, b, o.val === r.val);
}

/** Fw.Gate.Settle.readLayout: the value a read returns of a layout-output value `{ stale, steady }`: the steady one after a committed layout pass. */
export const readLayout = (c, m) => (c ? m.steady : m.stale);

/**
 * Fw.Gate.Settle.committed: whether a read follows a committed layout pass that includes the box. `viewed`: the reading is on the view
 * path (the part was brought into view first); `resizes`: the resizes the arm lived through before the read (a nudged load counts one).
 */
export const committed = (viewed, resizes) => viewed || resizes > 0;

/** Fw.Gate.Settle.commitNeeded: whether a run commits a layout pass before a read; it follows the bring flag (`viewFor`). */
export const commitNeeded = viewFor;

/** Fw.Gate.Settle.commitHolds: a read keeps its layout-output values when the run needs no commit or the read is committed. */
export const commitHolds = (needs, viewed, resizes) => !needs || committed(viewed, resizes);

/** Fw.Gate.Settle.commitOutcome: an uncommitted reading's wait is 'unsettled', a committed one keeps its outcome. */
export const commitOutcome = (c, o) => (c ? o : 'unsettled');

/** Fw.Gate.Settle.layoutCell: the cell of a layout-output probe from both arms' commit flags, `{ stale, steady }` values and waits. */
export function layoutCell(co, cr, mo, mr, a, b) {
  return report(commitOutcome(co, a), commitOutcome(cr, b), readLayout(co, mo) === readLayout(cr, mr));
}

/** Fw.Gate.Settle.nudge: the width a fresh load is opened at before the arm resizes to the width it is read at. */
export const nudge = (w) => w + 1;

/** Fw.Gate.Settle.crosses: whether the nudge from `w` crosses a breakpoint edge, `pairs` = [[lo, hi], ...]. */
export const crosses = (pairs, w) => pairs.some(([lo, hi]) => w <= lo && hi <= nudge(w));
