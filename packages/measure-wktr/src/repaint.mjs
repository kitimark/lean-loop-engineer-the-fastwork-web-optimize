import { classify, CLASSES, classKey, seenArea, wasteArea, rerasterArea, addDirty } from '../../measure-webkit/src/paintclip.mjs';

// Format: Source/WebCore/platform/graphics/GraphicsLayer.cpp:939-1112 and ca/GraphicsLayerCA.cpp:4759-4785 @862f17d.
export function parseLayers(text) {
  const view = [];
  const nodes = [];
  const stack = [];
  const N = '(-?[\\d.e+-]+)';
  const re4 = (head, sep, mid) => new RegExp('^\\(' + head + ' ' + N + sep + N + mid + N + ' x ' + N + '\\)$');
  const RECT = new RegExp('^\\(rect ' + N + ' ' + N + ' ' + N + ' ' + N + '\\)$');
  const VIS = re4('visible rect', ', ', ' ');
  const COV = re4('coverage rect', ', ', ' ');
  const TCOV = re4('tile cache coverage', ', ', ' ');
  const layerOf = () => { for (let i = stack.length - 1; i >= 0; i--) if (stack[i].node !== undefined) return stack[i].node; return -1; };
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line) continue;
    if (line === ')') { stack.pop(); continue; }
    if (line[0] !== '(') continue;
    let bal = 0;
    for (const ch of line) { if (ch === '(') bal++; else if (ch === ')') bal--; }
    let m;
    if (/^\(GraphicsLayer\b/.test(line)) {
      const parent = layerOf();
      nodes.push({ i: nodes.length, p: parent, d: parent < 0 ? 0 : nodes[parent].d + 1, pos: null, b: null, op: 1, cv: 1, clips: 0, tiled: 0, tr: 0, vis: null, cov: null, tcov: null, icov: null, scale: null, rep: [] });
      stack.push({ name: 'GraphicsLayer', node: nodes.length - 1 });
      continue;
    }
    if (bal > 0) { stack.push({ name: /^\(repaint rects/.test(line) ? 'repaint' : line.slice(1).split(/[ )]/)[0] }); continue; }
    const top = stack[stack.length - 1];
    const cur = layerOf();
    const n = cur >= 0 ? nodes[cur] : null;
    if ((m = RECT.exec(line))) {
      if (top && top.name === 'repaint') (n ?? { rep: view }).rep.push([+m[1], +m[2], +m[3], +m[4]]);
      continue;
    }
    if (!n) continue;
    if ((m = new RegExp('^\\(position ' + N + ' ' + N + '\\)$').exec(line))) n.pos = [+m[1], +m[2]];
    else if ((m = new RegExp('^\\(bounds ' + N + ' ' + N + '\\)$').exec(line))) n.b = [+m[1], +m[2]];
    else if ((m = new RegExp('^\\(opacity ' + N + '\\)$').exec(line))) n.op = +m[1];
    else if (/^\(contentsVisible 0\)$/.test(line)) n.cv = 0;
    else if (/^\(clips 1\)$/.test(line)) n.clips = 1;
    else if (/^\(usingTiledLayer 1\)$/.test(line)) n.tiled = 1;
    else if (/^\(transform /.test(line)) n.tr = 1;
    else if ((m = VIS.exec(line))) n.vis = [+m[1], +m[2], +m[3], +m[4]];
    else if ((m = COV.exec(line))) n.cov = [+m[1], +m[2], +m[3], +m[4]];
    else if ((m = TCOV.exec(line))) n.tcov = [+m[1], +m[2], +m[3], +m[4]];
    else if ((m = /^\(intersects coverage rect ([01])\)$/.exec(line))) n.icov = +m[1];
    else if ((m = new RegExp('^\\(contentsScale ' + N + '\\)$').exec(line))) n.scale = +m[1];
  }
  for (const n of nodes) n.h = (n.op === 0 || n.cv === 0 || (n.p >= 0 && nodes[n.p].h)) ? 1 : 0;
  return { view, nodes };
}

export function swipeSchedule(maxY, { rest = 10, tail = 30, dy = 10, moves = 78, gap = 2 } = {}) {
  const ys = [];
  for (let i = 0; i < rest; i++) ys.push(0);
  let y = 0;
  while (y < maxY) {
    for (let m = 0; m < moves && y < maxY; m++) { y = Math.min(maxY, y + dy); ys.push(y); }
    for (let g = 0; g < gap && y < maxY; g++) ys.push(y);
  }
  for (let i = 0; i < tail; i++) ys.push(maxY);
  return ys;
}

