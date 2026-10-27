/** Column pictures in the flip: the `object-fit: cover` model and the crossing knot (Lean Fw.Parts.MorphGeom, MorphGeomPic). */

export interface Rc {
  l: number;
  t: number;
  r: number;
  b: number;
}

/** The larger of the two fit ratios (Lean coverK). */
export const coverK = (bw: number, bh: number, iw: number, ih: number): number => Math.max(bw / iw, bh / ih);

/** The rectangle `object-fit: cover` draws in a bw by bh box, centred (Lean drawn). */
export function drawn(bw: number, bh: number, iw: number, ih: number): Rc {
  const k = coverK(bw, bh, iw, ih);
  return { l: (bw - iw * k) / 2, t: (bh - ih * k) / 2, r: (bw + iw * k) / 2, b: (bh + ih * k) / 2 };
}

/** The key offsets of a picture's transform: a knot at the crossing q when it is strictly inside (0, 1) (Lean kinkKnots). */
export const kinkKnots = (q: number): number[] => (q > 0 && q < 1 ? [0, q, 1] : [0, 1]);

/** The picture rectangle after a transform about its centre: translate (tx, ty), then scale (sx, sy) (Lean xform). */
export function xform(r: Rc, tx: number, ty: number, sx: number, sy: number): Rc {
  const cx = (r.l + r.r) / 2 + tx;
  const cy = (r.t + r.b) / 2 + ty;
  const hw = (sx * (r.r - r.l)) / 2;
  const hh = (sy * (r.b - r.t)) / 2;
  return { l: cx - hw, t: cy - hh, r: cx + hw, b: cy + hh };
}

/** The crop window: the static box [0, c1] cut by the clipper moved by tk (Lean composedCrop). */
export const cropAt = (tk: number, c1: number, h: number): Rc => ({ l: Math.max(0, tk), t: 0, r: Math.min(c1, tk + c1), b: h });
