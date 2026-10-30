// TS twin of lean/Fw/Device/FeelCapture.lean and the capture part of lean/Fw/Device/Feel.lean (golden:
// packages/contracts/golden/device/feel.jsonl, kinds capconsts, capture, blinks, closeCause, joint). Pure: no I/O, no clock.
// Units follow Lean: times in hundredths of a millisecond, scroll positions in tenths of a pixel, opacity in per mille.
import { readFileSync } from 'node:fs';
import { FEEL, LOOK_ARMS, SAME_ARMS, orderOf, scoresOf, reduceArm, reduceLook } from './device-feel.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/feel.jsonl', import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
export const CAP = Object.freeze(GOLDEN.find((l) => l.kind === 'capconsts'));

const sum = (l) => l.reduce((a, b) => a + b, 0);

/** Lean `gaps`. */
export const gaps = (ts) => ts.slice(1).map((t, i) => t - ts[i]);
/** Lean `diffs`, `movingFlags`. */
export const movingFlags = (ys) => {
  const ds = ys.slice(1).map((y, i) => y !== ys[i]);
  return ds.map((d, i) => d || (i > 0 && ds[i - 1]));
};
const moving = (ts, ys) => {
  const g = gaps(ts), m = movingFlags(ys);
  return g.slice(0, Math.min(g.length, m.length)).map((x, i) => [x, m[i]]);
};
/** Lean `longCount`: moving gaps longer than `thr`. */
export const longCount = (thr, ts, ys) => moving(ts, ys).filter(([g, m]) => m && thr < g).length;
/** Lean `movingCount`. */
export const movingCount = (ts, ys) => moving(ts, ys).filter(([, m]) => m).length;

/** Lean `reversals`: direction changes of the moves of the scroll series. */
export function reversals(ys) {
  const d = [];
  for (let i = 1; i < ys.length; i++) if (ys[i - 1] < ys[i]) d.push(true); else if (ys[i] < ys[i - 1]) d.push(false);
  let n = 0;
  for (let i = 1; i < d.length; i++) if (d[i] !== d[i - 1]) n++;
  return n;
}

/** Lean `dirAt`: the scroll move across the last frame at or before `t`. */
export function dirAt(ts, ys, t) {
  const k = ts.filter((x) => x <= t).length;
  return k < 2 ? 0 : (ys[k - 1] ?? 0) - (ys[k - 2] ?? 0);
}
/** Lean `fightAt`; a pin is `[t, from, to]`. */
export const fightAt = (ts, ys, [t, from, to]) => dirAt(ts, ys, t) * (to - from) < 0;
export const fights = (ts, ys, pins) => pins.filter((p) => fightAt(ts, ys, p)).length;
/** Lean `retargets`; a start is `[from, to]` in per mille. */
export const retargets = (starts) => starts.filter(([f]) => f > 0 && f < 1000).length;

/** Lean `dipAt`. */
export function dipAt(o, k) {
  const v = o[k] ?? 0;
  for (let i = 0; i < k; i++) {
    if (k - i <= CAP.blinkWithin && CAP.blinkDrop + v <= (o[i] ?? 0)) {
      for (let j = k + 1; j < k + 1 + CAP.blinkWithin; j++) if (j - i <= CAP.blinkWithin && CAP.blinkDrop + v <= (o[j] ?? 0)) return true;
    }
  }
  return false;
}
/** Lean `blinks`: runs of consecutive dipping frames, each counted once. */
export function blinks(o) {
  let n = 0;
  for (let k = 0; k < o.length; k++) if (dipAt(o, k) && !(k > 0 && dipAt(o, k - 1))) n++;
  return n;
}
export const blinksOf = (cards) => sum(cards.map(blinks));

/** Lean `workOf`. */
export const workOf = (c) => (c[0] ?? 0) + (c[1] ?? 0) + (c[2] ?? 0);

/** Lean `captureOf`. */
export function captureOf({ ts, ys, pins, starts, cards, zones }) {
  return {
    moving: movingCount(ts, ys), long17: longCount(CAP.long17Cs, ts, ys), long33: longCount(CAP.long33Cs, ts, ys), pins: pins.length,
    fights: fights(ts, ys, pins), reversals: reversals(ys), retargets: retargets(starts), blinks: blinksOf(cards), zoneWork: zones.map(workOf),
  };
}