export const zoneOf = (vh, maxY, y) => (y < 2 * vh ? 'hero' : maxY - y < vh ? 'finish' : 'rest');

export const ZONES = Object.freeze(['hero', 'rest', 'finish']);

export const ARMS = Object.freeze({
  orig: Object.freeze({ tree: 'snapshot', search: '' }),
  rewrite: Object.freeze({ tree: 'built', search: '' }),
  v2: Object.freeze({ tree: 'built', search: '?preset=v2-proved' }),
});
export const PARTS = Object.freeze(['nav', 'hero', 'people', 'profile', 'feed', 'pain', 'commission', 'platform', 'other']);

const toRect = (a) => {
  const x = Math.floor(a[0]), y = Math.floor(a[1]);
  return { x, y, w: Math.max(0, Math.ceil(a[0] + a[2]) - x), h: Math.max(0, Math.ceil(a[1] + a[3]) - y) };
};

export function keepDirty(items) {
  let ds = [];
  const owner = new Map();
  for (const it of items) {
    owner.set(it.rect, it);
    const next = addDirty(ds, it.rect);
    if (ds.length && next[0] !== ds[0]) owner.set(next[0], owner.get(ds[0]));
    ds = next;
  }
  return ds.map((r) => ({ ...owner.get(r), rect: r }));
}

export function frameFacts(fr, meta) {
  const rects = [];
  let calls = 0;
  const vp = { x: 0, y: 0, w: meta.innerWidth, h: meta.innerHeight };
  const rootCov = fr.rootCov ? toRect([fr.rootCov[0], fr.rootCov[1] - fr.sy, fr.rootCov[2], fr.rootCov[3]]) : vp;
  const el = (i) => (i != null && i >= 0 ? meta.els[i] : null);
  calls += fr.view.length;
  for (const v of keepDirty(fr.view.map((x) => ({ rect: toRect(x.r), v: x })))) {
    const e = el(v.v.e);
    const fact = { rect: v.rect, visible: vp, coverage: rootCov, hidden: !!v.v.h, covered: false, clipped: !!v.v.cl, pix: 'unknown' };
    rects.push({ part: v.v.p ?? e?.p ?? 'other', cause: v.v.c ?? null, el: e?.d ?? null, cls: classify(fact), area: v.rect.w * v.rect.h, seen: seenArea(fact), waste: wasteArea(fact), src: 'view' });
  }
  for (const L of fr.L) {
    const e = el(L.e);
    const vis = L.v ? toRect(L.v) : { x: 0, y: 0, w: L.b?.[0] ?? 0, h: L.b?.[1] ?? 0 };
    const cov = L.c ? toRect(L.c) : vis;
    calls += L.r.length;
    for (const { rect } of keepDirty(L.r.map((r) => ({ rect: toRect(r) })))) {
      const fact = { rect, visible: vis, coverage: cov, hidden: !!L.h, covered: false, clipped: !!L.cl, pix: 'unknown' };
      rects.push({ part: e?.p ?? 'other', cause: L.k ?? null, el: e?.d ?? null, cls: classify(fact), area: rect.w * rect.h, seen: seenArea(fact), waste: wasteArea(fact), src: 'layer' });
    }
  }
  const resizes = (fr.rs ?? []).map(([i, ow, oh, nw, nh, tiled, e]) => {
    const o = [Math.round(ow), Math.round(oh)], n = [Math.round(nw), Math.round(nh)];
    return { i, el: el(e)?.d ?? null, part: el(e)?.p ?? 'other', old: o, new: n, tiled: !!tiled, area: rerasterArea(!!tiled, o, n) };
  });
  return { rects, calls, resizes };
}

export function frameCounts(facts) {
  const c = { paintRects: facts.rects.length, trackedCalls: facts.calls ?? facts.rects.length, paintArea: 0, wasteArea: 0, resizedLayers: 0, reRasterArea: 0 };
  for (const k of CLASSES) c[`rects_${classKey(k)}`] = 0;
  for (const r of facts.rects) { c.paintArea += r.area; c.wasteArea += r.waste; c[`rects_${classKey(r.cls)}`]++; }
  for (const z of facts.resizes) { if (z.area > 0) c.resizedLayers++; c.reRasterArea += z.area; }
  return c;
}

