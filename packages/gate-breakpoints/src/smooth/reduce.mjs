// Motion continuity along one push and the bad-frame cadence verdict (task smoothness-probe). Advisory evidence only.
// The decisions are Lean's (lean/Fw/Gate/Smooth.lean: exact_zero, held_stalls, restart_flagged, tail_late, aa_same, verdict_swap, ...);
// this file is the TS twin, checked against packages/contracts/golden/gate/smooth.jsonl (test/smooth.test.mjs). Values are integers
// (property value x 1000, time in tenths of ms), exactly as the Lean side takes them.

export const STALL_PM = 5;
export const STALL_DIV = 4;
export const JUMP_PM = 50;
export const REVERSE_PM = 10;
export const BAD_TENTHS = 340;
export const MIN_REPS = 5;

const abs = (x) => (x < 0 ? -x : x);

/** The ideal value at driver d on the straight line from (d0, v0) to (d1, v1), rounded down (Lean `lerp`). */
export function lerp(d0, v0, d1, v1, d) {
  if (d0 === d1) return v1;
  const den = BigInt(abs(d1 - d0));
  const sg = d0 < d1 ? 1n : -1n;
  const num = sg * BigInt(v1 - v0) * BigInt(d - d0);
  let q = num / den;
  if (num % den !== 0n && num < 0n) q -= 1n;
  return Number(BigInt(v0) + q);
}

/** The steps between consecutive frames; a frame is [t, want, shown] (Lean `steps`). */
export function steps(frames) {
  const out = [];
  for (let i = 1; i < frames.length; i++) {
    const a = frames[i - 1];
    const b = frames[i];
    out.push({ t: b[0], e: b[1] - a[1], s: b[2] - a[2] });
  }
  return out;
}

export const travel = (ps) => abs(ps.reduce((x, p) => x + p.e, 0));
export const stalled = (T, p) => STALL_PM * T <= 1000 * abs(p.e) && STALL_DIV * abs(p.s) < abs(p.e);
export const jumped = (T, p) => JUMP_PM * T < 1000 * (abs(p.s) - abs(p.e));
export const reversed = (T, p) => p.s * p.e < 0 && REVERSE_PM * T <= 1000 * abs(p.s);

const idleRun = (ps) => {
  let k = ps.length;
  while (k > 0 && ps[k - 1].e === 0) k--;
  return { k, idle: ps.slice(k) };
};

/** All metrics of one push of one scalar property (Lean `metrics`). */
export function metrics(frames) {
  const ps = steps(frames);
  const T = travel(ps);
  const peakShown = ps.reduce((m, p) => Math.max(m, abs(p.s)), 0);
  const peakIdeal = ps.reduce((m, p) => Math.max(m, abs(p.e)), 0);
  const { k, idle } = idleRun(ps);
  const arrive = k > 0 ? ps[k - 1].t : 0;
  const moving = idle.filter((p) => p.s !== 0);
  const last = moving.length > 0 ? moving[moving.length - 1].t : arrive;
  return {
    n: ps.length,
    travel: T,
    stalls: ps.filter((p) => stalled(T, p)).length,
    jumps: ps.filter((p) => jumped(T, p)).length,
    reversals: ps.filter((p) => reversed(T, p)).length,
    peakPm: T === 0 ? 0 : Math.floor((1000 * peakShown) / T),
    peakRatio: peakIdeal === 0 ? 0 : Math.floor((1000 * peakShown) / peakIdeal),
    tailSteps: moving.length,
    tailT: Math.max(0, last - arrive),
  };
}

export const flat = (m) => m.travel === 0;
export const flagged = (m) => m.stalls > 0 || m.jumps > 0 || m.reversals > 0 || m.tailSteps > 0;

export const FIELDS = ['n', 'travel', 'stalls', 'jumps', 'reversals', 'peakPm', 'peakRatio', 'tailSteps', 'tailT'];

/** The worse of two components of one property (Lean `Metrics.worst`). */
export const worst = (a, b) => Object.fromEntries(FIELDS.map((f) => [f, Math.max(a[f], b[f])]));

