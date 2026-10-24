
export const JUMP_PX = 20;

const sgn = Math.sign;

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

export function cycles(ms) {
  let opens = 0;
  let closes = 0;
  for (let k = 1; k < ms.length; k++) {
    if (ms[k] > 0.5 && ms[k - 1] <= 0.5) opens++;
    if (ms[k] < 0.5 && ms[k - 1] >= 0.5) closes++;
  }
  return { opens, closes };
}

export const ranScripted = (c) => c.opens >= 2 && c.closes >= 1;

export function metrics({ ts, ys, down, writes, ms = [] }) {
  return { frames: ys.length, reversalsNoFinger: reversalsNoFinger(ys, down), jumps: jumps(ys), scriptJumps: scriptJumps(ts, ys, writes), writes: writeStats(writes), morph: cycles(ms) };
}
