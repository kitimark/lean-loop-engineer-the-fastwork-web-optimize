import { MORPH_NODES, envFor } from './registry.mjs';

const gcd = (a, b) => { a = a < 0n ? -a : a; b = b < 0n ? -b : b; while (b) [a, b] = [b, a % b]; return a; };
export const rat = (n, d = 1n) => {
  n = BigInt(n); d = BigInt(d);
  if (d === 0n) return { n: 0n, d: 1n };
  if (d < 0n) { n = -n; d = -d; }
  const g = gcd(n, d) || 1n;
  return { n: n / g, d: d / g };
};
export const ZERO = rat(0), ONE = rat(1);
export const add = (a, b) => rat(a.n * b.d + b.n * a.d, a.d * b.d);
export const sub = (a, b) => rat(a.n * b.d - b.n * a.d, a.d * b.d);
export const mul = (a, b) => rat(a.n * b.n, a.d * b.d);
export const div = (a, b) => (b.n === 0n ? ZERO : rat(a.n * b.d, a.d * b.n));
export const neg = (a) => rat(-a.n, a.d);
export const cmp = (a, b) => { const x = a.n * b.d, y = b.n * a.d; return x < y ? -1 : x > y ? 1 : 0; };
export const lt = (a, b) => cmp(a, b) < 0;
export const le = (a, b) => cmp(a, b) <= 0;
export const eq = (a, b) => cmp(a, b) === 0;
export const max = (a, b) => (lt(a, b) ? b : a);
export const min = (a, b) => (lt(a, b) ? a : b);
export const abs = (a) => (a.n < 0n ? neg(a) : a);
export const ratStr = (r) => `${r.n}/${r.d}`;
export const ratOf = (s) => { const [n, d] = String(s).split('/'); return rat(BigInt(n), BigInt(d ?? '1')); };
export const ratQ = (x) => rat(BigInt(Math.round(x)), 1000n);

export const PIX_TOL = rat(1, 2);
export const tolCss = (dpr) => div(PIX_TOL, dpr);
export const within = (t, x, y) => le(sub(x, t), y) && le(y, add(x, t));
export const cellEq = (ts, a, b) => ts.length === a.length && a.length === b.length && ts.every((t, i) => within(t, a[i], b[i]));

export const resolveLen = (l, side) => (l.k === 'px' ? l.v : div(mul(l.v, side), rat(100)));
export const expand4 = (l) => {
  if (l.length === 1) return [l[0], l[0], l[0], l[0]];
  if (l.length === 2) return [l[0], l[1], l[0], l[1]];
  if (l.length === 3) return [l[0], l[1], l[2], l[1]];
  if (l.length === 4) return [l[0], l[1], l[2], l[3]];
  return null;
};
export const usedRadius = (r, w, h) => min(r, min(div(w, rat(2)), div(h, rat(2))));
export const shapeOfBox = (b, r) => ({ rect: b, r: usedRadius(r, b.w, b.h) });
export const insetRect = (box, i) => {
  const l = resolveLen(i.left, box.w), rt = resolveLen(i.right, box.w), t = resolveLen(i.top, box.h), bt = resolveLen(i.bottom, box.h);
  return { x: add(box.x, l), y: add(box.y, t), w: max(ZERO, sub(sub(box.w, l), rt)), h: max(ZERO, sub(sub(box.h, t), bt)) };
};
export const radiusShape = (rect, radii) => {
  if (radii === null) return { rect, r: ZERO };
  const [tl] = radii;
  const rx = (c) => resolveLen(c, rect.w), ry = (c) => resolveLen(c, rect.h);
  return radii.every((c) => eq(rx(c), rx(tl)) && eq(ry(c), rx(tl))) ? shapeOfBox(rect, rx(tl)) : null;
};
export const clipRectOfInset = (box, i) => radiusShape(insetRect(box, i), i.radii);

