// In-page readers of the image audit. Each function is serialized by Playwright (`evaluate`), so it holds no closure over
// module scope. They read layout and computed style only (no screenshot, no animation seeking, native requestAnimationFrame).
//
// What is recorded for one image-bearing thing at one scroll stop:
//   kind   'img' (an <img>) | 'bg' (a CSS image: background-image, mask-image, border-image-source, list-style-image, content)
//   url    the resolved file (path + query only; the origin is the audit's own server)
//   nat    [w, h] the decoded file's pixel size (naturalWidth/Height; a bg image is loaded through an Image())
//   box    [w, h] the CSS size the image is drawn into (an <img>: its content box; a bg: the background positioning area)
//   img    [w, h] the CSS size the whole picture is drawn at inside that box (object-fit / background-size resolved)
//   vis    visual scale of the element's own transform chain (getBoundingClientRect / layout size), 1 when none
//   rw, rh  (an <img> only) the size of its getBoundingClientRect, unrounded: the rectangle the engine snaps to device pixels
//   effects  effects of the element and its ancestors that matter to paint: filter, backdrop-filter, opacity < 1,
//            opacity / transform / filter animations, will-change, static transform, mask, mix-blend-mode
//
// Region membership is the audit's reducer's job (reduce.mjs); here every record carries `fw`, the data-fw ancestors, and `cls`,
// the class names of the ancestors (the original snapshot has no data-fw), so one reducer reads both arms.

/** Split a CSS list at top-level commas (commas inside parentheses stay). Pure; tested in node. */
export function splitTop(s) {
  const out = [];
  let depth = 0;
  let cur = '';
  for (const ch of s) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ',' && depth === 0) { out.push(cur.trim()); cur = ''; } else cur += ch;
  }
  if (cur.trim() !== '') out.push(cur.trim());
  return out;
}

/** CSS px size of a picture of natural size [nw, nh] drawn by `background-size` token `tok` into box [bw, bh]. Pure; tested in node.
 * tok: 'auto' | 'cover' | 'contain' | '<L> [<L>|auto]', L = '<n>px' | '<n>%'. */
export function bgDrawn(tok, nw, nh, bw, bh) {
  const t = tok.trim();
  if (nw <= 0 || nh <= 0) return [bw, bh];
  if (t === 'cover' || t === 'contain') {
    const s = t === 'cover' ? Math.max(bw / nw, bh / nh) : Math.min(bw / nw, bh / nh);
    return [nw * s, nh * s];
  }
  const parts = t.split(/\s+/);
  const len = (p, ref) => (p === 'auto' ? null : p.endsWith('%') ? (parseFloat(p) / 100) * ref : parseFloat(p));
  let w = len(parts[0] ?? 'auto', bw);
  let h = len(parts[1] ?? 'auto', bh);
  if (w === null && h === null) return [nw, nh];
  if (w === null) w = (h * nw) / nh;
  if (h === null) h = (w * nh) / nw;
  return [w, h];
}

/** CSS px size of an <img>'s picture inside a content box by `object-fit`. Pure; tested in node. */
export function fitDrawn(fit, nw, nh, bw, bh) {
  if (nw <= 0 || nh <= 0) return [bw, bh];
  if (fit === 'cover') { const s = Math.max(bw / nw, bh / nh); return [nw * s, nh * s]; }
  if (fit === 'contain') { const s = Math.min(bw / nw, bh / nh); return [nw * s, nh * s]; }
  if (fit === 'none') return [nw, nh];
  if (fit === 'scale-down') { const s = Math.min(1, bw / nw, bh / nh); return [nw * s, nh * s]; }
  return [bw, bh];
}

/** The pure helpers above, as a script that defines window.__fwImgKit (give it to the engine as the init script). */
export const kitSource = () => `window.__fwImgKit = { splitTop: ${splitTop}, bgDrawn: ${bgDrawn}, fitDrawn: ${fitDrawn} };`;

/**
 * Read every <img> and every CSS image of the document at the current scroll position. Async only for the natural sizes of
 * CSS images (loaded once through an Image() and cached on window.__fwImgNat).
 * @returns {Promise<{scrollY:number, vw:number, vh:number, dpr:number, items:object[]}>}
 */
