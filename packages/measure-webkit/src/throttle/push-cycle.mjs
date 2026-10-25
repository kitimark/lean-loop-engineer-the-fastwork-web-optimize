// TS twin of lean/Fw/Measure/PushCycle.lean (golden: packages/contracts/golden/measure/push-cycle.jsonl; test/push-cycle.test.mjs): the cycle
// model, the verdicts of H1 to H4, the cycle plan and the phone replay profile. Below the twin, `recordCycles` and `passRow` are
// TS STAND-INS (no Lean spec): they cut a page record into cycles and count slow frames; the verdict inputs they build are Lean-decided.
import { stretches } from './morph-end.mjs';
import { reduce as lockReduce, refusal as lockRefusal } from '../touchlock.mjs';

export const CYCLES = 6;
export const LEG_FRAMES = 24;
export const THROTTLE_MS = 100;
export const MiB = 1024 * 1024;
export const H1_MIN_CHANGES = 3;
export const H1_MIN_SLOW = 5;
export const TICK = 1600;
export const LIFT_GAP = 3200;
export const FINGER_X = 215;
export const START_Y = 700;
export const STEP_PX = 14;
export const TOP_Y = START_Y - STEP_PX * (LEG_FRAMES - 1);

// ---- which work repeats per cycle
export const single = (c) => c.first + c.promo + c.run;
export const openWork = (c, keep, k) => c.run + (k === 0 ? c.first : 0) + (k === 0 || !keep ? c.promo : 0);
export const cycleWork = (c, keep, k) => openWork(c, keep, k) + c.close + c.toolbar;
export const series = (c, keep, n) => Array.from({ length: n }, (_, k) => cycleWork(c, keep, k));
export const totalWork = (c, keep, n) => series(c, keep, n).reduce((a, b) => a + b, 0);

const sum = (l) => l.reduce((a, b) => a + b, 0);

export function trend(xs) {
  if (xs.length === 0) return 'flat';
  const [f, ...t] = xs;
  if (6 * t.length * f < 5 * sum(t)) return 'rises';
  if (6 * sum(t) < 5 * t.length * f) return 'falls';
  return 'flat';
}

// ---- H3, H4
export const cycleFlags = (n) => Array.from({ length: n }, () => [false, true]).flat();
export function reattachPaint(area, flags) {
  let s = 0;
  for (let i = 0; i + 1 < flags.length; i++) if (flags[i + 1] && !flags[i]) s += area;
  return s;
}
export const cyclePx = (dpr, a, n) => reattachPaint(a, cycleFlags(n)) * dpr ** 2;
export const poolCap = (mac) => (mac ? 256 * MiB : 64 * MiB);
export const realloc = (cap, released) => released - Math.min(released, cap);

// ---- H1
export const updatesIn = (span) => Math.floor(span / THROTTLE_MS) + 1;
export function h1Verdict(o) {
  if (o.changes < H1_MIN_CHANGES) return 'open';
  if (o.slowNear + o.slowFar < H1_MIN_SLOW) return 'open';
  if (o.framesNear === 0 || o.framesFar === 0) return 'open';
  return 2 * o.slowFar * o.framesNear <= o.slowNear * o.framesFar ? 'holds' : 'refuted';
}

// ---- H2
export function h2Verdict(o) {
  if (o.stretchesFirst === 0 || o.stretchesLater < 2) return 'open';
  return o.fightsFirst * o.stretchesLater < o.fightsLater * o.stretchesFirst ? 'holds' : 'refuted';
}

// ---- H3, H4 verdicts
export function h3Verdict(o) {
  if (o.cyclesSeen < 3 || o.firstCyclePx === 0) return 'open';
  if (o.firstCyclePx <= o.laterCyclePx) return 'holds';
  return 2 * o.laterCyclePx < o.firstCyclePx ? 'refuted' : 'open';
}
export function h4Verdict(o) {
  if (o.freedBytes === 0) return 'open';
  if (o.freedBytes <= 64 * MiB) return 'refuted';
  return o.freedBytes <= 256 * MiB ? 'holds' : 'open';
}

// ---- the cycle plan
export const dwellFrames = (ms) => Math.floor((ms * 60) / 1000);
export const cycleLen = (d) => 2 * LEG_FRAMES + 2 * d;
export const endFrame = (n, d) => n * cycleLen(d);
export const windowOf = (d, k) => [k * cycleLen(d), (k + 1) * cycleLen(d)];

