export const CLASSES = Object.freeze(['zero-area', 'hidden', 'clipped-out', 'covered', 'beyond-margin', 'prepaint-margin', 'noop', 'visible']);

export const classKey = (c) => c.replace(/-/g, '_');

export const area = (r) => r.w * r.h;

export function inter(a, b) {
  const x = Math.max(a.x, b.x);
  const y = Math.max(a.y, b.y);
  return { x, y, w: Math.max(0, Math.min(a.x + a.w, b.x + b.w) - x), h: Math.max(0, Math.min(a.y + a.h, b.y + b.h) - y) };
}

export function classify(f) {
  if (area(f.rect) === 0) return 'zero-area';
  if (f.hidden) return 'hidden';
  if (f.clipped) return 'clipped-out';
  if (f.covered) return 'covered';
  if (area(inter(f.rect, f.visible)) > 0) return f.pix === 'same' ? 'noop' : 'visible';
  if (area(inter(f.rect, f.coverage)) > 0) return 'prepaint-margin';
  return 'beyond-margin';
}

export const seenArea = (f) => (classify(f) === 'visible' ? area(inter(f.rect, f.visible)) : 0);

export const wasteArea = (f) => area(f.rect) - seenArea(f);

export const tally = (names, c) => names.filter((n) => n === c).length;

export const per100 = (total, frames) => (frames === 0 ? 0 : Math.floor((total * 100) / frames));

export const margin = (scale) => Math.floor(512 / scale);

export function coverage(v, dir, m, contentH) {
  const h = v.h + m;
  const y0 = dir < 0 ? v.y - m : dir === 0 ? v.y - Math.floor(m / 2) : v.y;
  const y1 = y0 + h > contentH ? contentH - h : y0;
  return { x: v.x, y: Math.max(y1, 0), w: v.w, h };
}

export const rerasterArea = (tiled, old, neu) => (tiled || (old[0] === neu[0] && old[1] === neu[1]) ? 0 : neu[0] * neu[1]);

export const rectOf = (a) => ({ x: a[0], y: a[1], w: a[2], h: a[3] });

export const holds = (c, r) => c.x <= r.x && r.x + r.w <= c.x + c.w && c.y <= r.y && r.y + r.h <= c.y + c.h;

export const unite = (a, b) => {
  const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y);
  return { x, y, w: Math.max(Math.max(a.x + a.w, b.x + b.w) - x, 0), h: Math.max(Math.max(a.y + a.h, b.y + b.h) - y, 0) };
};

export const DIRTY_CAP = 32;

export function addDirty(ds, r) {
  if (ds.some((d) => holds(d, r))) return ds;
  if (ds.length < DIRTY_CAP) return [...ds, r];
  return [unite(ds[0], r), ...ds.slice(1)];
}

export const dirty = (rs) => rs.reduce(addDirty, []);
