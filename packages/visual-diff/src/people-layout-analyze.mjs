// Analysis of the people-layout probe records (people-layout.mjs): original against port, per engine, width and repetition.
// TS stand-in: the 0.5 px rule and the grouping are measurement bookkeeping, not site decisions, and have no Lean golden.
//   static   subtree dumps (load, held stops, warm) matched node by node (tree walk, children paired by tag order);
//            a pair differs when its width or height differs, or its position inside its parent does, by more than TOL
//   origin   a differing pair none of whose differing neighbours explains it: a size that no child's size explains, an offset
//            that the previous sibling's size does not explain
//   frames   the tracked boxes at the same scroll position in both arms; per arm the frame-to-frame changes of boxes whose
//            document position is fixed by layout (not the sticky ones), the section's siblings and the document height
//   shifts   Chromium layout-shift entries per phase and source path, an arm against the other
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export const TOL = 0.5;
const STICKY_KEYS = new Set(['sticky', 'chrome', 'tabs', 'deck', 'shell', 'panel']);
const f2 = (n) => (n == null ? '-' : String(+n.toFixed(2)));
const sgn = (n) => (n > 0 ? '+' : '') + f2(n);

/** Tree of a dump: nodes by path, children lists in order. */
function treeOf(dump) {
  const by = new Map();
  for (const n of dump.nodes) by.set(n.p, { ...n, kids: [] });
  for (const n of by.values()) {
    const i = n.p.lastIndexOf('.');
    if (i > 0) by.get(n.p.slice(0, i))?.kids.push(n);
  }
  return by.get('0');
}

/**
 * Pairs the children of two nodes: first the longest common subsequence of (tag, class key), then, between two such pairs, the
 * leftovers with the same tag in order (a node the port draws with another class or element still gets compared).
 */
function lcsPairs(a, b) {
  const same = (x, y) => x.g === y.g && ckey(x.c) === ckey(y.c);
  const n = a.length, m = b.length;
  const t = Array.from({ length: n + 1 }, () => new Int32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) t[i][j] = same(a[i], b[j]) ? t[i + 1][j + 1] + 1 : Math.max(t[i + 1][j], t[i][j + 1]);
  const anchors = [];
  let i = 0, j = 0;
  while (i < n && j < m) {
    if (same(a[i], b[j])) { anchors.push([i, j]); i++; j++; }
    else if (t[i + 1][j] >= t[i][j + 1]) i++;
    else j++;
  }
  anchors.push([n, m]);
  const pairs = [], onlyA = [], onlyB = [];
  let pi = 0, pj = 0;
  for (const [ai, bj] of anchors) {
    const ga = a.slice(pi, ai), gb = b.slice(pj, bj);
    const used = new Set();
    for (const x of ga) {
      const k = gb.findIndex((y, idx) => !used.has(idx) && y.g === x.g);
      if (k >= 0) { used.add(k); pairs.push([x, gb[k]]); } else onlyA.push(x);
    }
    gb.forEach((y, idx) => { if (!used.has(idx)) onlyB.push(y); });
    if (ai < n) pairs.push([a[ai], b[bj]]);
    pi = ai + 1;
    pj = bj + 1;
  }
  return { pairs, onlyA, onlyB };
}

const PREFIXES = ['start-selling-future-people-o-', 'start-selling-future-', 'start-selling-profile-', 'start-selling-'];
/** The first class with the original's prefixes or the port's module prefix and hash removed. */
const klass = (c) => {
  let k = (c || '').split(/\s+/)[0] || '';
  for (const p of PREFIXES) if (k.startsWith(p)) { k = k.slice(p.length); break; }
  return k.replace(/^[a-z]+-module_/, '').replace(/_[A-Za-z0-9_-]{6}$/, '');
};
/** Matching key of a class: lower case without dashes, so the original's `tab-label` meets the port's `tabLabel`. */
const ckey = (c) => klass(c).toLowerCase().replace(/-/g, '');
const label = (n) => `${n.g}.${klass(n.c)}`;