const digitsVal = (s) => (s.length > 0 && /^[0-9]+$/.test(s) ? BigInt(s) : null);
export function parseDec(s) {
  let neg_ = false, t = s;
  if (t.startsWith('-')) { neg_ = true; t = t.slice(1); } else if (t.startsWith('+')) t = t.slice(1);
  const dot = t.indexOf('.');
  const ip = dot < 0 ? t : t.slice(0, dot);
  const sign = (r) => (neg_ ? neg(r) : r);
  if (dot < 0) { const n = digitsVal(ip); return n === null ? null : sign(rat(n)); }
  const i = ip === '' ? 0n : digitsVal(ip);
  const fr = t.slice(dot + 1);
  const f = digitsVal(fr);
  if (i === null || f === null) return null;
  return sign(rat(i * 10n ** BigInt(fr.length) + f, 10n ** BigInt(fr.length)));
}
export function parseLen(s) {
  if (s === '0') return { k: 'px', v: ZERO };
  if (s.endsWith('px')) { const v = parseDec(s.slice(0, -2)); return v === null ? null : { k: 'px', v }; }
  if (s.endsWith('%')) { const v = parseDec(s.slice(0, -1)); return v === null ? null : { k: 'pct', v }; }
  return null;
}
const parseLens = (ts) => { const out = []; for (const t of ts) { const l = parseLen(t); if (l === null) return null; out.push(l); } return out; };
const trimAscii = (s) => s.replace(/^[\t\n\v\f\r ]+/, '').replace(/[\t\n\v\f\r ]+$/, '');
export function parseInset(s) {
  const t = trimAscii(s);
  if (!(t.startsWith('inset(') && t.endsWith(')'))) return null;
  const toks = t.slice(6, -1).split(' ').filter((x) => x !== '');
  let n = 0;
  while (n < toks.length && toks[n] !== 'round') n++;
  const sides = parseLens(toks.slice(0, n));
  const four = sides === null ? null : expand4(sides);
  if (four === null) return null;
  const [top, right, bottom, left] = four;
  const rest = toks.slice(n);
  if (rest.length === 0) return { top, right, bottom, left, radii: null };
  if (rest[0] !== 'round') return null;
  const rs = parseLens(rest.slice(1));
  const q4 = rs === null ? null : expand4(rs);
  return q4 === null ? null : { top, right, bottom, left, radii: q4 };
}
export const readShape = (box, radius, clip) => {
  if (trimAscii(clip) === 'none') return shapeOfBox(box, radius);
  const i = parseInset(clip);
  return i === null ? null : clipRectOfInset(box, i);
};
export const shapeVec = (s) => [s.rect.x, s.rect.y, s.rect.w, s.rect.h, s.r];

export const lerpVec = (f, a, b) => (a.length !== b.length ? null : a.map((x, i) => add(x, mul(sub(b[i], x), f))));
export const sortedKeys = (s) => s.every((p, i) => i === 0 || lt(s[i - 1].k, p.k));
export function interpAt(s, k) {
  for (let i = 0; i < s.length; i++) {
    if (i === s.length - 1) return eq(k, s[i].k) ? s[i].v : null;
    const a = s[i], b = s[i + 1];
    if (lt(k, a.k)) return null;
    if (le(k, b.k)) return lt(a.k, b.k) ? lerpVec(div(sub(k, a.k), sub(b.k, a.k)), a.v, b.v) : null;
  }
  return null;
}
export const matchAt = (tols, ref, cand, shift) => {
  let n = 0, ok = true;
  for (const { k, v } of cand) {
    const r = interpAt(ref, add(k, shift));
    if (r !== null) { n++; ok = ok && cellEq(tols, r, v); }
  }
  return { n, ok };
};
export function matchedGrade(tols, grid, frameKey, minCovered, ref, cand) {
  if (!sortedKeys(ref) || !sortedKeys(cand)) return null;
  const m0 = matchAt(tols, ref, cand, ZERO);
  if (m0.n < minCovered) return null;
  if (m0.ok) return 'E';
  const q = grid.some((s) => {
    if (s.n === 0n || !le(abs(s), ONE)) return false;
    const r = matchAt(tols, ref, cand, mul(s, frameKey));
    return minCovered <= r.n && r.ok;
  });
  return q ? 'Q' : 'L';
}

