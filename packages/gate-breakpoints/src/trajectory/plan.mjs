// The dispatch plan of the trajectory probe: which engines run, over which width legs, on which paths. The decision is Lean's
// (lean/Fw/Gate/Trajectory.lean: enginesOf, legs, walks, plan; golden rows `plan` in golden/gate/trajectory.jsonl); this file is its
// TS twin (checked against the golden by test/trajectory.test.mjs). It imports nothing but reduce.mjs, so the workflow's plan step
// runs it with plain node (no install). `mergeRaws` is glue: it joins the raw readings of the legs of one engine.
import { pathToFileURL } from 'node:url';
import { ALLOWED_WIDTHS, bucket, needsSample, pickWidths } from './reduce.mjs';

/** The engines of a dispatch's `engines` input: macOS WebKit runs with every WebKit. Null when refused. */
export function enginesOf(input) {
  return {
    both: ['chromium', 'linux-webkit', 'mac-webkit'],
    chromium: ['chromium'],
    'playwright-webkit': ['linux-webkit', 'mac-webkit'],
  }[input] ?? null;
}

/** The paths an engine is walked on: those it can decide (Linux WebKit's 150 ms frames cannot decide the morph pushes). */
export const walksOf = (engine) => (engine === 'linux-webkit' ? ['hero'] : ['hero', 'morph']);

/** The width legs of an engine's job: one width per Linux leg, two legs on macOS (its slots are shared). */
export const LEG_TABLE = {
  'mac-webkit': [[390, 641], [640, 1280]],
  other: ALLOWED_WIDTHS.map((w) => [w]),
};

/** The table legs cut to the picked widths, empty legs dropped. */
export const legsOf = (engine, ws) => (LEG_TABLE[engine] ?? LEG_TABLE.other).map((l) => l.filter((w) => ws.includes(w))).filter((l) => l.length > 0);

/** The legs of a dispatch: [{ engine, widths, walks }] or null when the engines or widths input is refused. */
export function planOf(enginesIn, widthsIn) {
  const es = enginesOf(enginesIn);
  const ws = pickWidths(widthsIn);
  if (es === null || ws === null) return null;
  return es.flatMap((engine) => legsOf(engine, ws).map((widths) => ({ engine, widths, walks: walksOf(engine) })));
}

/** Whether the probe's emulated primary pointer is coarse at a width: the touch environment up to 640 CSS px (Lean `probeCoarse`). */
export const probeCoarse = (w) => w <= 640;

/** The flags whose whole style rule sits behind `(pointer: coarse)` (Lean `coarseOnly`). */
export const COARSE_ONLY = ['engine.scroll:unthrottle'];

/** Whether a run is proved inactive at a width: it names flags, all coarse-only, and the width emulates a fine pointer (Lean `inactiveAt`). */
export const inactiveAt = (flags, w) => flags.length > 0 && flags.every((f) => COARSE_ONLY.includes(f)) && !probeCoarse(w);

/** What a width of a run rests on: its readings, or the proof that it equals its faithful arm there (Lean `basisAt`). */
export const basisAt = (flags, w) => (inactiveAt(flags, w) ? 'same-by-proof' : 'measured');

export const EXTRA_CAP = 8;

export const hitIn = (ms, k) => ms.some((m) => bucket(m) === k);

export const gapsIn = (b, c) => Array.from({ length: 11 }, (_, k) => k).filter((k) => needsSample(k) && hitIn(b, k) && !hitIn(c, k));

export const gapCount = (b, c) => gapsIn(b.opening, c.opening).length + gapsIn(b.closing, c.closing).length;

export const moreReps = (extra, b, c) => extra < EXTRA_CAP && gapCount(b, c) !== 0;

export const retriesRole = (role, hasBase) => role === 'cand' && hasBase;

export const pooledReps = (reps, extra) => reps + extra;

export const poolPush = (a, b) => ({ opening: a.opening.concat(b.opening), closing: a.closing.concat(b.closing) });

export async function settleReps(b, c0, walk) {
  let extra = 0;
  let c = c0;
  while (moreReps(extra, b, c)) { c = poolPush(c, await walk(extra)); extra++; }
  return { extra, c };
}

/** A group repeats when its new units fall at two or more widths (Lean `repeats`). */
export const repeats = (ws) => new Set(ws).size >= 2;

/** Whether the engine decides the path: Linux WebKit's morph pushes cannot be decided (Lean `covers`). */
export const covers = (engine, walk) => !(engine === 'linux-webkit' && walk === 'morph');

/**
 * The verdict of a stored run (Lean `outcome`): `unjudged:coverage` when the engine cannot decide the path, `unjudged:widths`
 * when a lane width was not walked, `fail` on a content repeat, `unjudged:coverage` on a coverage repeat, else `pass`. The units at
 * widths that rest on proof count nothing.
 */
export function cellOutcome(s) {
  if (!covers(s.engine, s.walk)) return 'unjudged:coverage';
  if (!ALLOWED_WIDTHS.every((w) => s.widths.includes(w))) return 'unjudged:widths';
  const counted = (ws) => ws.filter((w) => basisAt(s.flags, w) === 'measured');
  if (s.groups.some((g) => repeats(counted(g.content)))) return 'fail';
  if (s.groups.some((g) => repeats(counted(g.coverage)))) return 'unjudged:coverage';
  return 'pass';
}

/**
 * The matrix of a job: its include rows for the legs of the engines `pick` accepts. `engine` is the CLI engine name
 * (chromium or playwright-webkit), `leg` the artifact suffix, `widths` and `paths` the `cli.mjs run` arguments.
 */
export function matrixOf(plan, pick) {
  return {
    include: plan.filter((l) => pick.includes(l.engine)).map((l) => ({
      engine: l.engine === 'chromium' ? 'chromium' : 'playwright-webkit',
      widths: l.widths.join(','),
      paths: l.walks.join(','),
      leg: l.widths.join('_'),
    })),
  };
}

/** Joins the raw readings of the legs of one engine: the runs in width order; the legs must agree on everything else. */
export function mergeRaws(raws) {
  if (raws.length === 0) throw new Error('merge: no leg');
  const [first] = raws;
  for (const r of raws) {
    for (const k of ['engine', 'search', 'hash', 'baseHash', 'reads', 'reps', 'version', 'debug']) {
      if (JSON.stringify(r[k]) !== JSON.stringify(first[k])) throw new Error(`merge: legs disagree on ${k}`);
    }
    if (JSON.stringify(r.paths) !== JSON.stringify(first.paths)) throw new Error('merge: legs disagree on paths');
  }
  const runs = raws.flatMap((r) => r.runs);
  runs.sort((a, b) => ALLOWED_WIDTHS.indexOf(a.width) - ALLOWED_WIDTHS.indexOf(b.width));
  return { ...first, refused: raws.some((r) => r.refused), runs };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const plan = planOf(process.argv[2] ?? 'both', process.argv[3] ?? '');
  if (plan === null) { console.error('plan: engines must be both, chromium or playwright-webkit; widths a comma list of 390, 640, 641, 1280 without repeats'); process.exit(1); }
  process.stdout.write(JSON.stringify({
    linux: matrixOf(plan, ['chromium', 'linux-webkit']),
    apple: matrixOf(plan, ['mac-webkit']),
  }) + '\n');
}