/** Compares two dumps. Returns { pairs: [...], onlyA, onlyB, secDy } */
export function compareDumps(da, db) {
  const ta = treeOf(da), tb = treeOf(db);
  const out = [];
  const onlyA = [], onlyB = [];
  const ox = ta.b[0] - tb.b[0];
  const oy = ta.b[1] - tb.b[1];
  const walk = (a, b, pa, pb, prev, pd) => {
    const rel = (n, p) => [n.b[0] - p.b[0], n.b[1] - p.b[1]];
    const ra = pa ? rel(a, pa) : [0, 0];
    const rb = pb ? rel(b, pb) : [0, 0];
    const d = { a, b, dw: a.b[2] - b.b[2], dh: a.b[3] - b.b[3], dx: ra[0] - rb[0], dy: ra[1] - rb[1] };
    d.diff = Math.abs(d.dw) > TOL || Math.abs(d.dh) > TOL || Math.abs(d.dx) > TOL || Math.abs(d.dy) > TOL;
    d.prev = prev;
    d.pd = pd || null;
    d.tfAnc = !!pd && ((pd.a.tf || '') !== (pd.b.tf || '') || pd.tfAnc);
    out.push(d);
    const { pairs, onlyA: oa, onlyB: ob } = lcsPairs(a.kids, b.kids);
    for (const x of oa) onlyA.push(x);
    for (const x of ob) onlyB.push(x);
    d.xa = oa;
    d.xb = ob;
    let pv = null;
    d.kids = [];
    for (const [ka, kb] of pairs) { const kd = walk(ka, kb, a, b, pv, d); d.kids.push(kd); pv = kd; }
    return d;
  };
  const root = walk(ta, tb, null, null, null);
  for (const d of out) {
    d.kidDiffH = d.kids.some((k) => Math.abs(k.dh) > TOL);
    d.kidDiffW = d.kids.some((k) => Math.abs(k.dw) > TOL);
  }
  // origin: a size no child's size accounts for; an offset the previous sibling's size does not account for
  for (const d of out) {
    d.why = [];
    if (Math.abs(d.dh) > TOL && !d.kidDiffH) d.why.push('height');
    if (Math.abs(d.dw) > TOL && !d.kidDiffW && (!d.a.kids.length || true)) d.why.push('width');
    if (Math.abs(d.dy) > TOL && !(d.prev && (Math.abs(d.prev.dh) > TOL || Math.abs(d.prev.dy) > TOL))) d.why.push('offset-y');
    if (Math.abs(d.dx) > TOL && !(d.prev && (Math.abs(d.prev.dw) > TOL || Math.abs(d.prev.dx) > TOL))) d.why.push('offset-x');
  }
  return { root, pairs: out, onlyA, onlyB, secDx: ox, secDy: oy };
}

const SKEYS = ['d', 'ps', 't', 'w', 'h', 'mg', 'pd', 'gap', 'ff', 'fs', 'lh', 'fw', 'ls', 'ar', 'of', 'tf', 'ov', 'bs', 'cv'];
const styleDiff = (a, b) => (a.s && b.s ? SKEYS.filter((k) => a.s[k] !== b.s[k] && !['w', 'h', 't'].includes(k)).map((k) => `${k}:${a.s[k]}|${b.s[k]}`) : []);

/** Cause hint of a differing pair, from facts in the records only. */
export function causeOf(d) {
  const a = d.a, b = d.b;
  const sd = styleDiff(a, b);
  if ((a.tf || '') !== (b.tf || '')) return { cause: 'transform differs (scroll-driven motion)', detail: `${a.tf || 'none'} | ${b.tf || 'none'}`.slice(0, 120) };
  if (d.tfAnc) return { cause: 'transform of an ancestor differs (scroll-driven motion)', detail: '' };
  // a child with no partner in the other arm: it may be a flex or grid item of its own (gap, order), whatever it paints
  const un = (n) => (n || []).map((x) => label(x)).join(',');
  if ((d.xa && d.xa.length) || (d.xb && d.xb.length)) return { cause: 'structure: unmatched child', detail: `orig only [${un(d.xa)}] port only [${un(d.xb)}]` };
  if (d.pd && ((d.pd.xa && d.pd.xa.length) || (d.pd.xb && d.pd.xb.length))) return { cause: 'structure: parent has an unmatched child', detail: `orig only [${un(d.pd.xa)}] port only [${un(d.pd.xb)}]` };
  const font = sd.filter((x) => /^(ff|fs|lh|fw|ls):/.test(x));
  if (font.length) return { cause: 'restated CSS value (font)', detail: font.join(' ') };
  if (a.img || b.img) {
    const ia = a.img, ib = b.img;
    if (ia && ib && (ia.nw !== ib.nw || ia.nh !== ib.nh)) return { cause: 'image intrinsic size', detail: `${ia.nw}x${ia.nh} | ${ib.nw}x${ib.nh}` };
    if (ia && ib && ia.done !== ib.done) return { cause: 'image not complete', detail: `${ia.done}|${ib.done}` };
    if (ia && ib && (ia.wa !== ib.wa || ia.ha !== ib.ha)) return { cause: 'image width/height attributes', detail: `${ia.wa}x${ia.ha} | ${ib.wa}x${ib.ha}` };
  }
  if (sd.length) return { cause: 'restated CSS value', detail: sd.join(' ') };
  if (a.tx && b.tx && (a.tx.lines !== b.tx.lines || Math.abs(a.tx.w - b.tx.w) > TOL)) return { cause: 'text metrics (font)', detail: `lines ${a.tx.lines}|${b.tx.lines} w ${f2(a.tx.w)}|${f2(b.tx.w)}` };
  return { cause: 'unknown', detail: '' };
}