const clamp01 = (x) => max(ZERO, min(ONE, x));
export const panelProgress = (m) => clamp01(div(sub(m, rat(2, 25)), rat(18, 25)));
export const panelOpacity = panelProgress;
export const panelBlurPx = (m) => mul(sub(ONE, panelProgress(m)), rat(12));
export const panelScale = (m) => add(rat(24, 25), div(m, rat(25)));
export const effectAt = (m) => [panelOpacity(m), panelBlurPx(m), panelScale(m)];
export const READ_STEP = rat(1, 1000);
export const effectTols = (dpr, side) => [rat(1, 100), tolCss(dpr), add(div(tolCss(dpr), side), READ_STEP)];
export const effClock = (p) => add(rat(2, 25), mul(rat(18, 25), p));
export const lagAt = (prev, cur) => (lt(ZERO, cur.op) && lt(cur.op, ONE) && !eq(prev.nav, cur.nav)
  ? div(sub(cur.nav, effClock(cur.op)), sub(cur.nav, prev.nav)) : null);
export function lagFrames(fs) {
  const ls = [];
  for (let i = 1; i < fs.length; i++) { const l = lagAt(fs[i - 1], fs[i]); if (l !== null) ls.push(abs(l)); }
  return ls.length < 3 ? null : ls.reduce(max, ZERO);
}
export const LAG_SLACK = rat(1, 10);
export const lagGrade = (lag) => (le(lag, add(ONE, LAG_SLACK)) ? 'Q' : 'L');
export const laggedKey = (l, prev, cur) => sub(cur, mul(l, sub(cur, prev)));
export const EDGE = rat(1, 100);
export const keptInterior = (k) => lt(EDGE, k) && lt(k, sub(ONE, EDGE));
export const laggedSeries = (l, fs) => fs.slice(1).map((c, i) => ({ k: laggedKey(l, fs[i].k, c.k), v: c.v })).filter((p) => keptInterior(p.k));
export const residual = (s) => s.map(({ k, v }) => { const e = effectAt(k); return { k, v: Array.from({ length: Math.min(v.length, e.length) }, (_, i) => sub(v[i], e[i])) }; });
export const modelGrade = (tols, minCovered, ref, cand) => matchedGrade(tols, [], ONE, minCovered, residual(ref), residual(cand));
export const shiftedGrade = (tols, minCovered, ref, l, fs) => modelGrade(tols, minCovered, ref, seriesOf(laggedSeries(l, fs)));
export const panelGrade = (series, lag, shifted) => (series === null ? null : series === 'E' ? 'E'
  : lag === null ? null : le(lag, add(ONE, LAG_SLACK)) && shifted === 'E' ? 'Q' : 'L');
export function panelCell(tols, minCovered, ref, fs) {
  const series = modelGrade(tols, minCovered, ref, seriesOf(fs.filter((p) => keptInterior(p.k))));
  const lag = lagFrames(fs.map((f) => ({ nav: f.k, op: f.v[0] })));
  return { grade: panelGrade(series, lag, lag === null ? null : shiftedGrade(tols, minCovered, ref, lag, fs)), lag };
}

export const darkness = (layer, cls) => (layer !== null ? layer : cls ? ONE : ZERO);
const changes = (l) => { let n = 0; for (let i = 1; i < l.length; i++) if (!eq(l[i - 1], l[i])) n++; return n; };
export function painGrade(b, c) {
  if (b.length !== c.length || b.length === 0) return null;
  const tol = rat(1, 100);
  const at = (l, i) => (i >= 0 && i < l.length ? l[i] : ZERO);
  const same = (i) => within(tol, at(b, i), at(c, i));
  const bin = (x) => eq(x, ZERO) || eq(x, ONE);
  const slip = (i) => bin(at(b, i)) && bin(at(c, i)) && ((i > 0 && within(tol, at(b, i - 1), at(c, i))) || within(tol, at(b, i + 1), at(c, i)));
  const idx = b.map((_, i) => i);
  if (idx.every(same)) return 'E';
  return changes(b) === changes(c) && idx.every((i) => same(i) || slip(i)) ? 'Q' : 'L';
}