const bump = (o, k, n = 1) => { o[k] = (o[k] ?? 0) + n; };

export function reduceRun(run) {
  const { meta } = run;
  const byZone = Object.fromEntries(ZONES.map((z) => [z, []]));
  const table = {};
  const cell = (zone, part) => (table[`${zone}|${part}`] ??= {
    zone, part, rects: 0, area: 0, waste: 0, byClass: Object.fromEntries(CLASSES.map((k) => [k, { n: 0, area: 0, waste: 0 }])),
    causes: {}, els: {}, reRaster: { layers: 0, area: 0 },
  });
  const frames = Object.fromEntries(ZONES.map((z) => [z, 0]));
  const calls = Object.fromEntries(ZONES.map((z) => [z, 0]));
  for (const fr of run.frames) {
    const zone = zoneOf(meta.innerHeight, meta.maxY, fr.y);
    const facts = frameFacts(fr, meta);
    byZone[zone].push({ n: byZone[zone].length, phase: 'scroll', scrollY: fr.y, counts: frameCounts(facts) });
    frames[zone]++;
    calls[zone] += facts.calls;
    for (const r of facts.rects) {
      const c = cell(zone, r.part);
      c.rects++; c.area += r.area; c.waste += r.waste;
      const k = c.byClass[r.cls];
      k.n++; k.area += r.area; k.waste += r.waste;
      if (r.cls !== 'visible') { bump(c.causes, r.cause ?? 'none'); bump(c.els, r.el ?? '-'); }
    }
    for (const z of facts.resizes) {
      if (z.area === 0) continue;
      const c = cell(zone, z.part);
      c.reRaster.layers++; c.reRaster.area += z.area;
      bump(c.els, `${z.el ?? '-'} ${z.old.join('x')}->${z.new.join('x')}`);
    }
  }
  return { byZone, frames, calls, table: Object.values(table) };
}

export function parseRepaint(text) {
  const got = { meta: null, probe: null, els: [], frames: [], error: null, done: false, params: null };
  for (const line of text.split('\n')) {
    const m = /^(?:CONSOLE MESSAGE:\s*)?(?:line \d+: )?FWWKTR (\w+) (.*)$/.exec(line.trim());
    if (!m) continue;
    const v = JSON.parse(m[2]);
    if (m[1] === 'rp') got.frames.push(v);
    else if (m[1] === 'meta') got.meta = v;
    else if (m[1] === 'probe') got.probe = v;
    else if (m[1] === 'els') got.els = v;
    else if (m[1] === 'params') got.params = v;
    else if (m[1] === 'error') got.error = v;
    else if (m[1] === 'done') got.done = true;
  }
  return got;
}

export function buildRepaintRun(parsed) {
  if (parsed.error) throw new Error(`page reported an error: ${JSON.stringify(parsed.error)}`);
  if (!parsed.done || !parsed.meta) throw new Error('incomplete page output (no done/meta line)');
  parsed.frames.forEach((f, i) => { if (f.f !== i) throw new Error(`frame ${i} has f=${f.f}`); });
  if (parsed.frames.length !== parsed.meta.frames) throw new Error(`${parsed.frames.length} frames, expected ${parsed.meta.frames}`);
  return { meta: { ...parsed.meta, els: parsed.els, probe: parsed.probe }, frames: parsed.frames };
}

export function sumTables(tables) {
  const out = {};
  for (const t of tables) for (const c of t) {
    const o = (out[`${c.zone}|${c.part}`] ??= { zone: c.zone, part: c.part, rects: 0, area: 0, waste: 0, byClass: Object.fromEntries(CLASSES.map((k) => [k, { n: 0, area: 0, waste: 0 }])), causes: {}, els: {}, reRaster: { layers: 0, area: 0 } });
    o.rects += c.rects; o.area += c.area; o.waste += c.waste;
    for (const k of CLASSES) for (const f of ['n', 'area', 'waste']) o.byClass[k][f] += c.byClass[k][f];
    for (const [k, n] of Object.entries(c.causes)) bump(o.causes, k, n);
    for (const [k, n] of Object.entries(c.els)) bump(o.els, k, n);
    o.reRaster.layers += c.reRaster.layers; o.reRaster.area += c.reRaster.area;
  }
  return Object.values(out);
}
