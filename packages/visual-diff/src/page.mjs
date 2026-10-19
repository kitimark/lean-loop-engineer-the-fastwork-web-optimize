// Page-side functions of the visual diff. Each is self-contained (Playwright serialises it with toString) and only REPORTS: the
// decisions are Lean's (verdict.mjs, assets.mjs, settle-adapter.mjs are their golden-checked twins).

/** Scroll the part's box to the top of the viewport, let the frame settle, return the visible box (the crop). */
export async function locateInPage({ selector }) {
  const sleepP = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleepP(250)]);
  const el = document.querySelector(selector);
  if (!el) return { absent: 'no element' };
  const first = el.getBoundingClientRect();
  if (first.width === 0 && first.height === 0) return { absent: 'zero box' };
  window.scrollTo({ top: Math.max(0, first.top + window.scrollY), behavior: 'instant' });
  for (let i = 0; i < 3; i++) await frame();
  await sleepP(250);
  const r = el.getBoundingClientRect();
  const vw = document.documentElement.clientWidth;
  const vh = window.innerHeight;
  const x = Math.floor(Math.max(0, r.left));
  const y = Math.floor(Math.max(0, r.top));
  const right = Math.ceil(Math.min(vw, r.right));
  const bottom = Math.ceil(Math.min(vh, r.bottom));
  if (right - x <= 0 || bottom - y <= 0) return { absent: 'outside the viewport' };
  return { clip: { x, y, width: right - x, height: bottom - y }, scrollY: window.scrollY };
}

/**
 * The assets of the crop, as the page sees them (Fw.Gate.Pixel: `Img`, `Face`, `fontsLoaded`, `imagesLoaded`; decided in Node).
 *   images   every <img> whose box touches the crop: { complete, w, h }, natural size
 *   faces    every FontFace of document.fonts: { family, status }
 *   fams     the first font family (quotes stripped) of every element in the crop that carries text
 * With `waitMs` > 0 it first waits (polling 50 ms, `document.fonts.ready` included) until no face is loading and every image
 * that touches the crop is complete, or the budget is spent; the observation is taken after that.
 * arg: { selector, clip, waitMs }
 */