const RANK = { E: 0, E1: 1, Q: 2, L: 3, invalid: 0 };
export const worst = (gs) => (gs.length === 0 || gs.includes(null) ? null : gs.reduce((w, g) => (RANK[g] > RANK[w] ? g : w)));

export const MIN_COVERED = 8;

export const layoutOf = (nodes) => Object.fromEntries(nodes.map((n) => [n.id, Object.fromEntries(n.props.map((p, i) => [p.id, i]))]));

const num = (x) => (Array.isArray(x) && typeof x[0] === 'number' ? x : null);

export function navShapeOf(row, layout) {
  const e = row.nodes?.nav?.[0], ix = layout.nav;
  if (!e || !ix) return null;
  const rect = e[ix.rect], rad = num(e[ix['border-radius']]);
  if (!Array.isArray(rect) || rect.length !== 4 || rect.some((x) => typeof x !== 'number') || rad === null) return null;
  const clip = ix['clip-path'] !== undefined && typeof e[ix['clip-path']] === 'string' ? e[ix['clip-path']] : 'none';
  const s = readShape({ x: ratQ(rect[0]), y: ratQ(rect[1]), w: ratQ(rect[2]), h: ratQ(rect[3]) }, ratQ(rad[0]), clip);
  return s === null ? null : shapeVec(s);
}

export function panelEffectOf(row, layout) {
  const e = row.nodes?.panel?.[0], ix = layout.panel;
  if (!e || !ix) return null;
  const op = num(e[ix.opacity]);
  if (op === null) return null;
  const blur = Array.isArray(e[ix['filter.num']]) && typeof e[ix['filter.num']][0] === 'number' ? ratQ(e[ix['filter.num']][0]) : ZERO;
  const lin = e[ix['transform.lin']];
  const scale = Array.isArray(lin) && typeof lin[0] === 'number' ? ratQ(lin[0]) : ONE;
  return [ratQ(op[0]), blur, scale];
}

export function seriesOf(samples) {
  const s = samples.slice().sort((a, b) => cmp(a.k, b.k));
  return s.filter((p, i) => i === 0 || lt(s[i - 1].k, p.k));
}

const mOf = (row) => (typeof row.m === 'number' ? rat(BigInt(Math.round(row.m)), 10000n) : null);

export function morphCells({ width, base, cand, layout, phase }) {
  const env = envFor(width), dpr = rat(env.dpr), side = rat(width);
  const rowsOf = (arm) => (arm?.morph?.phases?.[phase] ?? []);
  const sample = (rows, fn) => rows.flatMap((r) => { const m = mOf(r), v = m === null || !keptInterior(m) ? null : fn(r); return v === null ? [] : [{ k: m, v }]; });
  const navTol = Array(5).fill(tolCss(dpr));
  const effTol = effectTols(dpr, side);
  const refNav = seriesOf(sample(rowsOf(base), (r) => navShapeOf(r, layout)));
  const refEff = seriesOf(sample(rowsOf(base), (r) => panelEffectOf(r, layout)));
  const reps = [...new Set(rowsOf(cand).map((r) => r.rep ?? 0))].sort((a, b) => a - b);
  const out = { nav: [], panel: [], lag: [] };
  for (const rep of reps) {
    const rows = rowsOf(cand).filter((r) => (r.rep ?? 0) === rep);
    out.nav.push(matchedGrade(navTol, [ZERO], ONE, MIN_COVERED, refNav, seriesOf(sample(rows, (r) => navShapeOf(r, layout)))));
    const frames = rows.flatMap((r) => { const m = mOf(r), e = panelEffectOf(r, layout); return m === null || e === null ? [] : [{ k: m, v: e }]; });
    const cell = panelCell(effTol, MIN_COVERED, refEff, frames);
    out.lag.push(cell.lag === null ? null : ratStr(cell.lag));
    out.panel.push(cell.grade);
  }
  return out;
}

export const painSeries = (rows) => rows.map((r) => darkness(typeof r.layer === 'number' ? ratQ(r.layer * 1000) : null, r.cls === true));