export async function collectImages() {
  const W = window;
  const ids = (W.__fwImgIds ??= { map: new WeakMap(), n: 0, pseudo: new Map() });
  const idOf = (el, pseudo) => {
    if (!pseudo) { if (!ids.map.has(el)) ids.map.set(el, ++ids.n); return `e${ids.map.get(el)}`; }
    if (!ids.map.has(el)) ids.map.set(el, ++ids.n);
    return `e${ids.map.get(el)}${pseudo}`;
  };
  const natCache = (W.__fwImgNat ??= new Map());
  const loadNat = (u) => {
    if (!natCache.has(u)) {
      natCache.set(u, new Promise((ok) => {
        const im = new Image();
        const t = setTimeout(() => ok([0, 0]), 6000);
        im.onload = () => { clearTimeout(t); ok([im.naturalWidth, im.naturalHeight]); };
        im.onerror = () => { clearTimeout(t); ok([0, 0]); };
        im.src = u;
      }));
    }
    return natCache.get(u);
  };
  const path = (u) => { try { const x = new URL(u, document.baseURI); return x.pathname + x.search; } catch { return u; } };
  const K = W.__fwImgKit;
  const split = K.splitTop;
  const label = (el) => {
    const fw = el.getAttribute?.('data-fw');
    if (fw) return fw;
    const c = typeof el.className === 'string' ? el.className.trim().split(/\s+/)[0] : '';
    return `${el.tagName.toLowerCase()}${c ? '.' + c.replace(/_[A-Za-z0-9_-]{6,}$/, '') : ''}`;
  };
  const NONE = (v) => v === 'none' || v === '' || v == null || v === 'auto' || v === 'normal';
  const ANIM_SKIP = new Set(['offset', 'easing', 'composite', 'computedOffset']);
  // The effects an element itself has, computed once per collect call (ancestors are shared by many images).
  const own = new Map();
  const ownOf = (el) => {
    if (own.has(el)) return own.get(el);
    const cs = getComputedStyle(el);
    const here = [];
    if (!NONE(cs.filter)) here.push(`filter=${cs.filter}`);
    const bf = cs.backdropFilter || cs.webkitBackdropFilter;
    if (!NONE(bf)) here.push(`backdrop-filter=${bf}`);
    if (parseFloat(cs.opacity) < 1) here.push(`opacity=${cs.opacity}`);
    if (!NONE(cs.transform)) here.push('transform');
    if (!NONE(cs.translate) || !NONE(cs.scale) || !NONE(cs.rotate)) here.push('individual-transform');
    if (!NONE(cs.willChange)) here.push(`will-change=${cs.willChange}`);
    if (!NONE(cs.mixBlendMode)) here.push(`mix-blend-mode=${cs.mixBlendMode}`);
    if (!NONE(cs.maskImage || cs.webkitMaskImage)) here.push('mask');
    if (!NONE(cs.clipPath)) here.push('clip-path');
    for (const a of el.getAnimations?.() ?? []) {
      if (a.effect?.target !== el) continue;
      const props = new Set();
      try { for (const kf of a.effect.getKeyframes()) for (const k of Object.keys(kf)) if (!ANIM_SKIP.has(k)) props.add(k); } catch { /* none */ }
      const kind = a.constructor?.name === 'CSSTransition' ? 'transition' : a.constructor?.name === 'CSSAnimation' ? 'animation' : 'waapi';
      here.push(`${kind}(${[...props].sort().join('+')}):${a.playState}`);
    }
    const v = { here, lab: label(el), fw: el.getAttribute?.('data-fw') || null, cls: typeof el.className === 'string' ? el.className : '' };
    own.set(el, v);
    return v;
  };
  const effectsOf = (start) => {
    const out = [];
    const fw = [];
    const cls = [];
    let depth = 0;
    for (let el = start; el && el.nodeType === 1; el = el.parentElement, depth++) {
      const v = ownOf(el);
      for (const h of v.here) out.push({ at: v.lab, up: depth, e: h });
      if (v.fw) fw.push(v.fw);
      if (v.cls) cls.push(v.cls);
    }
    return { effects: out, fw, cls };
  };

  const vw = W.innerWidth;
  const vh = W.innerHeight;
  const items = [];

  for (const im of document.getElementsByTagName('img')) {
    const cs = getComputedStyle(im);
    const r = im.getBoundingClientRect();
    const ow = im.offsetWidth;
    const oh = im.offsetHeight;
    const pad = (p) => parseFloat(cs[p]) || 0;
    const bw = Math.max(0, ow - pad('paddingLeft') - pad('paddingRight') - pad('borderLeftWidth') - pad('borderRightWidth'));
    const bh = Math.max(0, oh - pad('paddingTop') - pad('paddingBottom') - pad('borderTopWidth') - pad('borderBottomWidth'));
    const nw = im.naturalWidth;
    const nh = im.naturalHeight;
    const fit = cs.objectFit;
    const src = im.currentSrc || im.src;
    const e = effectsOf(im);
    const drawn = K.fitDrawn(fit, nw, nh, bw, bh);
    items.push({
      kind: 'img', id: idOf(im), url: path(src), attr: path(im.getAttribute('src') || ''), srcset: im.getAttribute('srcset') || null,
      loading: im.loading, decoding: im.decoding, complete: im.complete, nat: [nw, nh], box: [bw, bh], img: drawn, fit,
      vis: ow > 0 ? r.width / ow : 1, rw: r.width, rh: r.height, none: cs.display === 'none' || ow === 0 || oh === 0 || cs.visibility === 'hidden',
      inView: r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < vh && r.right > 0 && r.left < vw,
      top: Math.round(r.top + W.scrollY), fw: e.fw, cls: e.cls.slice(0, 8), effects: e.effects,
    });
  }

  const BG = [
    ['background-image', 'backgroundImage', 'backgroundSize'],
    ['mask-image', 'maskImage', 'maskSize'],
    ['border-image-source', 'borderImageSource', null],
    ['list-style-image', 'listStyleImage', null],
    ['content', 'content', null],
  ];
  const urlsOf = (v) => [...v.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)/g)].map((m) => m[1] ?? m[2] ?? m[3]);
  for (const el of document.querySelectorAll('*')) {
    for (const pseudo of ['', '::before', '::after']) {
      const cs = getComputedStyle(el, pseudo || null);
      if (pseudo && (cs.content === 'none' || cs.content === 'normal')) continue;
      for (const [prop, key, sizeKey] of BG) {
        const v = cs[key] || (key === 'maskImage' ? cs.webkitMaskImage : '');
        if (!v || v === 'none' || !v.includes('url(')) continue;
        const layers = split(v);
        const sizes = sizeKey ? split(cs[sizeKey] || 'auto') : ['auto'];
        const rect = el.getBoundingClientRect();
        // the positioning area: the padding box (background-origin default); a pseudo element has no box of its own to read, so its
        // host box stands in (flagged by pseudo).
        const bw = pseudo ? el.clientWidth : el.clientWidth;
        const bh = pseudo ? el.clientHeight : el.clientHeight;
        const e = effectsOf(el);
        for (let i = 0; i < layers.length; i++) {
          const us = urlsOf(layers[i]);
          if (us.length === 0) continue;
          const inSet = /image-set\(/.test(layers[i]);
          const u = us[0];
          const nat = await loadNat(new URL(u, document.baseURI).href);
          const tok = sizes[i % sizes.length];
          const drawn = K.bgDrawn(tok, nat[0], nat[1], bw, bh);
          items.push({
            kind: 'bg', prop, id: idOf(el, `${pseudo}#${prop}#${i}`), pseudo, imageSet: inSet, url: path(u), nat, box: [bw, bh], img: drawn, fit: tok,
            vis: el.offsetWidth > 0 ? rect.width / el.offsetWidth : 1, none: cs.display === 'none' || bw === 0 || bh === 0 || cs.visibility === 'hidden',
            inView: rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.top < vh && rect.right > 0 && rect.left < vw,
            top: Math.round(rect.top + W.scrollY), fw: e.fw, cls: e.cls.slice(0, 8), effects: e.effects,
          });
        }
      }
    }
  }
  return { scrollY: W.scrollY, vw, vh, dpr: W.devicePixelRatio, items };
}

