// The decisions of the drawn-size image arm (task image-arm-v2): a TS twin of lean/Fw/Measure/ImageArm.lean, checked against the golden
// vectors packages/contracts/golden/gate/image-arm.jsonl (test/images-armplan.test.mjs). Pure: sizes are whole milli-CSS-pixels and the
// DPR a whole number, so no float decides anything. `imgOf` is glue: it turns one audit reading into the Lean `Img`.

export const snapEdge = (dpr, m) => Math.floor((m * dpr + 500) / 1000);
export const snapSize = (dpr, left, right) => Math.max(0, snapEdge(dpr, right) - snapEdge(dpr, left));
export const integral = (dpr, m) => (m * dpr) % 1000 === 0;

export const devW = (dpr, i) => Math.floor((i.w * dpr) / 1000);
export const devH = (dpr, i) => Math.floor((i.h * dpr) / 1000);

export function smaller(dpr, i) {
  const w = devW(dpr, i);
  const h = devH(dpr, i);
  return w > 0 && h > 0 && w <= i.natW && h <= i.natH && (w < i.natW || h < i.natH);
}

/** The reason an image has or has no 1:1 copy: ok | notImg | cropped | scaled | fractional | noSaving (first that holds). */
export function reachWhy(dpr, i) {
  if (i.kind !== 'img') return 'notImg';
  if (!i.plain) return 'cropped';
  if (i.scaleMin !== 1000 || i.scaleMax !== 1000) return 'scaled';
  if (!(integral(dpr, i.w) && integral(dpr, i.h))) return 'fractional';
  if (!smaller(dpr, i)) return 'noSaving';
  return 'ok';
}

/** The `exact` copy [w, h] of one image, or null. */
export const exactCopy = (dpr, i) => (reachWhy(dpr, i) === 'ok' ? [devW(dpr, i), devH(dpr, i)] : null);

const ceilDiv = (n, d) => Math.floor((n + d - 1) / d);
export const needW = (dpr, i) => ceilDiv(i.w * Math.max(i.scaleMax, 1000) * dpr, 1000000);
export const aspectH = (natW, natH, w) => Math.max(1, Math.floor((w * natH * 2 + natW) / (2 * natW)));

/** The `fit` copy [w, h] of one image (control policy), or null. */
export function fitCopy(dpr, i) {
  const n = needW(dpr, i);
  return i.natW > 0 && n > 0 && n < i.natW ? [n, aspectH(i.natW, i.natH, n)] : null;
}

const same = (a, b) => a !== null && b !== null && a[0] === b[0] && a[1] === b[1];

/** The `exact` copy of a file drawn by the elements `is` (non-empty): the one size they all agree on, else null. */
export function exactFile(dpr, is) {
  if (is.length === 0) return null;
  const c = exactCopy(dpr, is[0]);
  if (c === null) return null;
  return is.slice(1).every((j) => same(exactCopy(dpr, j), c)) ? c : null;
}

/** The `fit` copy of a file drawn by the elements `is` (non-empty): the need of the greatest, at the file's aspect ratio. */
export function fitFile(dpr, is) {
  if (is.length === 0) return null;
  const i = is[0];
  const n = Math.max(0, ...is.map((j) => needW(dpr, j)));
  return i.natW > 0 && n > 0 && n < i.natW ? [n, aspectH(i.natW, i.natH, n)] : null;
}

/** The copy [w, h] a file is planned with in every rep (`plans`: one [w, h] or null per rep), else null (twin of Lean `agreeCopy`). */
export function agreeCopy(plans) {
  if (plans.length === 0 || plans[0] === null) return null;
  return plans.every((p) => same(p, plans[0])) ? plans[0] : null;
}

/** The reps disagree about a file: some planned a copy and they did not all plan the same one (twin of Lean `disputedCopy`). */
export const disputedCopy = (plans) => plans.some((p) => p !== null) && agreeCopy(plans) === null;

export const decoded = (w, h) => 4 * w * h;
export const saving = (nw, nh, cw, ch) => Math.max(0, decoded(nw, nh) - decoded(cw, ch));

/** Decoded bytes the `exact` copy of a file saves, 0 when it has none. */
export function exactSaving(dpr, is) {
  const c = exactFile(dpr, is);
  return c === null ? 0 : saving(is[0].natW, is[0].natH, c[0], c[1]);
}

export const VERDICT_WORDS = ['pass', 'fail', 'unsettled', 'invalid', 'nc', 'error'];
const FAIL = 'fail';
const PASS = 'pass';

/** The decision of a part from its cells [{base, drawn}] (verdict words; 'error' for an error cell), each cell on its own. */
export function partDecision(cells) {
  if (cells.some((c) => c.drawn === FAIL && c.base === PASS)) return 'lookChange';
  if (cells.some((c) => c.drawn === FAIL)) return 'shippedFails';
  if (cells.length === 0 || cells.some((c) => c.drawn !== PASS)) return 'undecided';
  return 'admissible';
}

/**
 * The decision of a part from its cells [{ copy, base, drawn }] (twin of Lean `partDecisionWithCopies`): `noCopy` when no cell has a
 * copy, else `partDecision` of the cells that have one. An error cell (copies unknown) has `copy: true`.
 */
export function partDecisionWithCopies(cells) {
  const copied = cells.filter((c) => c.copy);
  return copied.length === 0 ? 'noCopy' : partDecision(copied);
}

// ---- glue: audit reading -> Lean Img -------------------------------------------------------------------------------------------

const milli = (x) => Math.round(x * 1000);

/** True when the drawn size does not come from the natural size (no `object-fit: none | scale-down`, no `background-size: auto`). */
export const sizedOf = (it) => !(typeof it.fit === 'string' && (it.fit === 'none' || it.fit === 'scale-down' || /(^|\s)auto(\s|$)/.test(it.fit)));

/**
 * One merged audit reading (audit.mjs mergeStops; `rw`, `rh` are the bounding-rect size of an <img>, recorded by inpage.mjs) as the
 * Lean `Img`. `plain` means the picture fills its box (img equals box, within a milli-pixel) and the size does not come from the
 * natural size. The scale is the element's own transform scale over every stop it was seen in view (visMin, visMax).
 */
export function imgOf(it) {
  const kind = it.kind === 'bg' ? 'bg' : 'img';
  const box = it.box ?? [0, 0];
  const pic = it.img ?? [0, 0];
  const sized = sizedOf(it);
  const rwMax = it.rwMax ?? it.rw ?? box[0];
  const rhMax = it.rhMax ?? it.rh ?? box[1];
  const still = milli(it.rwMin ?? rwMax) === milli(rwMax) && milli(it.rhMin ?? rhMax) === milli(rhMax);
  const plain = sized && still && milli(pic[0]) === milli(box[0]) && milli(pic[1]) === milli(box[1]);
  return {
    kind,
    natW: it.nat[0],
    natH: it.nat[1],
    w: milli(kind === 'img' ? rwMax : pic[0]),
    h: milli(kind === 'img' ? rhMax : pic[1]),
    plain,
    scaleMin: milli(Math.min(it.visMin ?? it.vis ?? 1, it.vis ?? 1)),
    scaleMax: milli(Math.max(it.visMax ?? it.vis ?? 1, it.vis ?? 1)),
  };
}
