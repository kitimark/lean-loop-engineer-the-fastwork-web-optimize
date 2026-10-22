/** Fw.Gate.Settle.gatePolicy. */
export const GATE_POLICY = Object.freeze({ minFrames: 2, minStable: 3, eps: 100, timeoutMs: 30000, maxFrames: 60 });

/** Fw.Gate.Settle.idlePolicy. */
export const idlePolicy = (p, capMs) => Object.freeze({ ...p, minFrames: 0, minStable: 0, timeoutMs: capMs });

/** Fw.Gate.Settle.spent. */
export const spent = (p, o) => p.timeoutMs < o.t || p.maxFrames < o.frames;

export const micro = (x) => Math.round(x * 1e6);

/** Fw.Gate.Settle.settled. */
export function settled(p, o) {
  return o.running === 0 && p.minFrames <= o.frames && p.minStable <= o.stable && !o.hoverInside;
}

/** Fw.Gate.Settle.runCount. anims = [{ onDocument, dur, elapsed }]. */
export const runCount = (anims) => anims.filter((a) => a.onDocument && a.elapsed < a.dur).length;

/** Fw.Gate.Settle.quiet. */
export function quiet(eps, u, v) {
  return u.length === v.length && u.every((a, i) => Math.abs(a - v[i]) <= eps);
}

/** Fw.Gate.Settle.nextStable. */
export const nextStable = (eps, s, u, v) => (quiet(eps, u, v) ? s + 1 : 0);

/** Fw.Gate.Settle.wait over a finite trace; 'settled@i' or 'unsettled'. */
export function waitTrace(p, trace) {
  for (let i = 0; i < trace.length && i <= p.timeoutMs; i++) {
    if (spent(p, trace[i])) return 'unsettled';
    if (settled(p, trace[i])) return `settled@${i}`;
  }
  return 'unsettled';
}

/** Fw.Gate.Settle.fold. */
export const fold = (first, extra) => extra.reduce((a, w) => (a === 'unsettled' || w === 'unsettled' ? 'unsettled' : a), first);

/** Fw.Gate.Settle.report. */
export function report(a, b, equal) {
  if (a.startsWith('settled') && b.startsWith('settled')) return equal ? 'pass' : 'fail';
  return 'unsettled';
}

/** Fw.Gate.Exit.staleComparable. */
export const staleComparable = (after, fresh) => report(after, fresh, true) === 'pass';

/** Fw.Gate.Settle.rendered. */
export const rendered = (skips) => !skips.some(Boolean);

/** Fw.Gate.Settle.cell. */
export function cell(ra, rb, a, b, equal) {
  if (!(ra && rb)) return 'notRendered';
  return report(a, b, equal);
}

/** Fw.Gate.Settle.viewFor. `sw` is FW_GATE_VIEW (undefined when unset). */
export function viewFor(sw, name) {
  if (sw === '1') return true;
  if (sw === '0') return false;
  return name === 'chromium';
}

/** Fw.Gate.Settle.view. */
export const view = (bring, first, again) => (bring ? again : first);

/** Fw.Gate.Settle.viewCell. */
export function viewCell(bo, br, fo, go, fr, gr, a, b) {
  const o = view(bo, fo, go), r = view(br, fr, gr);
  return cell(!o.skipped, !r.skipped, a, b, o.val === r.val);
}
