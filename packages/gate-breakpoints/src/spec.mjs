// What to run: the 124 probes of the Lean matrix (read from the generated file only) and the live-resize sweeps.
// Data shaping only: no pass/fail decisions.
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PKG } from './serve.mjs';

export const GEN_PATH = resolve(PKG, '../../apps/site/src/breakpoints.gen.json');
export const ANCHORS_PATH = join(dirname(fileURLToPath(import.meta.url)), 'anchors.json');
export const PART_JSON_DIR = resolve(PKG, '../../apps/site/src/parts');

export function loadGen(path = GEN_PATH) {
  const text = readFileSync(path);
  return { gen: JSON.parse(text.toString('utf8')), sha256: createHash('sha256').update(text).digest('hex') };
}

export function loadAnchors() {
  return JSON.parse(readFileSync(ANCHORS_PATH, 'utf8'));
}

/**
 * Which pilot parts a run covers. `wanted` is null (all parts, the default) or a list of part ids as in anchors.json.
 * Returns { covered, skipped } in anchors order; `narrowed` is true when some part is skipped. Unknown or empty ids throw
 * (a typo must not silently run nothing). Selection only: the verdict rule is untouched (verdict.mjs).
 */
export function selectParts(allIds, wanted) {
  if (wanted === null || wanted === undefined) return { covered: [...allIds], skipped: [], narrowed: false };
  const bad = wanted.filter((id) => !allIds.includes(id));
  if (wanted.length === 0 || bad.length > 0) {
    throw new Error(`--parts: ${wanted.length === 0 ? 'empty list' : `unknown part ${bad.join(', ')}`}; known: ${allIds.join(', ')}`);
  }
  const covered = allIds.filter((id) => wanted.includes(id));
  const skipped = allIds.filter((id) => !wanted.includes(id));
  return { covered, skipped, narrowed: skipped.length > 0 };
}

export function partJson(id) {
  const p = join(PART_JSON_DIR, id, 'part.json');
  return existsSync(p) ? JSON.parse(readFileSync(p, 'utf8')) : null;
}

/** Requested environment of a matrix probe. */
export function probeEnv(p) {
  return {
    width: p.width, height: p.height, deviceWidth: p.deviceWidth, deviceHeight: p.deviceHeight, dpr: p.dpr,
    hover: p.hover, pointer: p.pointer, reducedMotion: p.reducedMotion, colorScheme: p.colorScheme,
  };
}

const DESK = { height: 900, dpr: 1, deviceHeight: 900, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' };
const TOUCH = { height: 900, dpr: 2, deviceHeight: 900, hover: 'none', pointer: 'coarse', reducedMotion: 'no-preference', colorScheme: 'light' };
const PHONE = { dpr: 3, hover: 'none', pointer: 'coarse', reducedMotion: 'no-preference', colorScheme: 'light', deviceWidth: 430, deviceHeight: 932 };

/**
 * Live-resize sweeps (PLAN 6.6). A sweep is a list of stops; the page is loaded at stop 0 and then only resized.
 * Each stop is a full requested env. Device width follows the Lean model (equal to the width on desk and touch, 430 on the phone).
 */
export function sweepDefs(gen) {
  const widths = [...new Set(gen.edgePairs.width.flat())].filter((w) => w >= 320).sort((a, b) => b - a); // 1512 .. 320
  const down = widths;
  const up = [...widths].reverse().slice(1);
  const desk = (w) => ({ ...DESK, width: w, deviceWidth: w });
  const touch = (w) => ({ ...TOUCH, width: w, deviceWidth: w });
  return [
    { id: 'desktop-1512-320-1512', blurb: 'desktop 1512 down through every edge to 320 and back up', stops: [...down, ...up].map(desk) },
    { id: 'phone-rotation', blurb: 'phone 430x932 <-> 932x430 (device width stays 430), twice', stops: [[430, 932], [932, 430], [430, 932], [932, 430], [430, 932]].map(([w, h]) => ({ ...PHONE, width: w, height: h })) },
    { id: 'touch-1024-1201', blurb: 'touch tablet 1024 <-> 1201, twice', stops: [1024, 1201, 1024, 1201, 1024].map(touch) },
    { id: 'pain-1440-600-1440', blurb: "v1's 1440 -> 600 -> 1440 pain sequence, twice", stops: [1440, 600, 1440, 600, 1440].map(desk) },
  ];
}

/**
 * Lean's expected truth for a sweep stop, looked up in the matrix by (width, device width, hover, pointer, reduced
 * motion, scheme); height and DPR are irrelevant (MQ.eval_indep_height_dpr). Returns undefined when no probe has this
 * environment, and also when two probes with it disagree.
 */
export function expectFor(gen, env) {
  const hits = gen.matrix.probes.filter((p) => p.width === env.width && p.deviceWidth === env.deviceWidth && p.hover === env.hover
    && p.pointer === env.pointer && p.reducedMotion === env.reducedMotion && p.colorScheme === env.colorScheme);
  if (hits.length === 0) return undefined;
  const first = JSON.stringify(hits[0].expect) + JSON.stringify(hits[0].expectNeutral);
  if (hits.some((h) => JSON.stringify(h.expect) + JSON.stringify(h.expectNeutral) !== first)) return undefined;
  return { expect: hits[0].expect, expectNeutral: hits[0].expectNeutral, from: hits[0].id };
}