export async function assetsInPage({ selector, clip, waitMs }) {
  const sleepP = (ms) => new Promise((r) => setTimeout(r, ms));
  const unq = (s) => s.trim().replace(/^["']|["']$/g, '');
  const touches = (r) => r.width > 0 && r.height > 0 && r.right > clip.x && r.left < clip.x + clip.width && r.bottom > clip.y && r.top < clip.y + clip.height;
  const imgs = () => Array.from(document.images).filter((im) => touches(im.getBoundingClientRect()));
  const faces = () => Array.from(document.fonts).map((f) => ({ family: unq(f.family), status: f.status }));
  const t0 = performance.now();
  // A lazy image that touches the crop but whose load WebKit has not started (run 39080594980: star.svg and r5.jpg stayed
  // incomplete 5 s in the original arm) is made eager; the pixels do not change, only when the file is fetched.
  if (waitMs > 0) for (const im of imgs()) if (!im.complete && im.loading === 'lazy') im.loading = 'eager';
  while (waitMs > 0 && performance.now() - t0 < waitMs) {
    const busy = faces().some((f) => f.status === 'loading') || imgs().some((im) => !im.complete);
    if (!busy) break;
    await sleepP(50);
  }
  if (waitMs > 0) { try { await Promise.race([document.fonts.ready, sleepP(500)]); } catch { /* reported by the faces */ } }
  const root = document.querySelector(selector);
  const fams = new Set();
  if (root) {
    const all = [root, ...Array.from(root.querySelectorAll('*')).slice(0, 4000)];
    for (const el of all) {
      let text = false;
      for (const n of el.childNodes) if (n.nodeType === 3 && n.nodeValue.trim() !== '') { text = true; break; }
      if (!text || !touches(el.getBoundingClientRect())) continue;
      fams.add(unq(getComputedStyle(el).fontFamily.split(',')[0] ?? ''));
    }
  }
  return {
    images: imgs().map((im) => ({ complete: im.complete, w: im.naturalWidth, h: im.naturalHeight, src: im.currentSrc || im.getAttribute('src') || '' })),
    faces: faces(),
    fams: Array.from(fams),
    fontsStatus: document.fonts.status,
  };
}

/**
 * The gate's settle wait (Fw.Gate.Settle) on the crop: one observation per real requestAnimationFrame (a 250 ms timer only keeps the
 * loop alive), the finite animations and transitions under the crop's subtree, real frames since the wait began, the run of quiet
 * frames (box, transform numbers and opacity of the crop root within eps of the frame before), and whether the pointer is inside the
 * root. It stops at the first settled observation or when the budget is spent. The outcome is NOT decided here: Node applies the
 * golden-checked twin (settle-adapter.mjs waitTrace) to the returned trace.
 * This is a thin copy of the gate-settle branch's `settleInPage` (packages/gate-breakpoints/src/page.mjs there), narrowed to one
 * root; once that branch has landed this function is replaced by an import.
 * arg: { policy: {minFrames, minStable, eps, timeoutMs}, roots: [selector], hoverCapable }
 */
export async function settleObserveInPage(arg) {
  const p = arg.policy;
  const settled = (q, o) => o.running === 0 && q.minFrames <= o.frames && q.minStable <= o.stable && !o.hoverInside;
  const quiet = (eps, u, v) => u.length === v.length && u.every((a, i) => Math.abs(a - v[i]) <= eps);
  const micro = (x) => Math.round(x * 1e6);
  const els = () => {
    const seen = new Set();
    for (const sel of arg.roots) for (const el of Array.from(document.querySelectorAll(sel)).slice(0, 64)) seen.add(el);
    return Array.from(seen);
  };
  const numbers = (s) => (s.match(/-?\d*\.?\d+(?:e[-+]?\d+)?/g) || []).map(Number);
  const observe = () => {
    const list = els();
    const anims = new Set();
    for (const el of list) {
      let as = [];
      try { as = el.getAnimations({ subtree: true }); } catch { as = []; }
      for (const a of as) {
        const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
        if (t && Number.isFinite(t.iterations) && a.playState !== 'finished' && a.playState !== 'idle') anims.add(a);
      }
    }
    const sig = [micro(window.innerWidth), micro(window.innerHeight)];
    let hover = false;
    for (const el of list) {
      const r = el.getBoundingClientRect();
      sig.push(micro(r.x), micro(r.y), micro(r.width), micro(r.height));
      const cs = getComputedStyle(el);
      for (const n of numbers(cs.transform === 'none' ? '' : cs.transform)) sig.push(micro(n));
      sig.push(micro(Number(cs.opacity)));
      if (arg.hoverCapable && el.matches(':hover')) hover = true;
    }
    return { running: anims.size, hover, sig };
  };
  const t0 = performance.now();
  const trace = [];
  let prev = observe().sig;
  let frames = 0, stable = 0;
  for (;;) {
    const gotFrame = await new Promise((resolve) => {
      let done = false;
      requestAnimationFrame(() => { if (!done) { done = true; resolve(true); } });
      setTimeout(() => { if (!done) { done = true; resolve(false); } }, 250);
    });
    const o = observe();
    if (gotFrame) {
      frames++;
      stable = quiet(p.eps, prev, o.sig) ? stable + 1 : 0;
      prev = o.sig;
    }
    const obs = { running: o.running, frames, stable, hoverInside: o.hover, t: Math.round(performance.now() - t0) };
    trace.push(obs);
    if (settled(p, obs) || obs.t > p.timeoutMs) break;
  }
  return { trace };
}

/** Diagnostic `--assets inject` only: declare the original's font faces in the rewrite page and force them on every element. */
export function injectFontsInPage({ css, family }) {
  const st = document.createElement('style');
  st.setAttribute('data-vd-assets', '');
  st.textContent = `${css}\n*{font-family:"${family}",sans-serif !important}`;
  document.head.appendChild(st);
  return true;
}