function dumpPairs(c, key) {
  const out = [];
  const la = c.orig[key], lb = c.rewrite[key];
  if (!la || !lb) return out;
  if (Array.isArray(la)) la.forEach((d, i) => { if (lb[i]) out.push({ id: `${key}[${i}]@y${d.want}`, a: d, b: lb[i], want: d.want }); });
  else out.push({ id: key, a: la, b: lb, want: 0 });
  return out;
}

const STATIC_KEYS = ['load', 'coldHolds', 'warmLoad', 'warmHolds'];

/** Frame-to-frame changes of a box series (layout-driven boxes only: y and h, x and w). */
function shiftsOf(frames, keys, getBox) {
  const ev = [];
  for (const k of keys) {
    let prev = null;
    for (const fr of frames) {
      const b = getBox(fr, k);
      const tf = k.startsWith('sib') ? '' : fr.tf[k];
      if (prev && b && prev.b) {
        const d = [b[0] - prev.b[0], b[1] - prev.b[1], b[2] - prev.b[2], b[3] - prev.b[3]];
        if (d.some((x) => Math.abs(x) > TOL)) ev.push({ k, y: fr.want, d, moved: tf !== prev.tf });
      }
      if (b) prev = { b, tf };
    }
  }
  return ev;
}

/** Per case: the tables' data. */
export function analyzeCase(c, engine) {
  const res = { id: c.id, rep: c.rep, engine, errors: [] };
  for (const arm of ['orig', 'rewrite']) if (c[arm].error || c[arm].absent) res.errors.push(`${arm}: ${c[arm].error || 'section absent'}`);
  if (res.errors.length) return res;
  res.geo = { orig: { docH: c.orig.geo.docH, secTop: c.orig.geo.secTop, secH: c.orig.geo.secH }, rewrite: { docH: c.rewrite.geo.docH, secTop: c.rewrite.geo.secTop, secH: c.rewrite.geo.secH } };
  res.fonts = { orig: c.orig.geo.fonts, rewrite: c.rewrite.geo.fonts };
  res.static = [];
  for (const key of STATIC_KEYS) {
    for (const p of dumpPairs(c, key)) {
      const cmp = compareDumps(p.a, p.b);
      const diffs = cmp.pairs.filter((d) => d.diff);
      res.static.push({
        id: p.id, want: p.want, secDx: cmp.secDx, secDy: cmp.secDy, nodes: cmp.pairs.length, diff: diffs.length,
        onlyA: cmp.onlyA.map((n) => `${n.p} ${label(n)}`), onlyB: cmp.onlyB.map((n) => `${n.p} ${label(n)}`),
        sibs: p.a.sibs.map((s, i) => ({ g: label(s), a: s.b, b: p.b.sibs[i] ? p.b.sibs[i].b : null })),
        origins: diffs.filter((d) => d.why.length).map((d) => ({ p: d.a.p, pb: d.b.p, la: label(d.a), lb: label(d.b), why: d.why, dw: d.dw, dh: d.dh, dx: d.dx, dy: d.dy, ha: d.a.b[3], hb: d.b.b[3], ...causeOf(d), styleDiff: styleDiff(d.a, d.b) })),
        all: diffs.map((d) => ({ p: d.a.p, la: label(d.a), lb: label(d.b), dw: d.dw, dh: d.dh, dx: d.dx, dy: d.dy })),
      });
    }
  }
  // frames
  res.frames = {};
  for (const pass of ['coldFrames', 'warmFrames']) {
    const fa = c.orig[pass], fb = c.rewrite[pass];
    const keys = Object.keys(fa[0].k).filter((k) => fa[0].k[k] && fb[0].k[k]);
    const layoutKeys = keys.filter((k) => !STICKY_KEYS.has(k));
    const sibsN = Math.min(fa[0].sib.length, fb[0].sib.length);
    const sibKeys = Array.from({ length: sibsN }, (_, i) => `sib${i}`);
    const get = (fr, k) => (k.startsWith('sib') ? [0, fr.sib[+k.slice(3)][0], 0, fr.sib[+k.slice(3)][1]] : fr.k[k]);
    const out = { shiftsA: shiftsOf(fa, [...layoutKeys, ...sibKeys], get), shiftsB: shiftsOf(fb, [...layoutKeys, ...sibKeys], get), docH: [] };
    // same scroll position, box against box
    out.cmp = [];
    for (const k of [...keys, ...sibKeys]) {
      let first = null, n = 0, max = 0;
      const n2 = Math.min(fa.length, fb.length);
      for (let i = 0; i < n2; i++) {
        const x = get(fa[i], k), y = get(fb[i], k);
        if (!x || !y) continue;
        const d = [x[0] - y[0], x[1] - y[1], x[2] - y[2], x[3] - y[3]];
        const m = Math.max(...d.map(Math.abs));
        if (m > TOL) { n++; if (!first) first = { y: fa[i].want, d }; max = Math.max(max, m); }
      }
      out.cmp.push({ k, frames: n, of: Math.min(fa.length, fb.length), first, max });
    }
    let last = null;
    const n2 = Math.min(fa.length, fb.length);
    for (let i = 0; i < n2; i++) {
      const d = fa[i].dh - fb[i].dh;
      if (last === null || d !== last) { out.docH.push({ y: fa[i].want, a: fa[i].dh, b: fb[i].dh, d }); last = d; }
    }
    out.docHA = [...new Set(fa.map((f) => f.dh))];
    out.docHB = [...new Set(fb.map((f) => f.dh))];
    res.frames[pass] = out;
  }
  // layout shifts (Chromium)
  const lsOf = (arm) => {
    const e = arm.ls && arm.ls.supported ? arm.ls.entries : null;
    if (!e) return null;
    const by = {};
    for (const x of e) {
      for (const s of x.src.length ? x.src : [{ n: '(no source)' }]) {
        const path = (s.n || '').replace(/\s\..*$/, '').replace(/#[a-z-]+/g, '').split('>').slice(-5).join('>');
        const key = `${x.ph}|${path}`;
        by[key] ??= { ph: x.ph, path, n: 0, v: 0, ex: null };
        by[key].n++;
        by[key].v += x.v / Math.max(1, x.src.length);
        by[key].ex ??= { name: s.n, p: s.p, c: s.c, y: x.y, t: x.t };
      }
    }
    return { total: e.reduce((s, x) => s + x.v, 0), n: e.length, by };
  };
  res.ls = { orig: lsOf(c.orig), rewrite: lsOf(c.rewrite) };
  return res;
}

function loadAll(dirs) {
  const files = [];
  for (const d of dirs) for (const f of readdirSync(d)) if (f.endsWith('.people-layout.json')) files.push(join(d, f));
  return files.map((f) => JSON.parse(readFileSync(f, 'utf8')));
}

const row = (cells) => '| ' + cells.join(' | ') + ' |';
const head = (cells) => row(cells) + '\n' + row(cells.map(() => '---'));

/** The markdown report; `base` also gets BASE.json (the full analysis) and BASE.md. */
export function report(dirs, base) {
  const runs = loadAll(dirs);
  const lines = [];
  const all = [];
  for (const run of runs) {
    const engine = run.header.engine;
    lines.push(`# People layout probe: ${engine}`, '', `browser ${run.header.browser}; snapshot ${run.header.snapshot}; site build ${JSON.stringify(run.header.site.buildId).slice(0, 40)}; params ${JSON.stringify(run.header.params)}`, '');
    const results = run.cases.map((c) => analyzeCase(c, engine));
    all.push({ header: run.header, results });
    lines.push('## Section size per width and repetition', '', head(['width', 'rep', 'orig top', 'port top', 'orig h', 'port h', 'dh', 'orig docH', 'port docH', 'diff nodes (load)']));
    for (const r of results) {
      if (r.errors.length) { lines.push(row([r.id, r.rep, `ERROR ${r.errors.join('; ')}`, '', '', '', '', '', '', ''])); continue; }
      const ld = r.static.find((s) => s.id === 'load');
      lines.push(row([r.id, r.rep, f2(r.geo.orig.secTop), f2(r.geo.rewrite.secTop), f2(r.geo.orig.secH), f2(r.geo.rewrite.secH), sgn(r.geo.orig.secH - r.geo.rewrite.secH), r.geo.orig.docH, r.geo.rewrite.docH, `${ld.diff}/${ld.nodes}`]));
    }
    lines.push('');
    lines.push('## Static differences: origins per width (load, rep 0), orig minus port', '');
    for (const r of results.filter((x) => !x.errors.length && x.rep === 0)) {
      const ld = r.static.find((s) => s.id === 'load');
      lines.push(`### ${r.id}  (section top difference ${sgn(ld.secDy)}, only in orig: ${ld.onlyA.length}, only in port: ${ld.onlyB.length})`, '');
      if (ld.onlyA.length || ld.onlyB.length) lines.push(`only orig: ${ld.onlyA.slice(0, 12).join('; ')}`, `only port: ${ld.onlyB.slice(0, 12).join('; ')}`, '');
      lines.push(head(['path', 'orig', 'port', 'why', 'dw', 'dh', 'dx', 'dy', 'cause', 'detail']));
      for (const o of ld.origins.slice(0, 40)) lines.push(row([o.p, o.la, o.lb, o.why.join('+'), sgn(o.dw), sgn(o.dh), sgn(o.dx), sgn(o.dy), o.cause, o.detail.slice(0, 90)]));
      lines.push('');
    }
    lines.push('## Frame comparison (cold pass, same scroll position), keys that differ', '');
    for (const r of results.filter((x) => !x.errors.length && x.rep === 0)) {
      lines.push(`### ${r.id}`, '', head(['key', 'frames differ', 'first at scrollY', 'first d (x y w h)', 'max']));
      for (const k of r.frames.coldFrames.cmp.filter((x) => x.frames > 0)) lines.push(row([k.k, `${k.frames}/${k.of}`, k.first.y, k.first.d.map(sgn).join(' '), f2(k.max)]));
      lines.push('', `docH orig ${r.frames.coldFrames.docHA.join(',')} port ${r.frames.coldFrames.docHB.join(',')}`, '');
      const sa = r.frames.coldFrames.shiftsA.filter((x) => !x.moved), sb = r.frames.coldFrames.shiftsB.filter((x) => !x.moved);
      lines.push(`frame-to-frame layout shifts with the transform unchanged (cold): orig ${sa.length}, port ${sb.length}`);
      for (const [nm, ss] of [['orig', sa], ['port', sb]]) for (const s of ss.slice(0, 12)) lines.push(`- ${nm} ${s.k} at scrollY ${s.y}: ${s.d.map(sgn).join(' ')}`);
      lines.push('');
    }
    if (engine === 'chromium') {
      lines.push('## Layout-shift entries (Chromium, whole run per arm, rep 0)', '', head(['width', 'arm', 'entries', 'sum', 'phase|source path (count, sum)']));
      for (const r of results.filter((x) => !x.errors.length && x.rep === 0)) {
        for (const arm of ['orig', 'rewrite']) {
          const l = r.ls[arm];
          if (!l) continue;
          const top = Object.values(l.by).sort((p, q) => q.v - p.v).slice(0, 6).map((b) => `${b.ph}|${b.path} (${b.n}, ${f2(b.v)})`).join('<br>');
          lines.push(row([r.id, arm, l.n, f2(l.total), top]));
        }
      }
      lines.push('');
    }
  }
  const md = lines.join('\n') + '\n';
  if (base) {
    writeFileSync(base + '.md', md);
    writeFileSync(base + '.json', JSON.stringify(all) + '\n');
  }
  return md;
}
