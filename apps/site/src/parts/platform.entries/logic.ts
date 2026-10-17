/**
 * Pure logic of `platform.entries` (no DOM): the entry animations of the stage visuals, the profile count-up and the
 * search typing schedule. Restated from the original (assets/2.gBuqKVzi.css keyframes 1064, 1160-1180, 1232, 1420-1475,
 * 1505-1516 of the compacted text; nodes/2.DyWL8TcE.js:11996-12040 and the typing loop of the search visual).
 * Spec and proofs: lean/Fw/Parts/PlatformEntries.lean. Golden vectors: packages/contracts/golden/parts/platform.entries.jsonl.
 */

/** `cubic-bezier(0.16, 1, 0.3, 1)`. */
export const SPRING = [0.16, 1, 0.3, 1] as const;
const STEPS = 24;

const bx = (u: number): number => 3 * (1 - u) * (1 - u) * u * SPRING[0] + 3 * (1 - u) * u * u * SPRING[2] + u * u * u;
const by = (u: number): number => 3 * (1 - u) * (1 - u) * u * SPRING[1] + 3 * (1 - u) * u * u * SPRING[3] + u * u * u;

/** The curve parameter whose x is closest to `x` after 24 bisections (the Lean spec's `solve`). */
function solve(x: number): number {
  let lo = 0;
  let hi = 1;
  for (let i = 0; i < STEPS; i++) {
    const mid = (lo + hi) / 2;
    if (bx(mid) < x) lo = mid;
    else hi = mid;
  }
  return (lo + hi) / 2;
}

/** Eased progress for a linear progress x. */
export function ease({ x }: { x: number }): number {
  return x <= 0 ? 0 : x >= 1 ? 1 : by(solve(x));
}

export interface Tr {
  key: string;
  from: number;
  to: number;
}
export interface Entry {
  keyframes: string;
  durMs: number;
  delayMs: number;
  props: Tr[];
}

const liftBlur = (): Tr[] => [
  { key: 'opacity', from: 0, to: 1 },
  { key: 'translateY', from: 18, to: 0 },
  { key: 'scale', from: 0.96, to: 1 },
  { key: 'blur', from: 8, to: 0 },
];
const fade = (k: string, a: number, b: number): Tr[] => [
  { key: 'opacity', from: 0, to: 1 },
  { key: k, from: a, to: b },
];

export const credCard = (i: number): Entry => ({ keyframes: 'cred-card-in', durMs: 420, delayMs: 70 * i, props: liftBlur() });
export const profilePhone: Entry = { keyframes: 'profile-phone-in', durMs: 620, delayMs: 0, props: liftBlur() };
export const rings: Entry = { keyframes: 'secure-network-rings-in', durMs: 480, delayMs: 0, props: fade('scale', 1.04, 1) };
export const faceLeft: Entry = { keyframes: 'secure-network-face-left-in', durMs: 320, delayMs: 0, props: fade('translateX', -8, 0) };
export const faceRight: Entry = { keyframes: 'secure-network-face-right-in', durMs: 320, delayMs: 0, props: fade('translateX', 8, 0) };
export const dash: Entry = { keyframes: 'secure-network-dash-in', durMs: 260, delayMs: 60, props: fade('scaleX', 0, 1) };
export const shield: Entry = { keyframes: 'secure-network-shield-in', durMs: 420, delayMs: 180, props: fade('scale', 0.88, 1) };
export const logo: Entry = { keyframes: 'secure-network-logo-in', durMs: 280, delayMs: 680, props: fade('scale', 0.7, 1) };
/** Delay of flag number k (1-based child index): 600, 560, 520, 520, 560, 600 ms. */
export const flagDelay = (k: number): number => [0, 600, 560, 520, 520, 560][k] ?? 600;
export const flag = (k: number): Entry => ({ keyframes: 'secure-network-flag-in', durMs: 280, delayMs: flagDelay(k), props: fade('scale', 0.82, 1) });
export const invoiceCard: Entry = {
  keyframes: 'invoice-card-in',
  durMs: 560,
  delayMs: 620,
  props: [
    { key: 'opacity', from: 0, to: 1 },
    { key: 'translateY', from: 22, to: 0 },
    { key: 'scale', from: 0.94, to: 1 },
  ],
};
export const orderRow = (i: number): Entry => ({ keyframes: 'invoice-i-row-in', durMs: 620, delayMs: 140 * i, props: fade('translateX', 20, 0) });
export const askIn = (i: number): Entry => ({ keyframes: 'agents-ask-in', durMs: 560, delayMs: 140 * i, props: fade('translateY', 10, 0) });
export const askOut = (i: number): Entry => ({
  keyframes: 'agents-ask-out',
  durMs: 560,
  delayMs: 140 * i,
  props: [
    { key: 'opacity', from: 1, to: 0 },
    { key: 'translateY', from: 0, to: 10 },
  ],
});