export const painDir = (b, c) => (b.length > 0 && changes(b) === 0 ? null : painGrade(b, c));

export const painCell = (base, cand) => ['up', 'down'].map((dir) => painDir(painSeries(base?.[dir] ?? []), painSeries(cand?.[dir] ?? [])));

export const CAROUSEL_GRID = [-1, -3 / 4, -1 / 2, -1 / 4, 1 / 4, 1 / 2, 3 / 4, 1].map((x) => rat(Math.round(x * 4), 4));
export const FRAME_MS = rat(50, 3);
export const CAROUSEL_MIN_COVERED = 4;

const sameVec = (a, b) => a.length === b.length && a.every((x, j) => x === b[j]);
export const restedBefore = (rows, i) => i >= 1 && !!rows[i - 1]?.v && !!rows[i]?.v && sameVec(rows[i - 1].v, rows[i].v);

export function swapSpans(rows, still = 6) {
  const spans = [];
  let cur = null, quiet = 0;
  for (let i = 1; i < rows.length; i++) {
    const a = rows[i - 1], b = rows[i];
    if (!a?.v || !b?.v) { cur = null; quiet = 0; continue; }
    const same = sameVec(a.v, b.v);
    if (!same && cur === null) cur = { from: i - 1, to: i };
    if (cur === null) continue;
    if (same) quiet++; else { quiet = 0; cur.to = i; }
    if (quiet >= still) { if (restedBefore(rows, cur.from)) spans.push(cur); cur = null; quiet = 0; }
  }
  return spans;
}

export function spanSeries(rows, { from, to }) {
  const vs = rows.slice(from, Math.min(rows.length, to + 2)).map((r) => r?.v ?? []);
  const full = vs.reduce((m, v) => Math.max(m, v.length), 0);
  return vs.map((v, j) => ({ k: mul(rat(BigInt(j)), FRAME_MS), v })).filter((p) => p.v.length === full).map((p) => ({ k: p.k, v: p.v.map(ratQ) }));
}

const sameRatVec = (a, b) => a.length === b.length && a.every((x, i) => eq(x, b[i]));
export function dropHold(s) {
  let i = 0;
  while (i + 1 < s.length && sameRatVec(s[i].v, s[i + 1].v)) i++;
  return s.slice(i);
}
export const rebase = (s) => (s.length === 0 ? s : [{ k: ZERO, v: s[0].v }, ...s.slice(1).map(({ k, v }) => ({ k: sub(k, s[0].k), v }))]);
export const swapSeries = (rows, sp) => rebase(dropHold(spanSeries(rows, sp)));
export const holdFrames = (rows, sp) => spanSeries(rows, sp).length - dropHold(spanSeries(rows, sp)).length;

export const swapsOf = (rows, still = 6) => swapSpans(rows, still).map((sp) => swapSeries(rows, sp));

export const swapGrade = (dpr, b, c) => matchedGrade(Array(b[0]?.v.length ?? 0).fill(tolCss(dpr)), CAROUSEL_GRID, FRAME_MS, CAROUSEL_MIN_COVERED, b, c);

export const carouselGrade = (nb, nc, reps) => (nb === nc ? worst(reps) : 'L');

export const HOLD_TOL = 1;
export const holdGrade = (hb, hc) => (hb <= hc + HOLD_TOL && hc <= hb + HOLD_TOL ? 'E' : 'L');
export const repGrade = (motion, hb, hc) => (motion === null ? null : worst([motion, holdGrade(hb, hc)]));

export const holdsOf = (rows, still = 6) => swapSpans(rows ?? [], still).map((sp) => holdFrames(rows, sp));

export function carouselCellAt(dpr, base, cand) {
  const bs = swapsOf(base ?? []), cs = swapsOf(cand ?? []);
  const hbs = holdsOf(base), hcs = holdsOf(cand);
  const grades = bs.slice(0, Math.min(bs.length, cs.length)).map((b, i) => repGrade(swapGrade(dpr, b, cs[i]), hbs[i], hcs[i]));
  return { swaps: [bs.length, cs.length], grades, grade: carouselGrade(bs.length, cs.length, grades) };
}

