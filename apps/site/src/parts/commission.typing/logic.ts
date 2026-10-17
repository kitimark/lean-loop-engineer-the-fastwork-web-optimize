/**
 * commission.typing: the pure timeline of the fee visual. The Lean spec is `lean/Fw/Parts/CommissionTyping.lean`; the
 * golden vectors (`packages/contracts/golden/parts/commission.typing.jsonl`) check this file against it (`logic.test.ts`).
 * Times are ms; `tau` is the time since the cycle began (the reset blink).
 */

export const MESSAGE = 'Hi! I found your profile from Explore.';
export const MSG_LEN = MESSAGE.length;

export const T_RESET = 80;
export const T_AVATAR = 420;
export const T_CHAR = 28;
export const T_CARET_HOLD = 180;
export const T_REFERRAL = 480;
export const T_COUNT = 1100;
export const T_GAP = 120;
export const T_PCT = 900;
export const T_HOLD = 1600;
export const T_OUT = 900;
export const PCT0 = 18;
export const EARNED_MAX = 100;

export const M_AVATAR = T_RESET;
export const M_MSG = M_AVATAR + T_AVATAR;
export const M_TYPE_END = M_MSG + MSG_LEN * T_CHAR;
export const M_REFERRAL = M_TYPE_END + T_CARET_HOLD;
export const M_COUNT_START = M_REFERRAL + T_REFERRAL;
export const M_COUNT_END = M_COUNT_START + T_COUNT;
export const M_PCT_START = M_COUNT_END + T_GAP;
export const M_PCT_END = M_PCT_START + T_PCT;
export const M_OUT = M_PCT_END + T_HOLD;
export const PERIOD = M_OUT + T_OUT;

export interface View {
  resetting: boolean;
  avatar: boolean;
  bubble: boolean;
  chars: number;
  caret: boolean;
  card: boolean;
  out: boolean;
  earned: number;
  pct: number;
  progress: number;
}

const clamp01 = (x: number): number => Math.min(1, Math.max(0, x));
/** Ease-out cubic of the original's `T` (JS 2433), with the clamp of `S`'s `Math.min(1, ...)`. */
export const ease = (x: number): number => 1 - (1 - clamp01(x)) ** 3;
const ramp = (from: number, to: number, dur: number, tau: number): number => from + (to - from) * ease(tau / dur);

export const resetView: View = { resetting: true, avatar: false, bubble: false, chars: 0, caret: false, card: false, out: false, earned: 0, pct: PCT0, progress: 0 };
export const initialView: View = { ...resetView, resetting: false };
export const finalView: View = { resetting: false, avatar: true, bubble: true, chars: MSG_LEN, caret: false, card: true, out: false, earned: EARNED_MAX, pct: 0, progress: 1 };

/** Typed characters at `tau`: those whose timer (the k-th at `M_MSG + k * 28`) has fired. */
export function chars(tau: number): number {
  if (tau < M_MSG) return 0;
  return Math.min(MSG_LEN, Math.floor((tau - M_MSG) / T_CHAR) + 1);
}

export const earnedAt = (tau: number): number => (tau >= M_COUNT_START ? ramp(0, EARNED_MAX, T_COUNT, tau - M_COUNT_START) : 0);
export const pctAt = (tau: number): number => (tau >= M_PCT_START ? ramp(PCT0, 0, T_PCT, tau - M_PCT_START) : PCT0);

/** The picture `tau` ms into a cycle. */
export function viewAt(tau: number): View {
  if (tau < M_AVATAR) return resetView;
  const earned = earnedAt(tau);
  return {
    resetting: false,
    avatar: true,
    bubble: tau >= M_MSG,
    chars: chars(tau),
    caret: tau >= M_MSG && tau < M_TYPE_END,
    card: tau >= M_REFERRAL,
    out: tau >= M_OUT,
    earned,
    pct: pctAt(tau),
    progress: earned / EARNED_MAX,
  };
}

/** `age mod p` for age >= 0 (the Lean `phase`); a negative age stays as it is. */
export const phase = (p: number, age: number): number => (age < 0 ? age : age % p);

export const BLINK = 900;
/** Caret opaque for the first half of each 900 ms (step-end keyframes 0-49 % / 50-100 %). */
export const caretOpaque = (age: number): boolean => phase(BLINK, age) < 450;
/** The boiling frame (0.6 s, step-end; cuts at 33.33 % and 66.66 %). */
export const boilFrame = (age: number): number => {
  const ph = phase(600, age);
  return ph < 199.98 ? 0 : ph < 399.96 ? 1 : 2;
};

/** `--visual-scale` from the parent's width (JS 2511-2518). */
export const visualScale = (width: number): number => Math.min(0.8, width / 432);

export interface Trig {
  visible: boolean;
  token: number;
  since: number | null;
  frozen: number;
  static: boolean;
}
export const trig0: Trig = { visible: false, token: 0, since: null, frozen: 0, static: false };
export type Act = 'keep' | 'cancel' | 'restart';

/** The observer callback (JS 2500-2506). */
export function observe(s: Trig, isIntersecting: boolean, now: number, reduced: boolean): { state: Trig; act: Act } {
  if (isIntersecting === s.visible) return { state: s, act: 'keep' };
  const frozen = s.since !== null ? now - s.since : s.frozen;
  if (isIntersecting) return { state: { visible: true, token: s.token + 1, since: now, frozen: 0, static: reduced }, act: 'restart' };
  return { state: { visible: false, token: s.token + 1, since: null, frozen, static: s.static }, act: 'cancel' };
}

export const elapsed = (s: Trig, now: number): number => (s.since !== null ? now - s.since : s.frozen);
export const cycleTime = (s: Trig, now: number): number => phase(PERIOD, elapsed(s, now));

/** The picture at `now`. */
export function picture(s: Trig, now: number): View {
  if (s.token === 0) return initialView;
  if (s.static) return finalView;
  return viewAt(cycleTime(s, now));
}

/** JS `Math.round` on the counters (half up). */
export const round = (x: number): number => Math.floor(x + 0.5);