/** The entries of the live stages by table name (the order and names of the Lean `entryTable`). */
export const TABLE: Record<string, Entry> = {
  credCard0: credCard(0),
  credCard3: credCard(3),
  profilePhone,
  rings,
  faceLeft,
  faceRight,
  dash,
  shield,
  logo,
  flag1: flag(1),
  flag3: flag(3),
  flag6: flag(6),
  invoiceCard,
  orderRow0: orderRow(0),
  orderRow3: orderRow(3),
  askIn0: askIn(0),
  askIn2: askIn(2),
  askOut1: askOut(1),
};

/** Eased progress of an entry t ms after it started (fill `both`). */
export function progressOf(e: Entry, t: number): number {
  return ease({ x: (t - e.delayMs) / e.durMs });
}

export function progress({ entry, t }: { entry: string; t: number }): number {
  return progressOf(TABLE[entry]!, t);
}

// ---- profile count-up ----------------------------------------------------------------------------------------------

export const COUNT_DELAY_MS = 180;
export const COUNT_DUR_MS = 1080;
/** The stats' final numbers (earned in thousands of baht, orders, rehires, reviews). */
export const PROFILE_TARGET = { earnedK: 240, orders: 43, rehires: 5, reviews: 48 } as const;

/** The shown number for target n, t ms after the stage became visible (JS `Math.round`, ease-out cubic). */
export function countAt({ n, t }: { n: number; t: number }): number {
  if (t < COUNT_DELAY_MS) return 0;
  const x = Math.min(1, (t - COUNT_DELAY_MS) / COUNT_DUR_MS);
  const eo = 1 - (1 - x) * (1 - x) * (1 - x);
  return Math.floor(n * eo + 0.5);
}

// ---- search typing ------------------------------------------------------------------------------------------------

export const ASK_LEAD_MS = 700;
export const TYPE_STEP_MS = 32;
export const ERASE_STEP_MS = 18;
export const HOLD_MS = 3000;
export const FIRST_REVEAL_MS = 280;
export const SWAP_MS = 700;

export interface View {
  /** characters of the query shown */
  len: number;
  /** topic the query belongs to */
  topic: number;
  /** topic whose service list is shown */
  shown: number;
  /** the previous list is leaving */
  leaving: boolean;
  /** results are visible */
  results: boolean;
  caret: boolean;
}

const topicDur = (L: number, reveal: number): number => TYPE_STEP_MS * L + reveal + HOLD_MS + ERASE_STEP_MS * L;

function lenAt(L: number, reveal: number, tau: number): number {
  const typed = TYPE_STEP_MS * L;
  if (tau < typed) return Math.min(L, Math.floor(tau / TYPE_STEP_MS) + 1);
  if (tau < typed + reveal + HOLD_MS) return L;
  return Math.max(0, L - (Math.floor((tau - (typed + reveal + HOLD_MS)) / ERASE_STEP_MS) + 1));
}

function topicView(idx: number, prev: number, L: number, first: boolean, tau: number): View {
  const reveal = first ? FIRST_REVEAL_MS : SWAP_MS;
  const typed = TYPE_STEP_MS * L;
  return {
    len: lenAt(L, reveal, tau),
    topic: idx,
    shown: typed <= tau ? idx : prev,
    leaving: !first && typed <= tau && tau < typed + SWAP_MS,
    results: !first || typed + FIRST_REVEAL_MS <= tau,
    caret: true,
  };
}

const EMPTY: View = { len: 0, topic: 0, shown: 0, leaving: false, results: false, caret: false };

function cycView(lens: readonly number[], r: number): View {
  const order: Array<[number, number]> = lens.slice(1).map((L, k) => [k + 1, L] as [number, number]);
  order.push([0, lens[0]!]);
  const P = order.reduce((s, [, L]) => s + topicDur(L, SWAP_MS), 0);
  let rest = r - P * Math.floor(r / P);
  for (const [i, L] of order) {
    const d = topicDur(L, SWAP_MS);
    if (rest < d) return topicView(i, i === 0 ? lens.length - 1 : i - 1, L, false, rest);
    rest -= d;
  }
  return EMPTY;
}

/** The view at time t after the stage became visible. `lens` are the query lengths in topic order. */
export function askView({ lens, t }: { lens: readonly number[]; t: number }): View {
  if (t < ASK_LEAD_MS || lens.length === 0) return EMPTY;
  const tau0 = t - ASK_LEAD_MS;
  const d0 = topicDur(lens[0]!, FIRST_REVEAL_MS);
  return tau0 < d0 ? topicView(0, 0, lens[0]!, true, tau0) : cycView(lens, tau0 - d0);
}

/** Everything the golden `const` line carries, in its shape. */
export function constants() {
  return {
    spring: [...SPRING],
    countDelayMs: COUNT_DELAY_MS,
    countDurMs: COUNT_DUR_MS,
    askLeadMs: ASK_LEAD_MS,
    typeStepMs: TYPE_STEP_MS,
    eraseStepMs: ERASE_STEP_MS,
    holdMs: HOLD_MS,
    firstRevealMs: FIRST_REVEAL_MS,
    swapMs: SWAP_MS,
    entries: Object.entries(TABLE).map(([name, e]) => ({ name, keyframes: e.keyframes, durMs: e.durMs, delayMs: e.delayMs, props: e.props })),
  };
}
