// The page script of the invisible-paint lane (served as /__fw/harness.js, loaded first in <head>), run inside
// WebKitTestRunner where `window.internals` exists (Tools/WebKitTestRunner/InjectedBundle/InjectedBundlePage.cpp:667@862f17d).
//
// Per frame, in a native requestAnimationFrame callback (nothing is replaced or seeked):
//   1. take the DOM events since the last callback (MutationObserver records, running animations and transitions),
//   2. dump `internals.layerTreeAsText(document, VISIBLE_RECTS | TILE_CACHES | REPAINT_RECTS | CLIPPING)`: the repaint rects of
//      the PREVIOUS frame (Internals.cpp:3608; the view's rects come first, LocalFrameView.cpp:6441, then each layer's, GraphicsLayer.cpp:1065),
//      with each layer's own visible and coverage rect (GraphicsLayerCA.cpp:4759-4785),
//   3. stopTrackingRepaints + startTrackingRepaints (LocalFrameView.cpp:6411-6439 clears the rects; start forces a layout),
//   4. scrollTo(y of this frame) (the swipe-touch-v1 offsets, repaint.mjs swipeSchedule).
// All of that is outside any timed count window; this lane counts repaint rects, never time.
//
// Layer identity: the layer text has no names, so before the run every element that has a composited layer
// (`internals.layerIDForElement`) is probed once: a transparent outline is set on it and the layer that gets a repaint rect is
// that element's layer (key = depth, bounds and occurrence). Layers without a probed element take their nearest probed ancestor's.
//
// Output (console lines `FWWKTR <tag> <json>`): meta, probe, rp (one per frame), els, done.
//   rp: { f, y, sy, view: [{ r:[x,y,w,h], e, h, c, p }], rootCov:[x,y,w,h], L: [{ i, r:[[x,y,w,h]], v, c, b, h, t, e, k }], rs: [[i,ow,oh,nw,nh,tiled,e]] }
import { bootstrapSource } from '../../measure-webkit/src/page.mjs';
import { parseLayers, swipeSchedule } from './repaint.mjs';

const LANDMARKS = [
  ['nav', 'header[aria-label="Primary navigation"]'], ['hero', 'section[aria-labelledby="start-selling-heading"]'],
  ['people', '#people'], ['profile', '#profile-showcase'], ['feed', 'section[aria-label="Profile feed"]'],
  ['pain', 'section[aria-labelledby="pain-heading"]'], ['commission', 'section[aria-labelledby="commission-heading"]'],
  ['platform', '#platform'],
];