/** Nearest-rank p-th smallest, or null when empty (Lean `quantile`). */
export function quantile(xs, p) {
  const s = [...xs].sort((a, b) => a - b);
  if (s.length === 0) return null;
  return s[Math.min(Math.floor((p * s.length + 99) / 100) - 1, s.length - 1)];
}

/** The median of each metric over repeated pushes, or null when there is none (Lean `Metrics.median`). */
export function median(ms) {
  if (ms.length === 0) return null;
  return Object.fromEntries(FIELDS.map((f) => [f, quantile(ms.map((m) => m[f]), 50)]));
}

/** A repeat from its frame intervals in tenths of ms (Lean `Rep.ofIntervals`). */
export const repOf = (ivs) => ({ frames: ivs.length, bad: ivs.filter((i) => BAD_TENTHS < i).length });
export const rate = (frames, bad) => (frames === 0 ? 0 : Math.floor((10000 * bad) / frames));
export const armRate = (a) => rate(a.reduce((x, r) => x + r.frames, 0), a.reduce((x, r) => x + r.bad, 0));
export function repRange(a) {
  if (a.length === 0) return 0;
  const rs = a.map((r) => rate(r.frames, r.bad));
  return Math.max(...rs) - Math.min(...rs);
}
export const dist = (a, b) => Math.max(a - b, 0) + Math.max(b - a, 0);
export const spread = (aa1, aa2) => Math.max(dist(armRate(aa1), armRate(aa2)), Math.max(repRange(aa1), repRange(aa2)));
export const enough = (a) => MIN_REPS <= a.length;

/** 'first' when the first arm's rate plus the spread is under the second's, 'second' the other way, else 'same' (Lean `judge`). */
export const judge = (sp, ra, rb) => (ra + sp < rb ? 'first' : rb + sp < ra ? 'second' : 'same');

/** The verdict on arms a and b against the A/A pair; any arm under MIN_REPS repeats is 'insufficient' (Lean `verdict`). */
export const verdict = (a, b, aa1, aa2) =>
  enough(a) && enough(b) && enough(aa1) && enough(aa2) ? judge(spread(aa1, aa2), armRate(a), armRate(b)) : 'insufficient';

export const HITCH_TENTHS = 600;
export const MIN_SAMPLES = 3;

/** Frames over 60 ms in one repeat, from its frame intervals in tenths of ms (Lean `hitches`). */
export const hitches = (ivs) => ivs.filter((i) => HITCH_TENTHS < i).length;

/** Every repeat of `a` has more hitches than every repeat of `b` (Lean `above`). */
export const above = (a, b) => a.every((x) => b.every((y) => y < x));
export const enoughN = (c) => MIN_REPS <= c.length;

/** 'first' when every repeat of the second arm has more hitches than every repeat of the first, 'second' the other way, else 'same' (Lean `hitchJudge`). */
export const hitchJudge = (a, b) => (above(b, a) ? 'first' : above(a, b) ? 'second' : 'same');

/** The hitch verdict on per-repeat hitch counts against the A/A pair; 'insufficient' under MIN_REPS repeats, 'same' when the A/A pair is itself told apart (Lean `hitchVerdict`). */
export const hitchVerdict = (a, b, aa1, aa2) =>
  !(enoughN(a) && enoughN(b) && enoughN(aa1) && enoughN(aa2)) ? 'insufficient' : hitchJudge(aa1, aa2) === 'same' ? hitchJudge(a, b) : 'same';

/** The agreement asked of n samples: two thirds, rounded up (Lean `agreeNeeded`). */
export const agreeNeeded = (n) => Math.floor((2 * n + 2) / 3);

/** The verdict over per-sample verdicts: 'first' when at least k say first and none says second, 'second' the other way, else 'same'; 'insufficient' under MIN_SAMPLES decisive (first, second or same) samples or k = 0 (Lean `across`). */
export function across(k, vs) {
  const f = vs.filter((v) => v === 'first').length;
  const s = vs.filter((v) => v === 'second').length;
  const same = vs.filter((v) => v === 'same').length;
  if (f + s + same < MIN_SAMPLES || k === 0) return 'insufficient';
  return k <= f && s === 0 ? 'first' : k <= s && f === 0 ? 'second' : 'same';
}
