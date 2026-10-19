/**
 * Variant `steps` of hero.accent (ledger n=15; Lean: lean/Fw/Parts/HeroAccentOpt.lean `bounds`, `chain`, `chainVal`,
 * `exact_chain_vis`). The idle boil is three inline svg boxes, each `0.6s step-end infinite` on its own keyframes. The
 * variant replaces each CSS animation by a chain of zero-duration, fill-forwards opacity animations, one per plateau
 * boundary of every cycle; a later one overrides an earlier one. The exact boundaries 199.98 ms and 399.96 ms equal the
 * original at every instant (`exact_chain_vis`); the round 200/400 ms ones need a phase premise and are not used.
 */

/** One boil cycle in ms. */
export const CYCLE_MS = 600;
/** Cycles one chain covers (2400 ms): longer than any single idle wait (2200 ms first, 1250 ms later). */
export const CHAIN_CYCLES = 4;

export interface Step {
  /** ms from the start of the chain's first cycle */
  at: number;
  opacity: 0 | 1;
}

/** Lean `bounds j`: the exact step offsets of frame j within one cycle (delay ms, opacity). Empty for j >= 3. */
export function bounds(j: number): readonly Step[] {
  switch (j) {
    case 0:
      return [
        { at: 0, opacity: 1 },
        { at: 199.98, opacity: 0 },
      ];
    case 1:
      return [
        { at: 0, opacity: 0 },
        { at: 199.98, opacity: 1 },
        { at: 399.96, opacity: 0 },
      ];
    case 2:
      return [
        { at: 0, opacity: 0 },
        { at: 399.96, opacity: 1 },
      ];
    default:
      return [];
  }
}

/** Lean `chain bs n`: the steps of `n` cycles, cycle 0 first. */
export function chain(j: number, n: number): Step[] {
  const out: Step[] = [];
  for (let m = 0; m < n; m += 1) for (const s of bounds(j)) out.push({ at: CYCLE_MS * m + s.at, opacity: s.opacity });
  return out;
}

/** Lean `chainVal cs e`: the value of the last step whose delay is at most `e`; null before the first. */
export function chainVal(steps: readonly Step[], e: number): 0 | 1 | null {
  let acc: 0 | 1 | null = null;
  for (const s of steps) if (s.at <= e) acc = s.opacity;
  return acc;
}

/**
 * The original's value (Lean `origVal j u`): frame j at local time u in [0, 600) of the cycle, from its keyframe list
 * with `step-end` (the last keyframe with offset <= u / 600). Restated from the CSS keyframes for the equality test.
 */
export function origVal(j: number, u: number): 0 | 1 {
  const kf: readonly (readonly [number, 0 | 1])[] =
    j === 0
      ? [[0, 1], [0.3332, 1], [0.3333, 0], [1, 0]]
      : j === 1
        ? [[0, 0], [0.3332, 0], [0.3333, 1], [0.6665, 1], [0.6666, 0], [1, 0]]
        : [[0, 0], [0.6665, 0], [0.6666, 1], [1, 1]];
  let acc: 0 | 1 = 0;
  for (const [o, v] of kf) if (o <= u / CYCLE_MS) acc = v;
  return acc;
}

export interface Planned {
  /** ms from now (negative: the step already passed; it still applies, in order) */
  delay: number;
  opacity: 0 | 1;
}

/**
 * The animations to create for frame j when `elapsed` ms of the idle window (counted from the original's animation
 * start) have passed: the chain from the current cycle on, delays relative to now. Cycles before the current one are
 * dropped (a later step always overrides an earlier one, so they cannot show).
 */
export function plan(j: number, elapsed: number, cycles: number = CHAIN_CYCLES): Planned[] {
  const m0 = Math.max(0, Math.floor(elapsed / CYCLE_MS));
  const out: Planned[] = [];
  for (let m = m0; m < m0 + cycles; m += 1) for (const s of bounds(j)) out.push({ delay: CYCLE_MS * m + s.at - elapsed, opacity: s.opacity });
  return out;
}
