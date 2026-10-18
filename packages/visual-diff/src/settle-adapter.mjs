// Thin adapter to the gate's settled-sample predicate (Fw.Gate.Settle, task gate-settle) and the capture's arm rule
// (Fw.Gate.Pixel: Arm, settledBoth, presentAny; golden: packages/contracts/golden/gate/pixel-assets.jsonl, kind "settle").
//
// STATUS: the gate-settle branch (worktree-agent-a102c4d136256e6ae, packages/gate-breakpoints/src/settle.mjs) has not landed on
// main when this was written, so `settled`, `waitTrace` and GATE_POLICY below are verbatim twins of that file's functions, not an
// import. When it lands, replace the three definitions by `export { GATE_POLICY, settled, waitTrace } from
// '../../gate-breakpoints/src/settle.mjs'` and replay settle.jsonl in this package's test. Nothing here is a new decision.

/**
 * Fw.Gate.Settle.gatePolicy, with one change: the budget. The gate waits up to 10000 ms; a pixel diff over 30 parts x 8 probes x 2
 * arms spends the budget on every part that never settles (an endless animation), so the budget is 15000 ms. Run 39080594980 used
 * 3000 ms and 34 WebKit cells were cut short with running = 0 but 0 to 3 real frames (about 1 frame/s on the CI runner); the
 * gate-settle branch settled on 30000 ms for the same reason, which is more than this run can afford per unsettled cell.
 * The predicate is the same.
 */
export const GATE_POLICY = Object.freeze({ minFrames: 2, minStable: 3, eps: 100, timeoutMs: 15000 });

/** Fw.Gate.Settle.settled. o = { running, frames, stable, hoverInside, t }. */
export function settled(p, o) {
  return o.running === 0 && p.minFrames <= o.frames && p.minStable <= o.stable && !o.hoverInside;
}

/** Fw.Gate.Settle.wait over a finite trace: past its end the budget has run out. Returns 'settled@i' or 'unsettled'. */
export function waitTrace(p, trace) {
  for (let i = 0; i < trace.length && i <= p.timeoutMs; i++) {
    if (p.timeoutMs < trace[i].t) return 'unsettled';
    if (settled(p, trace[i])) return `settled@${i}`;
  }
  return 'unsettled';
}

/** Fw.Gate.Pixel.Arm.ok: an absent arm (null) does not block; a shot arm needs the gate predicate and calm shots. */
export const armOk = (a) => a === null || (a.gate === true && a.calm === true);

/** Fw.Gate.Pixel.settledBoth. */
export const settledBoth = (a, b) => armOk(a) && armOk(b);

/** Fw.Gate.Pixel.fontsBoth / imagesBoth: every shot arm has them loaded (an absent arm, null, has none to load). */
export const fontsBoth = (a, b) => (a === null || a.fonts === true) && (b === null || b.fonts === true);
export const imagesBoth = (a, b) => (a === null || a.images === true) && (b === null || b.images === true);

/** Fw.Gate.Pixel.presentAny. */
export const presentAny = (a, b) => a !== null || b !== null;