// ---- the phone replay profile (hundredths of a ms, tenth px)
export function phoneSamples(ms) {
  const dw = ms * 100;
  const up = Array.from({ length: LEG_FRAMES }, (_, i) => [TICK * i, FINGER_X * 10, (START_Y - STEP_PX * i) * 10]);
  const t1 = TICK * (LEG_FRAMES - 1) + dw;
  const down = Array.from({ length: LEG_FRAMES }, (_, i) => [t1 + TICK * (i + 1), FINGER_X * 10, (TOP_Y + STEP_PX * (i + 1)) * 10]);
  const t2 = t1 + TICK * LEG_FRAMES + dw;
  return [...up, [t1, FINGER_X * 10, TOP_Y * 10], ...down, [t2, FINGER_X * 10, (TOP_Y + STEP_PX * LEG_FRAMES) * 10]];
}
export const phoneLift = (ms) => TICK * (2 * LEG_FRAMES - 1) + 2 * ms * 100 + TICK;
export function phoneProfile(n, ms) {
  const lift = phoneLift(ms);
  return {
    id: `push-cycle-${n}x${ms}`, w: 430, h: 775, load: 'warm',
    swipes: Array.from({ length: n }, (_, i) => ({ start: i * (lift + LIFT_GAP), lift, s: phoneSamples(ms) })),
  };
}

// ---- TS STAND-IN: cutting a page record into cycles (no Lean spec)
export const SLOW = Object.freeze([34, 50]);
export const NEAR_MS = 300;

const median = (xs) => {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
};

/** Frames where the inner or visual viewport height changed, merged into one toolbar change when closer than NEAR_MS. */
export function viewportChanges(rec) {
  const frames = [];
  for (let i = 1; i < rec.t.length; i++) if (rec.ih[i] !== rec.ih[i - 1] || rec.vh[i] !== rec.vh[i - 1]) frames.push(i);
  const groups = [];
  for (const i of frames) {
    const g = groups[groups.length - 1];
    if (g && rec.t[i] - rec.t[g[g.length - 1]] < NEAR_MS) g.push(i); else groups.push([i]);
  }
  return groups.map((g) => ({ first: g[0], last: g[g.length - 1] }));
}

/** Per frame: whether it lies within NEAR_MS after the start of a viewport change group (through its end). */
export function nearMask(rec, groups = viewportChanges(rec)) {
  const near = new Array(rec.t.length).fill(false);
  for (const g of groups) {
    const end = rec.t[g.last] + NEAR_MS;
    for (let i = g.first; i < rec.t.length && rec.t[i] <= end; i++) near[i] = true;
  }
  return near;
}

/** The cycles of a record: cycle k runs from the start of its k-th open stretch to the frame before the next stretch's start. */
export function cycleRanges(rec) {
  const st = stretches(rec.o);
  return st.map(([a], k) => [a, k + 1 < st.length ? st[k + 1][0] - 1 : rec.t.length - 1]);
}

function lockOf(rec, a, b) {
  const frames = [];
  for (let i = a; i <= b; i++) frames.push([rec.y[i], 1]);
  const calls = (rec.ca ?? []).filter((c) => c[2] >= a && c[2] <= b + 1).map((c) => [c[0], 1]);
  const run = { frames, events: [], calls };
  if (lockRefusal(run)) return null;
  const k = lockReduce(run);
  return { reversals: k.frameReversals, fights: k.frameFights, displaced: k.displacedFrames };
}