/** Scroll to y (instant), wait two frames and until every <img> within two viewports of the stop is complete (at most 4 s). */
export async function scrollStop(y) {
  document.documentElement.style.scrollBehavior = 'auto';
  window.scrollTo({ top: y, behavior: 'instant' });
  const frame = () => new Promise((ok) => requestAnimationFrame(() => ok()));
  await frame();
  await frame();
  // script-driven custom properties (the hero exit) settle a few frames after the scroll
  await new Promise((ok) => setTimeout(ok, 120));
  await frame();
  const t0 = performance.now();
  const near = () => [...document.getElementsByTagName('img')].filter((im) => {
    const r = im.getBoundingClientRect();
    return im.offsetWidth > 0 && r.bottom > -innerHeight && r.top < 2 * innerHeight && !(im.loading === 'lazy' && !im.complete && r.top > 1.5 * innerHeight);
  });
  while (performance.now() - t0 < 4000 && near().some((im) => !im.complete)) await new Promise((ok) => setTimeout(ok, 60));
  await frame();
  return { y: window.scrollY, h: document.documentElement.scrollHeight, vh: innerHeight };
}

/** Put the nav in the end state of the morph tween (`--morph` 1, as `publish` in morph.tween/index.tsx writes it), then let it settle. */
export async function morphEnd() {
  const nav = document.querySelector('[data-fw="nav"]');
  if (!nav) return { nav: false };
  nav.style.setProperty('--morph', '1');
  nav.dataset.fwMorph = '1';
  const frame = () => new Promise((ok) => requestAnimationFrame(() => ok()));
  await frame();
  await frame();
  await new Promise((ok) => setTimeout(ok, 200));
  await frame();
  const t0 = performance.now();
  const wait = () => [...document.getElementsByTagName('img')].some((im) => im.offsetWidth > 0 && !im.complete);
  while (performance.now() - t0 < 4000 && wait()) await new Promise((ok) => setTimeout(ok, 60));
  await frame();
  return { nav: true, morph: getComputedStyle(nav).getPropertyValue('--morph') };
}
