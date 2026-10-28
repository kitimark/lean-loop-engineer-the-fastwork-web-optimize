// The page side of the trajectory probe: an init script that installs `window.__traj`. It only reads and reports; every
// pass/fail decision is in reduce.mjs (Lean Fw.Gate.Trajectory). `installKit` is serialised with toString(), so it holds no
// closure over module scope.
//
// Reads go through getComputedStyle and getBoundingClientRect with NO screenshot between them: a screenshot refreshed the
// stale style of the WebKit hero bug (hero-bug note), so the probe never takes one. requestAnimationFrame stays native.
//
// A value is `null` (the node's element is missing), an array of integers (a measured number x 1000, rounded) or a string.
//
// A colour is `[r, g, b, a]` x 1000 in sRGB (channels and alpha on the 0..255 scale) whatever space the engine printed it in.
let offlineColour = null;
/**
 * Offline only (never in the page): the stored raw files of the runs before the kit converted spaces (39453181962,
 * 39471466367, 39457063232) hold the old reading, not the string. The old kit wrote `rgb`/`rgba`/`color(srgb ..)` as sRGB x 1000
 * and anything else with its numbers as they were (`oklab(0.989 0 0 / 0.1)` as `[989, 0, 0, 25500]`, alpha already x 255).
 * A tuple whose first number is 0..1000 and whose second and third are within +-500 is read as an old `oklab` (lightness
 * 0..1, a and b within +-0.5: the range of the sRGB gamut) and converted; any other tuple already is sRGB x 1000.
 * MEASURED range of the oklab-shaped tuples in the three runs: L 0.234 to 1.0, a -0.004 to 0, b -0.019 to 0 (counts:
 * 39453181962 apple 1321, chromium 1629; 39471466367 apple 726, chromium 1126; 39457063232 playwright-webkit 67, chromium
 * 1014; of them 44, 0, 65, 0, 34 and 10 have a or b not 0). The 0.001 rounding of a stored tuple gives a recovery error of up
 * to 0.64 level on that range (MEASURED, outside the Lean `chanErr` 500): a recovered reading is within 0.64 + 0.008 level of
 * the truth, one recovered arm against an `rgb` arm within 0.64 + 0.5 + 0.008 < 2 levels.
 * Accepted limits: an `rgb` reading with all channels 0 or 1 (a colour 1 of 255 levels from black) is read as oklab; a
 * near-black non-integer old `color(srgb ..)` tuple, such as `[510,255,255]`, has the same shape and is misread as oklab (the
 * stored runs hold none: every oklab-shaped tuple there has b at most 0); a stored `lab`, `lch` or `oklch` reading is not
 * recognised (the stored runs hold none of that shape).
 */
export function colourFromV1(v) {
  if (!Array.isArray(v) || v.length !== 4) return v;
  if (!(v[0] >= 0 && v[0] <= 1000 && Math.abs(v[1]) <= 500 && Math.abs(v[2]) <= 500)) return v;
  if (offlineColour === null) {
    const g = globalThis;
    const had = Object.getOwnPropertyDescriptor(g, 'window');
    g.window = {};
    try { installKit(); offlineColour = g.window.__traj.colour; } finally { if (had) Object.defineProperty(g, 'window', had); else delete g.window; }
  }
  const out = offlineColour(`oklab(${v[0] / 1000} ${v[1] / 1000} ${v[2] / 1000} / ${v[3] / 255000})`);
  return Array.isArray(out) ? out : v;
}

