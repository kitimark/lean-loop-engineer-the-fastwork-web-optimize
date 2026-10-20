// The page side of the trajectory probe: an init script that installs `window.__traj`. It only reads and reports; every
// pass/fail decision is in reduce.mjs (Lean Fw.Gate.Trajectory). `installKit` is serialised with toString(), so it holds no
// closure over module scope.
//
// Reads go through getComputedStyle and getBoundingClientRect with NO screenshot between them: a screenshot refreshed the
// stale style of the WebKit hero bug (hero-bug note), so the probe never takes one. requestAnimationFrame stays native.
//
// A value is `null` (the node's element is missing), an array of integers (a measured number x 1000, rounded) or a string.
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
  const colour = (s) => {
    const n = nums(s);
    if (/^color\(/.test(s)) {
      const slash = s.includes('/');
      return [q(n[0] * 255), q(n[1] * 255), q(n[2] * 255), q((slash ? n[3] : 1) * 255)];
    }
    if (n.length >= 3) return [q(n[0]), q(n[1]), q(n[2]), q((n.length > 3 ? n[3] : 1) * 255)];
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
   * One sample: the time before the reads (`t0`) and after (`t1`, also `t`), scroll, the morph value (x 10000) and ms since the
   * last nav class change, the nodes. `t1 - t0` is the read cost; the gap between two `t0` is the frame time with the reads in it.
   */
  const snap = (arg, tag, extra) => {
    const t0 = stamp();
    const nav = arg.navSel ? document.querySelector(arg.navSel) : null;
    let m = null;
    if (nav) { const v = parseFloat(getComputedStyle(nav).getPropertyValue('--morph')); if (Number.isFinite(v)) m = Math.round(v * 10000); }
    const nodes = readNodes(arg.arm, arg.nodes, arg.lean === true);
    const page = arg.pageProps.length === 0 ? [] : readNodes(arg.arm, [{ id: 'page', sel: 'html', props: arg.pageProps }], false).page[0];
    const t1 = stamp();
    return { tag, t: t1, t0, t1, y: Math.round(window.scrollY), m, since: state.lastMut === null ? null : Math.round(performance.now() - state.lastMut), page, nodes, ...extra };
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

  window.__traj = { heroPath, approach, watchNav, startSampler, stopSampler, now: stamp };
}
