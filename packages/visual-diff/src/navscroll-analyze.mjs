// Pure analysis of the nav scroll-hide probe (task nav-scroll-hide-check): no browser, no I/O. The page-side recorder is
// navscroll.mjs; this file turns its records into transitions, per-step differences and a curve check. TS-side stand-in:
// the hide rule itself is Lean (lean/Fw/Parts/Nav.lean); nothing here decides what the nav should do, it only compares
// the two arms' records.

/** CSS cubic-bezier(x1, y1, x2, y2) as a function of time fraction (Newton with bisection fallback). */
export function bezier(x1, y1, x2, y2) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const X = (s) => ((ax * s + bx) * s + cx) * s;
  const Y = (s) => ((ay * s + by) * s + cy) * s;
  const dX = (s) => (3 * ax * s + 2 * bx) * s + cx;
  return (x) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let s = x;
    for (let i = 0; i < 8; i++) {
      const e = X(s) - x;
      if (Math.abs(e) < 1e-7) return Y(s);
      const d = dX(s);
      if (Math.abs(d) < 1e-6) break;
      s -= e / d;
    }
    let lo = 0, hi = 1;
    s = x;
    for (let i = 0; i < 60; i++) {
      const e = X(s) - x;
      if (Math.abs(e) < 1e-7) break;
      if (e > 0) hi = s; else lo = s;
      s = (lo + hi) / 2;
    }
    return Y(s);
  };
}

/** Parse `cubic-bezier(a, b, c, d)` (or the CSS keywords) into a function; null when it is not one of those. */
export function easingOf(text) {
  const kw = { linear: [0, 0, 1, 1], ease: [0.25, 0.1, 0.25, 1], 'ease-in': [0.42, 0, 1, 1], 'ease-out': [0, 0, 0.58, 1], 'ease-in-out': [0.42, 0, 0.58, 1] };
  if (kw[text]) return bezier(...kw[text]);
  const m = /^cubic-bezier\(\s*([-\d.e]+)\s*,\s*([-\d.e]+)\s*,\s*([-\d.e]+)\s*,\s*([-\d.e]+)\s*\)$/.exec(text ?? '');
  return m ? bezier(+m[1], +m[2], +m[3], +m[4]) : null;
}

/** The hidden-state changes of a sweep: [{ at: index, u, y, to: boolean }] (first record counts against `false`). */
export function transitions(steps, hiddenOf = (s) => s.hidden) {
  const out = [];
  let prev = false;
  steps.forEach((s, i) => {
    const h = hiddenOf(s);
    if (h !== prev) out.push({ at: i, u: s.u, y: s.y, to: h, uBefore: i > 0 ? steps[i - 1].u : null, yBefore: i > 0 ? steps[i - 1].y : null });
    prev = h;
  });
  return out;
}

/**
 * Step-by-step comparison of two sweeps recorded on the same grid, matched on `uw` (the u asked for; u is scrollY minus the
 * section's document top). Returns the grid values where the hidden flag, the `is-` class list, or the visibility differ,
 * and the largest differences of the sticky element's top, of the nav's top and of the opacity over the matched steps.
 */
export function compareSweeps(a, b) {
  const byUw = new Map(b.map((r) => [r.uw, r]));
  const diff = { hidden: [], cls: [], vis: [] };
  let stTop = 0, navTop = 0, op = 0, matched = 0;
  for (const x of a) {
    const z = byUw.get(x.uw);
    if (!z) continue;
    matched++;
    if (x.hidden !== z.hidden) diff.hidden.push({ uw: x.uw, orig: x.hidden, port: z.hidden });
    if (x.cls !== z.cls) diff.cls.push({ uw: x.uw, orig: x.cls, port: z.cls });
    if (x.vis !== z.vis) diff.vis.push({ uw: x.uw, orig: x.vis, port: z.vis });
    if (x.stTop != null && z.stTop != null) stTop = Math.max(stTop, Math.abs(x.stTop - z.stTop));
    navTop = Math.max(navTop, Math.abs(x.top - z.top));
    op = Math.max(op, Math.abs(x.op - z.op));
  }
  return { matched, lengths: [a.length, b.length], diff, maxStickyTopDelta: +stTop.toFixed(2), maxNavTopDelta: +navTop.toFixed(2), maxOpacityDelta: +op.toFixed(3) };
}