export function installKit() {
  const Q = 1000;
  const q = (x) => Math.round(x * Q);
  const NUM = /-?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/gi;
  const nums = (s) => (String(s).match(NUM) || []).map(Number);
  const cssOf = (cs, css) => {
    for (const c of Array.isArray(css) ? css : [css]) { const v = cs.getPropertyValue(c); if (v && v.trim()) return v.trim(); }
    return '';
  };
  const matrixOf = (cs) => {
    const t = cs.transform;
    try { return !t || t === 'none' ? new DOMMatrix() : new DOMMatrix(t); } catch { return null; }
  };
  /**
   * A computed colour as `[r, g, b, a]` x 1000: sRGB channels on the 0..255 scale and alpha on the same scale, so a colour read
   * as `rgb(...)` at rest and as `oklab(...)` in flight (WebKit; Chromium for a transition that interpolates in oklab) is one
   * space for the judge. The functions and their formulas are Lean `Fw.Gate.Colour` (golden/gate/trajectory-colour.jsonl):
   * rgb/rgba, hsl/hsla, color(srgb|srgb-linear), lab, lch, oklab, oklch. Not clamped: an out-of-gamut colour keeps its
   * channels beyond 0..255. Anything else (another colour space, a keyword, calc()) stays the string, so the judge fails it
   * `type` instead of comparing it as a number.
   */
  const colour = (s) => {
    const m = /^\s*([a-z-]+)\(\s*([^()]*?)\s*\)\s*$/i.exec(String(s));
    if (!m) return s;
    let fn = m[1].toLowerCase();
    let body = m[2];
    if (fn === 'color') {
      const sp = /^([a-z0-9-]+)\s+([^]*)$/i.exec(body);
      if (!sp) return s;
      fn = 'color:' + sp[1].toLowerCase();
      body = sp[2];
    }
    const slash = body.split('/');
    if (slash.length > 2) return s;
    const toks = slash[0].trim().split(/[\s,]+/);
    let atok = slash.length === 2 ? slash[1].trim() : null;
    if (atok === null && toks.length === 4) atok = toks.pop();
    if (toks.length !== 3 || atok === '') return s;
    const num = (t) => {
      if (t === 'none') return { n: 0, u: '' };
      const p = /^([-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?)(deg|%)?$/i.exec(t);
      return p ? { n: Number(p[1]), u: (p[2] || '').toLowerCase() } : null;
    };
    const c = toks.map(num);
    const al = atok === null ? { n: 1, u: '' } : num(atok);
    if (c.includes(null) || al === null) return s;
    const alpha = al.u === '%' ? al.n / 100 : al.n;
    const [c0, c1, c2] = c.map((x) => x.n);
    const mul = (mat, v) => [0, 3, 6].map((i) => mat[i] * v[0] + mat[i + 1] * v[1] + mat[i + 2] * v[2]);
    const enc = (x) => { const a = Math.abs(x); const e = a > 0.0031308 ? 1.055 * Math.pow(a, 1 / 2.4) - 0.055 : 12.92 * a; return x < 0 ? -e : e; };
    // XYZ D65 to linear sRGB, CSS Color 4 XYZ_to_lin_sRGB
    const XYZ_SRGB = [3.2409699419045226, -1.537383177570094, -0.4986107602930034, -0.9692436362808796, 1.8759675015077202, 0.04155505740717559, 0.05563007969699366, -0.20397695888897652, 1.0569715142428786];
    // XYZ D50 to D65, Bradford (WebKit ColorConversion.h 250-255)
    const D50_D65 = [0.955473421488075, -0.02309845494876471, 0.06325924320057072, -0.0283697093338637, 1.0099953980813041, 0.021041441191917323, 0.012314014864481998, -0.020507649298898964, 1.330365926242124];
    // linear LMS to XYZ D65 and Oklab to non-linear LMS (WebKit ColorConversion.cpp 282-292)
    const LMS_XYZ = [1.2268798758459243, -0.5578149944602171, 0.2813910456659647, -0.0405757452148008, 1.1122868032803170, -0.0717110580655164, -0.0763729366746601, -0.4214933324022432, 1.5869240198367816];
    const OKLAB_LMS = [1, 0.3963377773761749, 0.2158037573099136, 1, -0.1055613458156586, -0.0638541728258133, 1, -0.0894841775298119, -1.2914855480194092];
    const oklab = (l, a, b) => mul(XYZ_SRGB, mul(LMS_XYZ, mul(OKLAB_LMS, [l, a, b]).map((x) => x * x * x))).map(enc);
    const lab = (l, a, b) => {
      const E = 216 / 24389, K = 24389 / 27;
      const f1 = (l + 16) / 116, f0 = f1 + a / 500, f2 = f1 - b / 200;
      const xz = (t) => (t * t * t > E ? t * t * t : (116 * t - 16) / K);
      const y = l > K * E ? f1 * f1 * f1 : l / K;
      return mul(XYZ_SRGB, mul(D50_D65, [(0.3457 / 0.3585) * xz(f0), y, ((1 - 0.3457 - 0.3585) / 0.3585) * xz(f2)])).map(enc);
    };
    const polar = (ch, h) => [ch * Math.cos((h * Math.PI) / 180), ch * Math.sin((h * Math.PI) / 180)];
    const hsl = (h, sat, l) => {
      const a = sat * Math.min(l, 1 - l);
      const f = (n) => { const t = n + h / 30; const k = t - 12 * Math.floor(t / 12); return l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1)); };
      return [f(0), f(8), f(4)];
    };
    // floor(x + 0.5), never -0 (Lean q255)
    const out = (rgb) => [...rgb.map((x) => Math.floor(x * 255 * Q + 0.5)), Math.floor(alpha * 255 * Q + 0.5)];
    if (fn === 'rgb' || fn === 'rgba') {
      const ch = c.map((x) => (x.u === '%' ? (x.n * 255) / 100 : x.n));
      return [...ch.map((x) => Math.floor(x * Q + 0.5)), Math.floor(alpha * 255 * Q + 0.5)];
    }
    if (fn === 'hsl' || fn === 'hsla') return out(hsl(c0, c1 / 100, c2 / 100));
    if (c.some((x) => x.u === '%')) return s;
    if (fn === 'color:srgb') return out([c0, c1, c2]);
    if (fn === 'color:srgb-linear') return out([c0, c1, c2].map(enc));
    if (fn === 'lab') return out(lab(c0, c1, c2));
    if (fn === 'lch') return out(lab(c0, ...polar(c1, c2)));
    if (fn === 'oklab') return out(oklab(c0, c1, c2));
    if (fn === 'oklch') return out(oklab(c0, ...polar(c1, c2)));
    return s;
  };
  const readers = {
    num: (el, p, c) => { const v = parseFloat(cssOf(c.cs, p.css)); return Number.isFinite(v) ? [q(v)] : cssOf(c.cs, p.css); },
    css: (el, p, c) => cssOf(c.cs, p.css),
    cssnum: (el, p, c) => { const v = parseFloat(cssOf(c.cs, p.css)); return Number.isFinite(v) ? [q(v)] : cssOf(c.cs, p.css); },
    fnmask: (el, p, c) => cssOf(c.cs, p.css).replace(NUM, '#'),
    fnnum: (el, p, c) => nums(cssOf(c.cs, p.css)).map(q),
    tlin: (el, p, c) => { const m = matrixOf(c.cs); return m ? [m.m11, m.m12, m.m13, m.m21, m.m22, m.m23, m.m31, m.m32, m.m33].map(q) : c.cs.transform; },
    tshift: (el, p, c) => { const m = matrixOf(c.cs); return m ? [m.m41, m.m42, m.m43].map(q) : c.cs.transform; },
    // a percentage translate is a share of the element's own box, so it is read as px: the two arms may write the same move either way
    translate: (el, p, c) => {
      const v = c.cs.translate;
      if (!v || v === 'none') return [0, 0, 0];
      const dims = [el.offsetWidth, el.offsetHeight, 0];
      const n = v.trim().split(/\s+/).map((t, i) => (t.endsWith('%') ? (parseFloat(t) * dims[i]) / 100 : parseFloat(t)));
      while (n.length < 3) n.push(0);
      return n.map(q);
    },
    rotate: (el, p, c) => { const v = c.cs.rotate; return !v || v === 'none' ? [0] : nums(v).map(q); },
    scale: (el, p, c) => {
      const v = c.cs.scale;
      if (!v || v === 'none') return [q(1), q(1), q(1)];
      const n = nums(v);
      return [q(n[0]), q(n.length > 1 ? n[1] : n[0]), q(n.length > 2 ? n[2] : 1)];
    },
    rect: (el) => { const r = el.getBoundingClientRect(); return [r.x, r.y, r.width, r.height].map(q); },
    relrect: (el, p, c) => {
      const ref = c.first[p.to]; if (!ref) return null;
      const r = el.getBoundingClientRect(), o = ref.getBoundingClientRect();
      return [r.x - o.x, r.y - o.y, r.width, r.height].map(q);
    },
    colour: (el, p, c) => colour(cssOf(c.cs, p.css)),
    lens: (el, p, c) => { const v = cssOf(c.cs, p.css); return nums(v).length > 0 && !/[a-z%]/i.test(v.replace(/px/g, '')) ? nums(v).map(q) : v; },
    cls: (el, p, c) => { const e = p.on ? c.first[p.on] : el; return e ? (e.classList.contains(p.name) ? 'on' : 'off') : null; },
    attr: (el, p) => (p.prop ? [q(el[p.prop])] : el.hasAttribute(p.name) ? el.getAttribute(p.name) : '(none)'),
    flag: (el, p) => (el.hasAttribute(p.name) && el.getAttribute(p.name) !== 'false' ? 'on' : 'off'),
    scrollHeight: () => [q(document.documentElement.scrollHeight)],
  };
  /**
   * Every property of every element of each node, in the registry order. Values read from one style per element, created on the
   * first property that needs it. With `lean`, a property not marked `lean` is not read (null in its place), so the indices
   * of the reading stay those of the registry.
   */
  const readNodes = (arm, nodes, lean) => {
    const first = {};
    const els = {};
    for (const n of nodes) { els[n.id] = Array.from(document.querySelectorAll(n.sel)); first[n.id] = els[n.id][0] || null; }
    const out = {};
    for (const n of nodes) {
      out[n.id] = els[n.id].map((el) => {
        let style = null;
        const c = { get cs() { return style || (style = getComputedStyle(el)); }, first };
        return n.props.map((p0) => {
          if (lean && !p0.lean) return null;
          const p = arm === 'orig' && p0.orig ? { ...p0, ...p0.orig } : p0;
          try { return readers[p.r](el, p, c); } catch (e) { return 'error: ' + String(e && e.message || e).slice(0, 60); }
        });
      });
    }
    return out;
  };
  /** Whether each element of each node has a box (getClientRects().length > 0: Chromium Element::ClientQuads, WebKit Element::getClientRects). */
  const boxesOf = (nodes) => {
    const out = {};
    for (const n of nodes) out[n.id] = Array.from(document.querySelectorAll(n.sel)).map((el) => el.getClientRects().length > 0);
    return out;
  };
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  /** The end of a rendering frame: after the rAF callbacks of that frame, whatever they wrote is in the next style read. */
  const frameEnd = async () => { await raf(); await sleep(0); };
  const T0 = performance.now();
  /** Milliseconds since the kit was installed, with a tenth of a millisecond (the read of one frame is a few ms). */
  const stamp = () => Math.round((performance.now() - T0) * 10) / 10;

  /** Wait until the scroll position has not changed for 8 frames (or `cap` ms): the original smooths a scroll, the rewrite does not. */
  const settle = async (cap) => {
    let still = 0, last = -1;
    const t1 = performance.now();
    while (still < 8 && performance.now() - t1 < cap) {
      await frameEnd();
      const y = Math.round(window.scrollY);
      still = y === last ? still + 1 : 0;
      last = y;
    }
    return { settled: still >= 8, waited: Math.round(performance.now() - t1) };
  };

  const state = { rows: [], loop: false, gen: 0, lastMut: null, observer: null };
  /**
   * A page recorder (apps/site/src/debug/nav-transition.ts, only on `fw-debug=nav-transition`) offers `window.__fwDebug.navTransitionRead`;
   * calling it before the reads of a sample puts a `read` row in the recorder's own log, so a forced style flush between two of its
   * rows is visible there. No recorder: nothing happens (the original arm and every run without the debug key).
   */
  const stampRead = () => {
    const d = window.__fwDebug;
    if (d && typeof d.navTransitionRead === 'function') d.navTransitionRead();
  };
  /**
   * One sample: the time before the reads (`t0`) and after (`t1`, also `t`), scroll, the morph value (x 10000) and ms since the
   * last nav class change, the nodes. `t1 - t0` is the read cost; the gap between two `t0` is the frame time with the reads in it.
   */
  const snap = (arg, tag, extra) => {
    stampRead();
    const t0 = stamp();
    const nav = arg.navSel ? document.querySelector(arg.navSel) : null;
    let m = null;
    if (nav) { const v = parseFloat(getComputedStyle(nav).getPropertyValue('--morph')); if (Number.isFinite(v)) m = Math.round(v * 10000); }
    const nodes = readNodes(arg.arm, arg.nodes, arg.lean === true);
    const box = arg.boxes === true ? boxesOf(arg.nodes) : null;
    const page = arg.pageProps.length === 0 ? [] : readNodes(arg.arm, [{ id: 'page', sel: 'html', props: arg.pageProps }], false).page[0];
    const t1 = stamp();
    return { tag, t: t1, t0, t1, y: Math.round(window.scrollY), m, since: state.lastMut === null ? null : Math.round(performance.now() - state.lastMut), page, nodes, ...(box === null ? {} : { box }), ...extra };
  };

  const heroPath = async (arg) => {
    const rows = [];
    window.scrollTo(0, 0);
    await frameEnd();
    await sleep(arg.restMs);
    const vh = window.innerHeight;
    let y0 = Math.round(window.scrollY);
    for (let i = 0; i < arg.steps.length; i++) {
      const st = arg.steps[i];
      const max = document.documentElement.scrollHeight - vh;
      const yt = Math.max(0, Math.min(max, Math.round(st.at === 'mid' ? max / 2 : st.at * vh)));
      for (let f = 1; f <= arg.moveFrames && yt !== y0; f++) {
        window.scrollTo(0, Math.round(y0 + ((yt - y0) * f) / arg.moveFrames));
        await frameEnd();
        rows.push(snap(arg, `${st.id}/m${f}`, { step: st.id, frame: `m${f}` }));
      }
      y0 = yt;
      window.scrollTo(0, yt);
      // The original smooths scrollTo, so the rest is "the scroll position has stopped" (same value on 8 frames, capped), then the dwell.
      // WebKit's smooth scroll sometimes stops short or never starts while the position stays still for 8 frames (macos-26: 114 of the
      // faithful rewrite's units fell on a step where the original rested at an older y). A rest short of its target is retried
      // twice with an instant scroll, so both arms are read at the position the step names. The row keeps `target` for the reducer.
      let s = await settle(arg.settleCapMs);
      for (let k = 0; k < 2 && Math.round(window.scrollY) !== yt; k++) {
        window.scrollTo({ top: yt, left: 0, behavior: 'instant' });
        s = await settle(arg.settleCapMs);
      }
      await sleep(st.dwellMs || arg.restMs);
      await frameEnd();
      rows.push(snap(arg, `${st.id}/rest`, { step: st.id, frame: 'rest', target: yt, ...s }));
    }
    return rows;
  };

  const watchNav = (navSel) => {
    if (state.observer) state.observer.disconnect();
    const nav = document.querySelector(navSel);
    state.lastMut = null;
    if (!nav) return false;
    state.observer = new MutationObserver(() => { state.lastMut = performance.now(); });
    state.observer.observe(nav, { attributes: true, attributeFilter: ['class'] });
    return true;
  };

  /** Scroll from three viewports before the end to the end in quarter-viewport steps; read after each step, then rest. */
  const approach = async (arg) => {
    const rows = [];
    const vh = window.innerHeight;
    const end = () => document.documentElement.scrollHeight - vh;
    const start = Math.max(0, end() - 3 * vh);
    const at = async (tag, step, y, dwell) => {
      window.scrollTo(0, y);
      const s = await settle(arg.settleCapMs);
      await sleep(dwell);
      await frameEnd();
      rows.push(snap(arg, tag, { step, frame: 'rest', target: y, ...s }));
    };
    await at('approach/0', 'a0', start, arg.restMs);
    for (let k = 1; k <= 12; k++) await at(`approach/${k}`, 'a' + k, Math.min(end(), start + Math.round((k * vh) / 4)), 150);
    await at('rest', 'rest', end(), 1500);
    return rows;
  };

  /** Sample every `stride`-th rendering frame until `stopSampler`. */
  const startSampler = (arg) => {
    state.rows = [];
    state.loop = true;
    const mine = ++state.gen; // a stopped loop may still be inside its last frame: only the newest generation records
    let n = 0;
    (async () => {
      while (state.loop && state.gen === mine) {
        await frameEnd();
        if (!state.loop || state.gen !== mine) break;
        if (n++ % arg.stride === 0) state.rows.push(snap(arg, arg.phase, { step: arg.phase, frame: 'f' + state.rows.length }));
      }
    })();
    return true;
  };
  const stopSampler = () => { state.loop = false; state.gen++; const r = state.rows; state.rows = []; return r; };

  window.__traj = { colour, heroPath, approach, watchNav, startSampler, stopSampler, now: stamp };
}
