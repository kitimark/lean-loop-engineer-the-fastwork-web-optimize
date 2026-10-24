// Pure reductions of one combo replay (task combo-scroll-fight). TS stand-in: the verdicts are not yet a Lean function; the
// definitions copy the lead's mark analysis of a phone record (reversals with no finger down, single-frame jumps).
// Frames: ys[k] is scrollY at the k-th animation frame, down[k] 1 while a finger is on the screen, writes the page's
// `scrollTo` calls as [t, top, yBefore, down].

/** Bound (CSS px) of a "jump": two adjacent frames moving in opposite directions, each by at least this much. */
export const JUMP_PX = 20;

const sgn = Math.sign;

/** Direction reversals of scrollY between adjacent frames that both have no finger down (as in the phone analysis). */
export function reversalsNoFinger(ys, down) {
  let rev = 0;
  let prev = 0;
  for (let k = 1; k < ys.length; k++) {
    if (down[k] || down[k - 1]) { prev = 0; continue; }
    const dy = ys[k] - ys[k - 1];
    if (sgn(dy) && prev && sgn(dy) !== prev) rev++;
    if (sgn(dy)) prev = sgn(dy);
  }
  return rev;
}

/** Single-frame jumps: frame pairs with opposite signs, both at least `bound` px. Returns {n, max, at: [frame...]}. */
export function jumps(ys, bound = JUMP_PX) {
  let n = 0;
  let max = 0;
  const at = [];
  for (let k = 2; k < ys.length; k++) {
    const a = ys[k - 1] - ys[k - 2];
    const b = ys[k] - ys[k - 1];
    if (a * b < 0 && Math.min(Math.abs(a), Math.abs(b)) >= bound) {
      n++;
      max = Math.max(max, Math.abs(a), Math.abs(b));
      if (at.length < 20) at.push(k);
    }
  }
  return { n, max, at };
}

/**
 * Script jumps: the jump pairs of `jumps` with a page `scrollTo` between the first frame of the pair and its last, so the reversal is not the
 * finger's own (a finger that turns round also turns the scroll). `ts[k]` is the frame time, `writes[i][0]` the time of a call, both in ms of the page clock.
 */
export function scriptJumps(ts, ys, writes, bound = JUMP_PX) {
  let n = 0;
  let max = 0;
  const moved = writes.filter((w) => Math.abs(w[1] - w[2]) >= 0.5);
  for (let k = 2; k < ys.length; k++) {
    const a = ys[k - 1] - ys[k - 2];
    const b = ys[k] - ys[k - 1];
    if (!(a * b < 0 && Math.min(Math.abs(a), Math.abs(b)) >= bound)) continue;
    if (!moved.some((w) => w[0] >= ts[k - 2] && w[0] <= ts[k])) continue;
    n++;
    max = Math.max(max, Math.abs(a), Math.abs(b));
  }
  return { n, max };
}

/** Script writes that moved the page: counts while a finger is down and after it lifted, and the px they moved. */
export function writeStats(writes) {
  const out = { n: 0, down: 0, free: 0, pxDown: 0, pxFree: 0 };
  for (const [, top, before, d] of writes) {
    const px = Math.abs(top - before);
    if (px < 0.5) continue;
    out.n++;
    if (d) { out.down++; out.pxDown += px; } else { out.free++; out.pxFree += px; }
  }
  return out;
}

export function metrics({ ts, ys, down, writes }) {
  return { frames: ys.length, reversalsNoFinger: reversalsNoFinger(ys, down), jumps: jumps(ys), scriptJumps: scriptJumps(ts, ys, writes), writes: writeStats(writes) };
}