export const STILL_FRAMES = 6;
export const SETTLE_CAP_MS = rat(2200);
export const TAIL_CAP_MS = rat(1500);

const sameInts = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
export function settleRun(still, cap, s0, prev, frames) {
  let st = { prev, moved: false, quiet: 0 }, now = s0, n = 0;
  for (const { t, v } of frames) {
    if (le(add(s0, cap), now)) return { consumed: n, quiet: false };
    st = sameInts(st.prev, v) ? { prev: v, moved: st.moved, quiet: st.moved ? st.quiet + 1 : st.quiet } : { prev: v, moved: true, quiet: 0 };
    n++; now = t;
    if (st.moved && still <= st.quiet) return { consumed: n, quiet: true };
  }
  return { consumed: n, quiet: false };
}

export function tailRun(ms, still, frames) {
  let prev = null, tail = 0, n = 0;
  for (const { t, v } of frames) {
    tail = prev !== null && sameInts(prev, v) ? tail + 1 : 0;
    prev = v; n++;
    if (le(add(ms, TAIL_CAP_MS), t) || (le(ms, t) && still <= tail)) return { rows: n, quiet: lt(t, add(ms, TAIL_CAP_MS)) };
  }
  return { rows: n, quiet: false };
}

export const carouselCell = (width, base, cand) => carouselCellAt(rat(envFor(width).dpr), base, cand);

const roleRun = (raw, role, width) => raw.runs.find((r) => (r.role ?? (r.site === 'orig' ? 'orig' : 'cand')) === role && r.width === width);

export function cellsOfRaw(raw, nodes = MORPH_NODES) {
  const layout = raw.layout ?? layoutOf(nodes);
  const hasClip = layout.nav?.['clip-path'] !== undefined;
  const aa = raw.hash === raw.baseHash;
  const units = [];
  const widths = [...new Set(raw.runs.map((r) => r.width))].sort((a, b) => a - b);
  for (const width of widths) {
    const base = roleRun(raw, 'base', width), cand = roleRun(raw, 'cand', width);
    if (!base || !cand) continue;
    if (base.morph && cand.morph) {
      for (const phase of ['open', 'close']) {
        const c = morphCells({ width, base, cand, layout, phase });
        const navOk = hasClip || aa;
        units.push({ width, cell: 'nav-clip', part: phase, grade: navOk ? worst(c.nav) : null, reps: c.nav, note: navOk ? undefined : 'no clip-path reading in this artifact' });
        units.push({ width, cell: 'panel-effect', part: phase, grade: worst(c.panel), reps: c.panel, lag: c.lag });
      }
    }
    if (base.pain && cand.pain) units.push({ width, cell: 'pain-dark', part: 'scroll', grade: worst(painCell(base.pain, cand.pain)), reps: painCell(base.pain, cand.pain) });
    if (base.carousel && cand.carousel) {
      const c = carouselCell(width, base.carousel, cand.carousel);
      units.push({ width, cell: 'carousel', part: 'swap', grade: c.grade, reps: c.grades, swaps: c.swaps, holds: [holdsOf(base.carousel), holdsOf(cand.carousel)], atRest: [restedBefore(base.carousel, 1), restedBefore(cand.carousel, 1)] });
    }
  }
  return units;
}

export function tally(engine, units) {
  const cells = [...new Set(units.map((u) => u.cell))];
  const lines = [];
  for (const cell of cells) {
    const us = units.filter((u) => u.cell === cell);
    const n = (g) => us.filter((u) => u.grade === g).length;
    const lags = us.flatMap((u) => u.lag ?? []).filter((l) => l !== null).map((l) => Number(ratOf(l).n) / Number(ratOf(l).d));
    const lag = lags.length === 0 ? '' : `, lag max ${Math.max(...lags).toFixed(3)} frames`;
    lines.push(`CELLS ${engine} ${cell}: units ${us.length}, E ${n('E')}, Q ${n('Q')}, L ${n('L')}, not comparable ${n(null)}${lag}`);
  }
  return lines;
}