/** Lean `medianOf`: the upper middle of the sorted list. */
export const medianOf = (l) => [...l].sort((a, b) => a - b)[Math.floor(l.length / 2)] ?? 0;
/** Lean `addZones`. */
export function addZones(a, b) {
  const n = Math.max(a.length, b.length);
  return Array.from({ length: n }, (_, i) => (a[i] ?? 0) + (b[i] ?? 0));
}
/** Lean `topZone`: the first zone with the most work, or null when none has any. */
export function topZone(w) {
  const m = w.reduce((a, b) => Math.max(a, b), 0);
  return m === 0 ? null : w.indexOf(m);
}
export const scoreOf = (s) => s.long33 + s.fights + s.blinks;
/** Lean `summaryOf`. */
export function summaryOf(cs) {
  if (cs.length === 0) return null;
  const s = {
    visits: cs.length, long17: medianOf(cs.map((c) => c.long17)), long33: medianOf(cs.map((c) => c.long33)), fights: medianOf(cs.map((c) => c.fights)),
    blinks: medianOf(cs.map((c) => c.blinks)), topZone: topZone(cs.reduce((acc, c) => addZones(acc, c.zoneWork), [])),
  };
  return { ...s, score: scoreOf(s) };
}
/** Lean `measured`: an arm against base. */
export function measured(a, b) {
  if (b.score + CAP.capMargin <= a.score) return 'heavier';
  if (a.score + CAP.capMargin <= b.score) return 'lighter';
  return 'same';
}
/** Lean `flagOf`. */
export function flagOf(verdict, dir) {
  if (verdict === 'worse' && dir === 'lighter') return 'felt worse, measured lighter';
  if (verdict === 'better' && dir === 'heavier') return 'felt better, measured heavier';
  return 'none';
}
/** Lean `jointWith`. */
export function jointWith(verdict, cs, bs) {
  const summary = summaryOf(cs), base = summaryOf(bs);
  return { verdict, summary, flag: flagOf(verdict, summary && base ? measured(summary, base) : null) };
}
/** Lean `capturesOf`: `caps` is indexed like the ratings. */
export const capturesOf = (seed, caps, a) => orderOf(seed).order.flatMap((x, i) => (x === a && caps[i] != null ? [caps[i]] : []));

/** Lean `jointSame` / `jointLook` over a session's ratings and captures. */
export function jointSession(seed, ratings, caps) {
  const n = orderOf(seed).order.length;
  const base = capturesOf(seed, caps.slice(0, n), FEEL.baseArm);
  const bs = scoresOf(orderOf(seed).order, ratings.slice(0, n), FEEL.baseArm);
  const same = SAME_ARMS.map((a, k) => ({
    id: a.id,
    ...jointWith(reduceArm(scoresOf(orderOf(seed).order, ratings.slice(0, n), k), bs), capturesOf(seed, caps.slice(0, n), k), base),
  }));
  const look = LOOK_ARMS.map((a, k) => {
    const r = ratings[n + k], c = caps[n + k];
    return { id: a.id, ...jointWith(reduceLook(r == null ? [] : [r], bs), c == null ? [] : [c], base) };
  });
  return { same, look };
}

export { closeCause, CAUSE_TEXT } from './wip-close.mjs';

/** One line per arm for the lead: rating verdict, capture summary, flag. */
export function jointText(seed, ratings, caps) {
  const j = jointSession(seed, ratings, caps);
  const row = (a) => {
    const s = a.summary;
    const cap = s ? `long>17ms ${s.long17}, long>34ms ${s.long33}, pin fights ${s.fights}, blinks ${s.blinks}, most work in zone ${s.topZone ?? '-'} (${s.visits} visit${s.visits === 1 ? '' : 's'})` : 'no capture';
    return `${a.id}: ${FEEL.texts[a.verdict]}; ${cap}${a.flag === 'none' ? '' : `  [DISAGREE: ${a.flag}]`}`;
  };
  return ['joint, rating next to capture (medians per visit):', ...j.same.map(row), ...j.look.map(row)].join('\n');
}
