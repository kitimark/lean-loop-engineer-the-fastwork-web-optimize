// Twin of lean/Fw/Engine/PaintVisible.lean (TS stand-in until the rule runs as fwcore); test/paintclip.test.mjs replays every
// line of golden/measure/paint-visible.jsonl through these functions. Integer pixels. Rects are { x, y, w, h }.
// Page-side code only gathers the facts; the class of a painted rect is decided here, from the facts.

/** The classes, in Lean `classes` order (report order). */
export const CLASSES = Object.freeze(['zero-area', 'hidden', 'clipped-out', 'covered', 'beyond-margin', 'prepaint-margin', 'noop', 'visible']);

/** The key of a class in a counts file (hyphens do not belong in count type names). */
export const classKey = (c) => c.replace(/-/g, '_');

/** Lean `Rect.area`. */
export const area = (r) => r.w * r.h;

/** Lean `Rect.inter`. */
export function inter(a, b) {
  const x = Math.max(a.x, b.x);
  const y = Math.max(a.y, b.y);
  return { x, y, w: Math.max(0, Math.min(a.x + a.w, b.x + b.w) - x), h: Math.max(0, Math.min(a.y + a.h, b.y + b.h) - y) };
}

/**
 * Lean `classify`: the class of one painted rect. `fact` is { rect, visible, coverage, hidden, covered, clipped, pix }, all rects in
 * one space (the viewport's for the view layer, the layer's own for a layer), pix 'unknown' | 'same' | 'changed'.
 */
export function classify(f) {
  if (area(f.rect) === 0) return 'zero-area';
  if (f.hidden) return 'hidden';
  if (f.clipped) return 'clipped-out';
  if (f.covered) return 'covered';
  if (area(inter(f.rect, f.visible)) > 0) return f.pix === 'same' ? 'noop' : 'visible';
  if (area(inter(f.rect, f.coverage)) > 0) return 'prepaint-margin';
  return 'beyond-margin';
}

/** Lean `seenArea`: the overlap with the viewport when the paint is `visible`, else 0. */
export const seenArea = (f) => (classify(f) === 'visible' ? area(inter(f.rect, f.visible)) : 0);

/** Lean `wasteArea`: pixels painted that the user does not see. */
export const wasteArea = (f) => area(f.rect) - seenArea(f);

/** Lean `tally`: how many of the classes in `names` equal `c`. */
export const tally = (names, c) => names.filter((n) => n === c).length;

/** Lean `per100`: rounded down; 0 for an empty window. */
export const per100 = (total, frames) => (frames === 0 ? 0 : Math.floor((total * 100) / frames));

/** Lean `margin`: the tile margin in layer pixels, 512 over the contents scale. */
export const margin = (scale) => Math.floor(512 / scale);

/** Lean `coverage`: the vertical tile coverage of viewport `v` in a layer `contentH` tall, moving `dir`, margin `m`. */
export function coverage(v, dir, m, contentH) {
  const h = v.h + m;
  const y0 = dir < 0 ? v.y - m : dir === 0 ? v.y - Math.floor(m / 2) : v.y;
  const y1 = y0 + h > contentH ? contentH - h : y0;
  return { x: v.x, y: Math.max(y1, 0), w: v.w, h };
}

/** Lean `rerasterArea`: pixels re-rastered when a layer's size goes from `old` to `neu` ([w, h]); 0 for a tiled layer or the same size. */
export const rerasterArea = (tiled, old, neu) => (tiled || (old[0] === neu[0] && old[1] === neu[1]) ? 0 : neu[0] * neu[1]);

/** [x, y, w, h] (the golden's rect form) to { x, y, w, h }. */
export const rectOf = (a) => ({ x: a[0], y: a[1], w: a[2], h: a[3] });

/** Lean `Rect.holds`: rect `c` holds all of `r`. */
export const holds = (c, r) => c.x <= r.x && r.x + r.w <= c.x + c.w && c.y <= r.y && r.y + r.h <= c.y + c.h;

/** Lean `Rect.unite`: the smallest rect that holds both. */
export const unite = (a, b) => {
  const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y);
  return { x, y, w: Math.max(Math.max(a.x + a.w, b.x + b.w) - x, 0), h: Math.max(Math.max(a.y + a.h, b.y + b.h) - y, 0) };
};

/** Lean `dirtyCap`: dirty rects a layer keeps (GraphicsLayerCA.cpp:1033 `maxDirtyRects`). */
export const DIRTY_CAP = 32;

/** Lean `addDirty`: one setNeedsDisplayInRect call on the kept rects `ds` (a new array). */
export function addDirty(ds, r) {
  if (ds.some((d) => holds(d, r))) return ds;
  if (ds.length < DIRTY_CAP) return [...ds, r];
  return [unite(ds[0], r), ...ds.slice(1)];
}

/** Lean `dirty`: the kept rects after the calls `rs` (rect objects), in order. */
export const dirty = (rs) => rs.reduce(addDirty, []);