/** Hidden-state edges of a wheel recording (changes only): the u of the first hidden frame and of the first visible frame after it, per direction. */
export function wheelEdges(rec) {
  const peak = rec.reduce((m, r, i) => (r.y > rec[m].y ? i : m), 0);
  const edge = (list, to) => { const r = list.find((x) => x.hidden === to); return r ? +r.u.toFixed(0) : null; };
  const down = rec.slice(0, peak + 1);
  const downOn = edge(down, true);
  const downOff = downOn == null ? null : edge(down.slice(down.findIndex((x) => x.hidden)), false);
  const up = rec.slice(peak);
  const upOn = edge(up, true);
  const upOff = upOn == null ? null : edge(up.slice(up.findIndex((x) => x.hidden)), false);
  return { downOn, downOff, upOn, upOff, peakU: +rec[peak].u.toFixed(0), frames: rec.length };
}

/**
 * Transform and opacity path of one recorded transition against the curve the browser itself reports for it. `anims` are the
 * running transitions read with getAnimations() ({ prop, startTime, duration, delay, easing }); `frames` the per-frame samples
 * ({ ct: document.timeline.currentTime, ty, op, vis }). For each frame inside the transition the expected value is
 * from + (to - from) * easing((ct - startTime - delay) / duration); the result is the largest absolute error and the frame
 * count. Elapsed time comes from the animation's own start time, so frame jitter does not enter.
 */
export function pathError(frames, anims, from, to) {
  const out = {};
  for (const [name, key] of [['transform', 'ty'], ['opacity', 'op']]) {
    const a = anims.find((x) => x.prop === name);
    if (!a) { out[name] = null; continue; }
    const ease = easingOf(a.easing);
    if (!ease) { out[name] = { unknownEasing: a.easing }; continue; }
    const f0 = from[key], f1 = to[key];
    let max = 0, used = 0, worstAt = null;
    for (const f of frames) {
      const el = f.ct - a.startTime - a.delay;
      if (el < 0 || el > a.duration) continue;
      const exp = f0 + (f1 - f0) * ease(el / a.duration);
      const err = Math.abs(f[key] - exp);
      used++;
      if (err > max) { max = err; worstAt = { elapsed: +el.toFixed(1), got: f[key], exp: +exp.toFixed(3) }; }
    }
    out[name] = { timing: { duration: a.duration, delay: a.delay, easing: a.easing }, frames: used, maxErr: +max.toFixed(3), worstAt };
  }
  return out;
}

/** Condensed description of a transition record, comparable across arms (no times that depend on the machine). */
export function describeTransition(rec) {
  const anims = rec.anims.map((a) => `${a.prop}:${a.duration}ms+${a.delay}ms ${a.easing}`).sort();
  const last = rec.frames[rec.frames.length - 1];
  const t0 = rec.frames.findIndex((f) => f.hidden !== rec.before.hidden);
  return {
    anims, before: pick(rec.before), end: pick(last), frames: rec.frames.length,
    classFlipFrame: t0, classFlipAtMs: t0 < 0 ? null : rec.frames[t0].dt,
  };
}

const pick = (r) => ({ hidden: r.hidden, tx: r.tx, ty: r.ty, op: r.op, vis: r.vis, top: r.top, bottom: r.bottom });

/** Smallest change of the nav's translateY (px) that counts as "the transform moved". */
export const TY_EPS = 1e-3;

/**
 * Frame indexes of one captured transition. Frame 0 is the sample taken in the same task as the scroll jump; frame k >= 1
 * is the k-th native rAF after it. `flip` is the first frame whose hidden flag differs from the start state (the class
 * change is visible), `move` the first frame whose computed translateY differs from the start state, `start` the first
 * frame at or after the transform transition's start time (null when the record has no start time: older probe versions).
 * Each is -1 / null when it never happens in the record.
 */