const RUN_SRC = `(() => {
  const P = __PARAMS__;
  const LANDMARKS = __LANDMARKS__;
  const swipeSchedule = __SCHEDULE__;
  const parseLayers = __PARSE__;
  const out = (tag, obj) => console.log('FWWKTR ' + tag + ' ' + JSON.stringify(obj));
  if (!window.testRunner || !window.internals) { out('error', { message: 'no testRunner/internals in this page' }); return; }
  testRunner.dumpAsText();
  testRunner.waitUntilDone();
  const I = window.internals;
  const nST = window.__fwN.st;
  const sleep = (ms) => new Promise((r) => nST(r, ms));
  const raf = (fn) => new Promise((res) => requestAnimationFrame(() => res(fn())));
  const FL = (I.LAYER_TREE_INCLUDES_VISIBLE_RECTS ?? 1) | (I.LAYER_TREE_INCLUDES_TILE_CACHES ?? 2) | (I.LAYER_TREE_INCLUDES_REPAINT_RECTS ?? 4) | (I.LAYER_TREE_INCLUDES_CLIPPING ?? 64);
  const FL_NOREP = FL & ~(I.LAYER_TREE_INCLUDES_REPAINT_RECTS ?? 4);

  // ---- element table: descriptor and landmark part, indexed
  const els = [], elRef = [], elIdx = new Map();
  const desc = (el) => {
    let s = el.localName;
    if (el.id) s += '#' + el.id;
    const cl = [...el.classList].filter((c) => !/^svelte-/.test(c)).slice(0, 3);
    if (cl.length) s += '.' + cl.join('.');
    return s.slice(0, 70);
  };
  const partOf = (el) => { for (const [k, sel] of LANDMARKS) if (el.closest(sel)) return k; return 'other'; };
  const idx = (el, withParent) => {
    if (!el || el.nodeType !== 1) return -1;
    let i = elIdx.get(el);
    if (i === undefined) { i = els.length; els.push({ d: withParent && el.parentElement ? desc(el.parentElement) + ' > ' + desc(el) : desc(el), p: partOf(el) }); elRef.push(el); elIdx.set(el, i); }
    return i;
  };
  const near = (a, b) => a === b || a.contains(b) || b.contains(a);

  // ---- layer keys and the element of each layer
  const keyed = (nodes) => {
    const seen = new Map();
    return nodes.map((n) => { const base = n.d + ':' + (n.b ? n.b[0] + 'x' + n.b[1] : '-'); const o = seen.get(base) ?? 0; seen.set(base, o + 1); return base + '#' + o; });
  };
  const keyEl = new Map();
  // a layer the probe did not name takes the one composited element of its size (bounds in px), when exactly one has that size
  const sizeCand = new Map();
  // still unnamed: the elements of the page with that size (a layer is mostly its element's box) form a guessed group; the layer
  // takes the first of them, its entry says "1 of N same size", and the guess never sets hidden or clipped flags
  const sizeAll = new Map();
  const guessIdx = new Map();
  const guessList = new Map();
  const guessOf = (key) => {
    const l = sizeAll.get(key);
    if (!l || !l.length) return -1;
    let g = guessIdx.get(key);
    if (g === undefined) {
      g = els.length;
      els.push({ d: desc(l[0]) + (l.length > 1 ? ' (1 of ' + l.length + ' same size)' : ' (size match)'), p: partOf(l[0]), g: 1 });
      elRef.push(l[0]);
      guessIdx.set(key, g);
      guessList.set(g, l.slice(0, 60));
    }
    return g;
  };
  const elOfNodes = (nodes, keys) => {
    const r = new Array(nodes.length);
    for (const n of nodes) {
      let e = keyEl.get(keys[n.i]);
      const sk = n.b ? Math.round(n.b[0]) + 'x' + Math.round(n.b[1]) : null;
      if (e === undefined && sk) { const l = sizeCand.get(sk); if (l && l.length === 1) e = idx(l[0]); }
      if (e === undefined && n.p >= 0 && r[n.p] >= 0) e = r[n.p];
      if (e === undefined && sk) { const g = guessOf(sk); if (g >= 0) e = g; }
      r[n.i] = e !== undefined ? e : -1;
    }
    return r;
  };

  const hidMemo = new Map();
  const hiddenOwn = (el) => { let h = hidMemo.get(el); if (h === undefined) { const cs = getComputedStyle(el); h = (cs.opacity === '0' || cs.visibility === 'hidden' || cs.display === 'none') ? 1 : 0; hidMemo.set(el, h); } return h; };
  const hiddenDom = (el) => { for (let e = el; e; e = e.parentElement) if (hiddenOwn(e)) return 1; return 0; };
  // clipped away by its own style: the classic visually-hidden text (clip: rect(0 0 0 0) or clip-path: inset(50%))
  const clipOwn = (el) => { const cs = getComputedStyle(el); return (cs.clip.replace(/ |px|,/g, '') === 'rect(0000)' || cs.clipPath.startsWith('inset(50%')) ? 1 : 0; };
  const clippedDom = (el) => { for (let e = el; e; e = e.parentElement) if (clipOwn(e)) return 1; return 0; };

  // ---- DOM events since the last callback
  const muts = [];
  const mo = new MutationObserver(() => {});
  const startMo = () => mo.observe(document, { subtree: true, attributes: true, childList: true, characterData: true });
  const events = () => {
    const ev = [];
    for (const r of mo.takeRecords()) {
      const t = r.target.nodeType === 1 ? r.target : r.target.parentElement;
      if (!t) continue;
      ev.push({ el: t, tok: r.type === 'attributes' ? 'attr:' + r.attributeName : r.type });
    }
    try {
      for (const a of document.getAnimations()) {
        const t = a.effect && a.effect.target;
        if (!t || a.playState !== 'running') continue;
        const tok = a.animationName ? 'anim:' + a.animationName : a.transitionProperty ? 'trans:' + a.transitionProperty : 'js-anim';
        ev.push({ el: t, tok });
      }
    } catch (e) { /* no getAnimations */ }
    return ev;
  };
  const causeFor = (el, ev) => {
    const toks = new Set();
    const some = Array.isArray(el) ? el : [el];
    for (const e of ev) if (some.some((x) => near(x, e.el))) toks.add(e.tok);
    return toks.size ? [...toks].slice(0, 4).join(' ') : 'scroll';
  };

  // ---- landmark document ranges, for rects with no element
  let ranges = [];
  const measureRanges = () => {
    ranges = [];
    for (const [k, sel] of LANDMARKS) { const el = document.querySelector(sel); if (el) { const b = el.getBoundingClientRect(); ranges.push([k, b.top + scrollY, b.bottom + scrollY]); } }
  };
  const partAtDoc = (y) => { for (const [k, a, b] of ranges) if (y >= a && y < b) return k; return 'other'; };
  // elements of at most 2 px each way (visually hidden text): a 1x1 repaint rect is matched to one of them by document position
  let tiny = [];
  const measureTiny = () => {
    tiny = [];
    for (const el of document.querySelectorAll('body *')) {
      const b = el.getBoundingClientRect();
      if (b.width <= 2 && b.height <= 2 && tiny.length < 400) tiny.push([el, b.left + scrollX, b.top + scrollY]);
    }
  };
  const tinyAt = (x, y) => { for (const [el, tx, ty] of tiny) if (Math.abs(tx - x) <= 1.5 && Math.abs(ty - y) <= 1.5) return el; return null; };

  const run = async () => {
    await sleep(P.settleMs);
    const docH = document.documentElement.scrollHeight;
    const maxY = Math.max(0, docH - innerHeight);
    measureRanges();
    measureTiny();
    for (const el of document.querySelectorAll('body *')) {
      const b = el.getBoundingClientRect();
      if (b.width < 1 || b.height < 1) continue;
      const k = Math.round(b.width) + 'x' + Math.round(b.height);
      const l = sizeAll.get(k);
      if (!l) sizeAll.set(k, [el]); else l.push(el);
    }
    // ---- probe: which layer is which element
    const cands = [];
    for (const el of document.querySelectorAll('body, body *')) {
      if (cands.length >= P.maxProbe) break;
      try { I.layerIDForElement(el); cands.push(el); } catch (e) { /* not composited */ }
    }
    for (const el of cands) { const b = el.getBoundingClientRect(); const k = Math.round(b.width) + 'x' + Math.round(b.height); const l = sizeCand.get(k); if (l) l.push(el); else sizeCand.set(k, [el]); }
    let probed = 0, ambiguous = 0, unseen = 0;
    const t0 = performance.now();
    for (const el of cands) {
      const prev = el.style.outline;
      I.stopTrackingRepaints(); I.startTrackingRepaints();
      el.style.outline = '1px solid rgba(1, 2, 3, 0.02)';
      const t = parseLayers(I.layerTreeAsText(document, FL));
      el.style.outline = prev;
      const hit = t.nodes.filter((n) => n.rep.length);
      if (!hit.length) { unseen++; continue; }
      const keys = keyed(t.nodes);
      const deepest = hit.reduce((a, b) => (b.d > a.d ? b : a));
      if (hit.filter((n) => n.d === deepest.d).length > 1) ambiguous++;
      const k = keys[deepest.i];
      if (!keyEl.has(k)) { keyEl.set(k, idx(el)); probed++; }
    }
    I.stopTrackingRepaints(); I.startTrackingRepaints();
    await raf(() => 0); await raf(() => 0);
    out('probe', { candidates: cands.length, probed, ambiguous, unseen, ms: Math.round(performance.now() - t0), layers: parseLayers(I.layerTreeAsText(document, FL_NOREP)).nodes.length });

    out('sample', { text: I.layerTreeAsText(document, FL_NOREP).slice(0, 6000) });
    let recordErrors = 0;
    const ys = P.maxFrames ? swipeSchedule(maxY).slice(0, P.maxFrames) : swipeSchedule(maxY);
    startMo();
    let prevShape = null, prevB = null, prevEl = null;
    const frames = [];
    const record = (f, y) => {
      const ev = events();
      hidMemo.clear();
      const sy = Math.round(scrollY);
      const t = parseLayers(I.layerTreeAsText(document, FL));
      const keys = keyed(t.nodes);
      const nodeEl = elOfNodes(t.nodes, keys);
      const fr = { f, y, sy, view: [], L: [], rs: [] };
      const root = t.nodes[0];
      if (root) fr.rootCov = root.tcov || root.cov;
      for (const r of t.view) {
        const vy = r[1];
        let el = null, cause = null;
        for (const e of ev) { const b = e.el.getBoundingClientRect(); if (b.right > r[0] && b.left < r[0] + r[2] && b.bottom > r[1] && b.top < r[1] + r[3]) { el = e.el; cause = causeFor(e.el, ev); break; } }
        if (!el && r[2] > 0 && r[3] > 0) {
          const cx = r[0] + r[2] / 2, cy = r[1] + r[3] / 2;
          if (cx >= 0 && cy >= 0 && cx < innerWidth && cy < innerHeight) { el = document.elementFromPoint(cx, cy); if (el) cause = causeFor(el, ev); }
        }
        if (!el && r[2] <= 2 && r[3] <= 2) { const t = tinyAt(r[0] + scrollX, r[1] + sy); if (t) { el = t; cause = causeFor(t, ev); } }
        const e = el ? idx(el, r[2] <= 2 && r[3] <= 2) : -1;
        fr.view.push({ r, e, h: el ? hiddenDom(el) : 0, cl: el ? clippedDom(el) : 0, c: cause ?? 'scroll', p: el ? els[e].p : partAtDoc(vy + sy) });
      }
      for (const n of t.nodes) {
        if (!n.rep.length) continue;
        const ei = nodeEl[n.i];
        const el = ei >= 0 ? elRef[ei] : null;
        const gl = ei >= 0 && els[ei].g ? guessList.get(ei) : null;
        fr.L.push({ i: n.i, r: n.rep, v: n.vis, c: n.tcov || n.cov, b: n.b, h: n.h || (el && !gl ? hiddenDom(el) : 0), cl: el && !gl ? clippedDom(el) : 0, t: n.tiled, e: ei, k: el ? causeFor(gl || el, ev) : 'scroll' });
      }
      const shape = t.nodes.map((n) => n.p).join(',');
      if (prevShape === shape) {
        for (const n of t.nodes) { const o = prevB[n.i], b = n.b; if (o && b && (o[0] !== b[0] || o[1] !== b[1])) fr.rs.push([n.i, o[0], o[1], b[0], b[1], n.tiled, prevEl[n.i]]); }
      }
      prevShape = shape; prevB = t.nodes.map((n) => n.b); prevEl = nodeEl;
      out('rp', fr);
      frames.push(f);
    };
    for (let k = 0; k <= ys.length; k++) {
      await raf(() => {
        if (k > 0) {
          try { record(k - 1, ys[k - 1]); } catch (e) {
            recordErrors++;
            out('rperr', { f: k - 1, message: String(e && e.message || e) });
            out('rp', { f: k - 1, y: ys[k - 1], sy: -1, view: [], L: [], rs: [], err: 1 });
            if (recordErrors > 3) throw e;
          }
        }
        I.stopTrackingRepaints(); I.startTrackingRepaints();
        if (k < ys.length) scrollTo({ top: ys[k], behavior: 'instant' });
      });
    }
    mo.disconnect();
    out('meta', {
      recordErrors, ua: navigator.userAgent, innerWidth, innerHeight, dpr: devicePixelRatio, docH, maxY, endY: Math.round(scrollY), frames: ys.length, ranges,
      fw: window.__fw ? { mode: window.__fw.mode ?? null, configHash: window.__fw.configHash ?? null } : null, bootstrap: window.__wkBootstrap || null,
      landmarks: LANDMARKS.map(([k, sel]) => [k, document.querySelectorAll(sel).length]),
    });
    out('els', els);
    out('params', P);
  };
  addEventListener('load', () => {
    run().catch((e) => out('error', { message: String(e && e.message || e), stack: String(e && e.stack || '') })).then(() => { out('done', {}); testRunner.notifyDone(); });
  });
})();`;

/** The page script: the same bootstrap as the other WKTR lane (pinned Date, seeded Math.random), then the swipe run. */
export function repaintHarnessSource({ settleMs = 6000, maxProbe = 800, maxFrames = 0 } = {}) {
  const pre = 'window.__fwN = { st: window.setTimeout.bind(window) };\n';
  return pre + bootstrapSource({ clock: 'pinned' }) + '\n' + RUN_SRC
    .replace('__PARAMS__', () => JSON.stringify({ settleMs, maxProbe, maxFrames }))
    .replace('__LANDMARKS__', () => JSON.stringify(LANDMARKS))
    .replace('__SCHEDULE__', () => swipeSchedule.toString())
    .replace('__PARSE__', () => parseLayers.toString());
}