/** The per-cycle counts of one pass record. The open stretch of a cycle is its first run of `o` frames; `lock` is TouchLock on it. */
export function recordCycles(rec) {
  const near = nearMask(rec);
  const st = stretches(rec.o);
  const evAt = (xs, a, b) => (xs ?? []).filter((f) => f >= a && f <= b).length;
  return cycleRanges(rec).map(([a, b], k) => {
    const gaps = [];
    for (let i = a + 1; i <= b; i++) gaps.push(rec.t[i] - rec.t[i - 1]);
    const [oa, ob] = st[k];
    let nearFrames = 0, slowNear34 = 0, slowNear50 = 0, slowFar34 = 0, slowFar50 = 0;
    for (let i = a + 1; i <= b; i++) {
      const g = rec.t[i] - rec.t[i - 1];
      if (near[i]) { nearFrames++; slowNear34 += g > 34; slowNear50 += g > 50; } else { slowFar34 += g > 34; slowFar50 += g > 50; }
    }
    const groups = viewportChanges(rec).filter((g) => g.first >= a && g.first <= b);
    return {
      k, from: a, to: b, frames: b - a + 1, openFrames: ob - oa + 1,
      slow34: gaps.filter((g) => g > 34).length, slow50: gaps.filter((g) => g > 50).length,
      medianGap: median(gaps), maxGap: gaps.length ? Math.max(...gaps) : null,
      viewportChanges: groups.length, nearFrames, farFrames: gaps.length - nearFrames, slowNear34, slowNear50, slowFar34, slowFar50,
      resizes: evAt(rec.rz, a, b), vvResizes: evAt(rec.vvr, a, b), vvScrolls: evAt(rec.vvs, a, b),
      lock: lockOf(rec, oa, ob),
    };
  });
}

/** The verdict inputs of a list of passes of one arm: H1 over all frames at the slow threshold `thr` (34 or 50), H2 first open against later ones. */
export function verdictInputs(passes, thr = 34) {
  const key = thr === 50 ? ['slowNear50', 'slowFar50'] : ['slowNear34', 'slowFar34'];
  const h1 = { changes: 0, slowNear: 0, framesNear: 0, slowFar: 0, framesFar: 0 };
  const h2 = { stretchesFirst: 0, fightsFirst: 0, stretchesLater: 0, fightsLater: 0 };
  for (const cyc of passes.map(recordCycles)) {
    for (const c of cyc) {
      h1.changes += c.viewportChanges; h1.slowNear += c[key[0]]; h1.framesNear += c.nearFrames; h1.slowFar += c[key[1]]; h1.framesFar += c.farFrames;
      if (!c.lock) continue;
      if (c.k === 0) { h2.stretchesFirst++; h2.fightsFirst += c.lock.fights; } else { h2.stretchesLater++; h2.fightsLater += c.lock.fights; }
    }
  }
  return { h1, h2 };
}

/** Per cycle index, summed over passes: the series the trend is read from. */
export function indexSeries(passes, field, n = CYCLES) {
  const out = new Array(n).fill(0), seen = new Array(n).fill(0);
  for (const cyc of passes.map(recordCycles)) cyc.slice(0, n).forEach((c, k) => { out[k] += c[field] ?? 0; seen[k]++; });
  return { sums: out, passes: seen };
}

// ---- TS STAND-IN: the arms of the lane (the flags are the user's felt-smoother composition; the site build prerenders the page of each arm)
export const USER_FLAGS = Object.freeze([
  'nav:earn-logical', 'hero.countdown:strip', 'platform:fade-threaded', 'platform.glint:offscreen-pause', 'platform.sweep:offscreen-pause',
  'morph.columns:idle-none', 'morph.countdown:strip', 'engine.events:quiet', 'engine.scroll:unthrottle',
]);

/** Flags that the site refuses without another one (morph.countdown:strip requires hero.countdown:strip), so a flag-off page drops them with it. */
const NEEDS = Object.freeze({ 'hero.countdown:strip': ['morph.countdown:strip'] });

/** `original` (no search), `rewrite` (default build), `user` (all flags), `off-<flag>` (all flags but one and what requires it: the flag's share). */
export function searchOf(arm) {
  if (arm === 'original') return null;
  if (arm === 'rewrite') return '';
  if (arm === 'user') return `?fw=${USER_FLAGS.join(',')}`;
  if (arm.startsWith('off-')) {
    const gone = [arm.slice(4), ...(NEEDS[arm.slice(4)] ?? [])];
    const rest = USER_FLAGS.filter((f) => !gone.includes(f));
    if (rest.length === USER_FLAGS.length) throw new Error(`unknown flag in ${arm}`);
    return `?fw=${rest.join(',')}`;
  }
  throw new Error(`unknown arm ${arm}`);
}

/** A file name the artifact upload accepts: it refuses `: < > | * ? " \` (push 3 lost all three sims on `off-hero.countdown:strip` log names). */
export const uploadName = (name) => name.replace(/[:<>|*?"\\]/g, '_');

/** The pages the site build must prerender for these arms (the rewrite default page is always built). */
export const searchesOf = (arms) => [...new Set(arms.filter((a) => a !== 'original' && a !== 'rewrite').map(searchOf))];