export function frameIndexes(rec) {
  const flip = rec.frames.findIndex((f) => f.hidden !== rec.before.hidden);
  const move = rec.frames.findIndex((f) => Math.abs(f.ty - rec.before.ty) > TY_EPS);
  let st = null;
  for (const f of rec.frames) {
    const a = (f.run ?? []).find((x) => x.prop === 'transform' && x.st != null);
    if (a) { st = a.st; break; }
  }
  const start = st == null ? null : rec.frames.findIndex((f) => f.ct >= st - 0.01);
  return { flip, move, start, lagMove: flip < 0 || move < 0 ? null : move - flip, lagStart: start == null || start < 0 || flip < 0 ? null : start - flip };
}

/**
 * Per-frame comparison of the same edge in the two arms: the frame of the class flip, of the first transform change, their
 * distance (lag), and translateY per frame from the jump (`n` frames). `aligned` is the largest |ty difference| when each
 * arm's frames are counted from its own first transform change, i.e. the curve itself with the start lag removed.
 */
export function compareTransitionFrames(o, p, n = 8) {
  const a = frameIndexes(o), b = frameIndexes(p);
  const ty = (r) => r.frames.slice(0, n).map((f) => +f.ty.toFixed(2));
  let aligned = null;
  if (a.move >= 0 && b.move >= 0) {
    aligned = 0;
    for (let k = 0; k < n; k++) {
      const x = o.frames[a.move + k], z = p.frames[b.move + k];
      if (x && z) aligned = Math.max(aligned, Math.abs(x.ty - z.ty));
    }
    aligned = +aligned.toFixed(2);
  }
  return {
    flip: { orig: a.flip, port: b.flip }, move: { orig: a.move, port: b.move }, start: { orig: a.start, port: b.start },
    lag: { orig: a.lagMove, port: b.lagMove }, lagStart: { orig: a.lagStart, port: b.lagStart },
    lagDelta: a.lagMove == null || b.lagMove == null ? null : b.lagMove - a.lagMove,
    ty: { orig: ty(o), port: ty(p) }, aligned,
  };
}

/**
 * The order of events of a record up to its first transform change (frames, scroll events, class mutations, transition
 * events), as one string, repeats collapsed: "f s f c tr ts f" where f frame sample, s scroll, c class change, tr
 * transitionrun, ts transitionstart (transform only). Null when the record has no event log (older probe versions).
 */
export function eventSequence(rec) {
  if (!rec.ev) return null;
  const { move } = frameIndexes(rec);
  const short = { frame: 'f', scroll: 's', class: 'c', 'transitionrun:transform': 'tr', 'transitionstart:transform': 'ts' };
  const out = [];
  let frames = 0;
  for (const e of rec.ev) {
    if (e.e === 'frame') frames++;
    if (move >= 0 && frames > move + 1) break;
    const s = short[e.e];
    if (s && out[out.length - 1] !== s) out.push(s);
  }
  return out.join(' ');
}

/**
 * Pooled lag statistics over runs. `rows` are { run, engine, id, key, orig, port } with the lag (frames) of the edge in each
 * arm. Groups by engine, width and edge; the counts say how often the port's lag is longer / shorter / equal to the
 * original's on the same edge of the same run.
 */
export function lagSummary(rows) {
  const groups = new Map();
  for (const r of rows) {
    if (r.orig == null || r.port == null) continue;
    const k = `${r.engine} ${r.id} ${r.key}`;
    const g = groups.get(k) ?? { engine: r.engine, id: r.id, key: r.key, orig: [], port: [], longer: 0, shorter: 0, equal: 0 };
    g.orig.push(r.orig);
    g.port.push(r.port);
    if (r.port > r.orig) g.longer++; else if (r.port < r.orig) g.shorter++; else g.equal++;
    groups.set(k, g);
  }
  return [...groups.values()];
}
