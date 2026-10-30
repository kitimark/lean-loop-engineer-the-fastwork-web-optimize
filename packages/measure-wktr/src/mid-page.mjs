// Fork of packages/gate-breakpoints/src/track-accel-page.mjs (task geom-webkit-midflip) with the `P.mid` mid-flip readout; the WKTR run
// uses this copy because that task may not write gate-breakpoints. Merge it back in a task that owns both.
// The page side of the geom-track-style probe (task geom-track-style), shared by the Chromium run (track-accel.mjs, Playwright) and
// the WebKit run (packages/measure-wktr/src/accel-cli.mjs, WebKitTestRunner). It is an init script: it wraps Element.prototype.animate
// before the site runs, tags every Web Animation the morph.geom drivers create on a [data-mg] element, and runs one scenario per arm.
//
//   mode scrubbed  `morph.geom:on`: the probe pins the nav morph 0 -> 1 in N frames (the flip-cell's own pin), so the driver creates paused
//                  tracks and writes `currentTime` each frame.
//   mode timed     `morph.geom:on,morph.tween:geom-timed`: the probe scrolls to the page bottom in steps (the flip-cell's stepScroll); the
//                  take creates running tracks and sets their `startTime` once.
//   arm            which track groups are held still: `all` (nothing held), `no-<css property>` (that property's tracks held),
//                  `none` (every track held). Held = a scrubbed track ignores its `currentTime` writes; a timed track is paused at 0 and
//                  ignores its `startTime` write. The site is not changed; the wrapper does this to the Animation objects it receives.
//                  `idle` holds every track and sends no input (scrubbed: one pin, no more writes; timed: no wheel), the baseline of the site's
//                  own per-frame style work.
//
// Readouts: per arm the frames and ms of the window, and style recalcs counted in the page where the engine allows it
// (`internals.styleRecalcCount()` in WebKitTestRunner). Chromium counts recalcs from the trace (marks `fwx:<arm>:<stage>:start|end`).
// For the arm `all` the mid-window table lists every tag with its play state and, in WebKitTestRunner, the accelerated animations the
// element's graphics layer holds (`internals.acceleratedAnimationsForElement`, Internals.cpp:1534@862f17d).

import { BS_C } from './recalc-bisect.mjs';

export const PROPS = ['translate', 'scale', 'transform', 'opacity', 'filter', 'backdrop-filter'];
export const ARMS = ['all', ...PROPS.map((p) => `no-${p}`), 'none', 'idle', 'all-again'];

/** The tags are sealed in the page by the wrapper; the node side reads them back with this exact shape. */
export const SCHEMA = 'fw.track-accel/1';

function pageProbe(P) {
  const X = (window.__fwx = { created: [], suppress: new Set(), mode: P.mode, arm: null, n: 0, rows: [], tags: [], table: null, errors: [] });
  const CSSN = { backdropFilter: 'backdrop-filter' };
  const NONKEY = new Set(['offset', 'easing', 'composite']);
  const origRaf = window.requestAnimationFrame.bind(window);
  const origST = window.setTimeout.bind(window);
  const origSI = window.setInterval.bind(window);
  const origAnimate = Element.prototype.animate;
  const GH = (X.gh = { begin: new Map(), read: null });
  if (P.gh && window.SVGAnimationElement) {
    const ob = SVGAnimationElement.prototype.beginElement;
    SVGAnimationElement.prototype.beginElement = function () {
      const svg = this.ownerSVGElement;
      const t = svg ? svg.getCurrentTime() * 1000 : 0;
      const now = performance.now();
      const r = ob.apply(this, arguments);
      if (svg) {
        const b = GH.begin.get(svg);
        if (!b || now - b.at > 50) GH.begin.set(svg, { t0: t, at: now, n: 1 });
        else { b.at = now; b.n++; }
      }
      return r;
    };
    GH.read = () => {
      const o = [null, null];
      for (const [svg, b] of GH.begin) {
        if (!svg.isConnected) continue;
        const d = svg.closest('[data-fw-dash]');
        const side = d ? d.getAttribute('data-fw-dash') : null;
        if (side !== 'left' && side !== 'right') continue;
        o[side === 'left' ? 0 : 1] = Math.round(svg.getCurrentTime() * 1000 - b.t0);
      }
      return o;
    };
  }
  Element.prototype.animate = function (frames, opts) {
    if (X.rs && X.rs.cur) X.rs.add('anim:' + X.rs.partOf(this));
    const mg = this.getAttribute ? this.getAttribute('data-mg') : null;
    if (mg === null) return origAnimate.call(this, frames, opts);
    const first = Array.isArray(frames) && frames.length ? frames[0] : {};
    const props = Object.keys(first).filter((k) => !NONKEY.has(k)).map((k) => CSSN[k] || k);
    const prop = props.length ? props[0] : '?';
    const id = 'fwx' + X.n++;
    // Element.animate plays before the engine reads the id (Chromium writes the trace BEGIN at play), so the probe builds the same pair by
    // hand, names it, then plays it: new KeyframeEffect + new Animation + play() is what animate() does.
    const a = new Animation(new KeyframeEffect(this, frames, opts), document.timeline);
    a.id = id;
    a.play();
    const idx = Array.prototype.indexOf.call(document.querySelectorAll('[data-mg="' + mg + '"]'), this);
    const tag = { id: id, mg: mg, prop: prop, idx: idx, arm: X.arm, held: false };
    if (X.suppress.has(prop)) {
      tag.held = true;
      if (X.mode === 'scrubbed') {
        Object.defineProperty(a, 'currentTime', { get: function () { return 0; }, set: function () {}, configurable: true });
      } else {
        a.pause();
        Object.defineProperty(a, 'startTime', { get: function () { return null; }, set: function () {}, configurable: true });
      }
    }
    X.created.push({ tag: tag, a: a, el: this });
    X.tags.push(tag);
    if (X.onFirst && X.created.length === 1) { const f = X.onFirst; X.onFirst = null; f(); }
    return a;
  };

  const sleep = (ms) => new Promise((r) => origST(r, ms));
  const raf = () => new Promise((r) => origRaf(() => r()));
  const I = window.internals || null;
  const recalc = () => (I && typeof I.styleRecalcCount === 'function' ? I.styleRecalcCount() : null);
  const mark = (name) => { try { performance.mark(name); } catch (e) { /* no user timing */ } };
  const nav = () => document.querySelector('[data-fw="nav"]');
  const pin = (m) => {
    const n = nav();
    n.classList.toggle('is-on-dark', m > 0.2 || !!n.dataset.fwKeepDark);
    n.style.setProperty('--morph', String(m));
    n.dataset.fwMorph = String(m);
  };
  const armSet = (arm) => {
    if (arm === 'none' || arm === 'idle') return new Set(P.props);
    if (arm.indexOf('no-') === 0) return new Set([arm.slice(3)]);
    return new Set();
  };
  const norm = (s) => String(s).toLowerCase().replace(/[^a-z]/g, '');
  const cls = (p) => { const n = norm(p); return n === 'translate' || n === 'scale' || n === 'rotate' || n === 'transform' ? 'transform' : n; };

  const readout = () => {
    const rows = X.created.map((c) => {
      const row = { id: c.tag.id, mg: c.tag.mg, prop: c.tag.prop, idx: c.tag.idx, held: c.tag.held, state: c.a.playState, pending: !!c.a.pending };
      if (P.mid) {
        row.cur = c.a.currentTime;
        if (I && typeof I.timeToNextAnimationTick === 'function') {
          const v = I.timeToNextAnimationTick(c.a);
          row.ttnt = v === Infinity ? 'inf' : v;
        }
      }
      return row;
    });
    if (I && typeof I.acceleratedAnimationsForElement === 'function') {
      const byEl = new Map();
      X.created.forEach((c, i) => {
        if (!byEl.has(c.el)) byEl.set(c.el, I.acceleratedAnimationsForElement(c.el).map((x) => ({ property: x.property, speed: x.speed, isThreaded: x.isThreaded })));
        const list = byEl.get(c.el);
        const hit = list.filter((x) => norm(x.property) === norm(c.tag.prop));
        rows[i].accel = hit.length > 0;
        rows[i].speed = hit.length ? hit[0].speed : null;
        rows[i].threaded = hit.length ? hit[0].isThreaded : null;
        if (P.mid) {
          rows[i].ent = list.map((x) => x.property);
          rows[i].tc = X.created.filter((o) => o.el === c.el && cls(o.tag.prop) === cls(c.tag.prop)).length;
        }
      });
      const seen = {};
      for (const list of byEl.values()) for (const x of list) seen[x.property] = (seen[x.property] || 0) + 1;
      X.accelProps = seen;
    }
    return rows;
  };

  const windowFrames = async (arm, stage, ms, frames, mid) => {
    mark('fwx:' + arm + ':' + stage + ':start');
    const r0 = recalc();
    const t0 = performance.now();
    let n = 0;
    let midDone = false;
    for (;;) {
      await raf();
      n++;
      if (mid && !midDone && (frames ? n >= frames / 2 : performance.now() - t0 >= ms / 3)) {
        midDone = true;
        X.table = readout();
        X.docAnims = document.getAnimations().length;
      }
      if (frames ? n >= frames : performance.now() - t0 >= ms) break;
    }
    const t1 = performance.now();
    mark('fwx:' + arm + ':' + stage + ':end');
    const r1 = recalc();
    return { stage: stage, frames: n, ms: Math.round(t1 - t0), recalc: r0 === null ? null : r1 - r0 };
  };

  const envNow = () => {
    const e = {};
    const get = (k, f) => { try { if (I && typeof I[f] === 'function') e[k] = I[f](); else if (I && f in I) e[k] = I[f]; } catch (x) { e[k] = 'err'; } };
    get('act', 'numberOfActiveAnimations');
    get('inv', 'numberOfAnimationTimelineInvalidations');
    get('itv', 'animationsInterval');
    get('rc', 'styleRecalcCount');
    try { if (I && 'lastStyleUpdateSize' in I) e.upd = I.lastStyleUpdateSize; } catch (x) { e.upd = 'err'; }
    return e;
  };

  const listAnims = () => {
    const out = [];
    for (const a of document.getAnimations()) {
      const ef = a.effect;
      const t = ef && ef.target;
      let keys = [];
      try { keys = ef && ef.getKeyframes ? Object.keys(ef.getKeyframes()[0] || {}).filter((k) => !NONKEY.has(k) && k !== 'computedOffset') : []; } catch (x) { keys = ['err']; }
      const row = { kind: a.constructor ? a.constructor.name : '?', name: a.animationName || a.transitionProperty || a.id || '', state: a.playState, pending: !!a.pending, keys: keys };
      if (t) row.target = (t.tagName || '?').toLowerCase() + (t.getAttribute && t.getAttribute('data-fw') ? '[data-fw=' + t.getAttribute('data-fw') + ']' : '') + (t.getAttribute && t.getAttribute('data-mg') ? '[data-mg=' + t.getAttribute('data-mg') + ']' : '') + (t.className && typeof t.className === 'string' ? '.' + t.className.split(' ').slice(0, 2).join('.') : '');
      if (I && typeof I.timeToNextAnimationTick === 'function') { const v = I.timeToNextAnimationTick(a); row.ttnt = v === Infinity ? 'inf' : v; }
      if (I && typeof I.acceleratedAnimationsForElement === 'function' && t && ef.constructor && ef.constructor.name === 'KeyframeEffect') {
        try { row.accel = I.acceleratedAnimationsForElement(t).map((x) => x.property); } catch (x) { row.accel = ['err']; }
      }
      out.push(row);
    }
    return out;
  };

  // Whether the element has a compositing layer: Internals.setElementTracksDisplayListReplay throws without one (Internals.cpp:3968-3987@862f17d).
  const layOf = (el) => {
    if (!(I && typeof I.setElementTracksDisplayListReplay === 'function')) return null;
    try { I.setElementTracksDisplayListReplay(el, false); return 1; } catch (e) { return 0; }
  };
  const compactRows = (withLay) => {
    const lays = new Map();
    return readout().map((r, i) => {
      const el = X.created[i] && X.created[i].el;
      if (withLay && el && !lays.has(el)) lays.set(el, layOf(el));
      return { id: r.id, s: r.state, p: r.pending ? 1 : 0, a: r.accel ? 1 : 0, th: r.threaded, t: r.ttnt, c: r.cur === null || r.cur === undefined ? null : Math.round(r.cur), e: r.ent, tc: r.tc, l: withLay && el ? lays.get(el) : undefined };
    });
  };
  const layersBefore = () => Array.from(document.querySelectorAll('[data-mg]')).map((el) => [el.getAttribute('data-mg'), layOf(el)]);

  const midWindow = async (arm, idle, tw) => {
    const dur = P.durationMs;
    const ref = X.created.find((c) => !c.tag.held);
    const phase = () => {
      if (ref) {
        if (ref.a.playState === 'idle') return 9;
        const c = ref.a.currentTime;
        if (c !== null && c !== undefined) return c / dur;
      }
      return (performance.now() - tw) / dur;
    };
    mark('fwx:' + arm + ':flip:start');
    const r0 = recalc();
    const t0 = performance.now();
    const frames = [];
    const samples = [];
    let next = 0;
    let listed = null;
    let alive = true;
    const take = (why, ph) => {
      const rows = compactRows(true);
      const s = { why: why, ph: Math.round(ph * 1000), dt: Math.round(performance.now() - t0), env: envNow(), rows: rows };
      samples.push(s);
      if (!listed && ph >= 0.4 && P.listAnims) {
        const a0 = recalc();
        listed = { ph: s.ph, list: listAnims() };
        listed.listRc = recalc() === null ? null : recalc() - a0;
      }
      return s;
    };
    const check = () => {
      if (idle || next >= P.mid.length) return;
      const ph = phase();
      if (ph >= P.mid[next] && ph < 1.0) {
        take('p' + Math.round(P.mid[next] * 100), ph);
        while (next < P.mid.length && P.mid[next] <= ph) next++;
      }
    };
    const poll = () => { if (!alive) return; check(); origST(poll, 4); };
    poll();
    let post = 0;
    let f = 0;
    const mid0 = idle ? [0.25, 0.5, 0.75] : [];
    for (;;) {
      await raf();
      f++;
      const now = performance.now();
      const ph = phase();
      const e = envNow();
      frames.push({ n: f, dt: Math.round(now - t0), ph: Math.round(ph * 1000), rc: e.rc === undefined || r0 === null ? null : e.rc - r0, upd: e.upd, inv: e.inv, act: e.act });
      check();
      if (idle && mid0.length && (now - t0) / dur >= mid0[0]) {
        take('i' + Math.round(mid0[0] * 100), mid0[0]);
        mid0.shift();
      }
      if (idle ? now - t0 >= dur : (ph >= 1 ? ++post > 2 : false) || now - t0 > P.capMs) break;
    }
    alive = false;
    const last = take('end', phase() > 5 ? 1.5 : phase());
    const t1 = performance.now();
    mark('fwx:' + arm + ':flip:end');
    const r1 = recalc();
    return { stage: { stage: 'flip', frames: f, ms: Math.round(t1 - t0), recalc: r0 === null ? null : r1 - r0 }, samples: samples, frames: frames, listed: listed, last: last.ph };
  };

  const scrubbedArm = async (arm) => {
    X.arm = arm;
    X.suppress = armSet(arm);
    X.created.length = 0;
    pin(0);
    await raf(); await raf(); await sleep(250);
    const out = { arm: arm, mode: 'scrubbed', stages: [] };
    const m0 = 0.25;
    const step = (1 - m0) / P.sweepFrames;
    pin(m0);
    out.stages.push(await windowFrames(arm, 'enter', 0, 2, false));
    out.tracks = X.created.length;
    let k = 1;
    const sweep = async () => {
      mark('fwx:' + arm + ':sweep:start');
      const r0 = recalc();
      const t0 = performance.now();
      for (let f = 0; f < P.sweepFrames; f++) {
        k++;
        if (arm !== 'idle') pin(Math.min(1, m0 + k * step));
        await raf();
        if (f === (P.sweepFrames >> 1)) { X.table = readout(); X.docAnims = document.getAnimations().length; }
      }
      const t1 = performance.now();
      mark('fwx:' + arm + ':sweep:end');
      const r1 = recalc();
      return { stage: 'sweep', frames: P.sweepFrames, ms: Math.round(t1 - t0), recalc: r0 === null ? null : r1 - r0 };
    };
    out.stages.push(await sweep());
    out.table = X.table;
    out.docAnims = X.docAnims;
    X.table = null;
    pin(0);
    out.stages.push(await windowFrames(arm, 'leave', 0, 3, false));
    await sleep(250);
    return out;
  };

  const toBottom = async () => {
    const max = () => document.documentElement.scrollHeight - window.innerHeight;
    for (let i = 0; i < 20 && Math.abs(window.scrollY - max()) > 2; i++) { window.scrollTo(0, max()); await sleep(150); }
    return Math.round(window.scrollY);
  };
  const wheel = (dy) => window.dispatchEvent(new WheelEvent('wheel', { deltaY: dy, bubbles: true, cancelable: true }));

  // The timed tween starts on a downward wheel while the platform fills the viewport bottom (morph.tween/driver.ts armed + move); the
  // probe sends that wheel itself, then the upward one that runs the reverse flip.
  // Reads right after the tracks exist, before the next frame: the blending keyframes and the layer animations are made by the first style
  // update, so each step forces one more stage (getAnimations() flushes style, a forced layout runs the post-layout tasks, layerTreeAsText
  // commits the compositing update) and reads again, with the phase of the reference track and the time the step took.
  const flushSamples = () => {
    const ref = X.created.find((c) => !c.tag.held);
    const out = [];
    const steps = [
      ['f-style', () => document.getAnimations().length],
      ['f-layout', () => document.documentElement.getBoundingClientRect().height],
      ['f-layers', () => (I && typeof I.layerTreeAsText === 'function' ? I.layerTreeAsText(document).length : -1)],
    ];
    for (const [why, fn] of steps) {
      const t0 = performance.now();
      let err = null;
      try { fn(); } catch (e) { err = String(e && e.message || e).slice(0, 80); }
      const ms = Math.round((performance.now() - t0) * 10) / 10;
      const cur = ref && ref.a.currentTime !== null && ref.a.currentTime !== undefined ? ref.a.currentTime : null;
      out.push({ why: why, ph: cur === null ? null : Math.round((cur / P.durationMs) * 1000), ms: ms, err: err, env: envNow(), rows: compactRows() });
    }
    return out;
  };

  // Task geom-sweep-paused. Arms `sw-<warm|flip|idle>[-p][-t]`: -p pauses exactly the sweepDoc animations (CSSAnimation named sweepDoc whose
  // target sits in section[data-fw=platform]) before the window and plays them after; -t adds a forced style flush and a forced layout flush
  // at the start of every frame callback and times each one. Plain arms are unperturbed (recalcs per frame); -t arms give the style and layout ms.
  const SW_ARM = /^sw-(warm|flip|idle)(-[pao])?(-t)?$/;
  const sweepAnims = () => {
    const sec = document.querySelector('[data-fw="platform"]');
    const all = document.getAnimations();
    const css = all.filter((a) => typeof CSSAnimation !== 'undefined' && a instanceof CSSAnimation && sec && a.effect && a.effect.target && sec.contains(a.effect.target));
    const hit = css.filter((a) => /(^|[-_])sweepDoc(_[A-Za-z0-9-]+)?$/.test(a.animationName));
    return { hit: hit, ident: { total: all.length, platformCss: css.map((a) => a.animationName), n: hit.length, texts: hit.map((a) => String(a.effect.target.textContent || '').trim().slice(0, 16)) } };
  };
  const swWindow = async (arm, idle, tw, timing) => {
    const dur = P.durationMs;
    const ref = X.created.find((c) => !c.tag.held);
    const phase = () => {
      if (ref) {
        if (ref.a.playState === 'idle') return 9;
        const c = ref.a.currentTime;
        if (c !== null && c !== undefined) return c / dur;
      }
      return (performance.now() - tw) / dur;
    };
    mark('fwx:' + arm + ':sw:start');
    const r0 = recalc();
    const t0 = performance.now();
    const list = [];
    let f = 0, post = 0, styleMs = 0, layoutMs = 0, flushRc = 0, updSum = 0, updMax = 0;
    for (;;) {
      await raf();
      f++;
      const now = performance.now();
      const ph = idle ? null : phase();
      let st = null, la = null, rcIn = null;
      if (timing) {
        const q0 = recalc();
        const a = performance.now();
        document.getAnimations();
        const b = performance.now();
        document.documentElement.getBoundingClientRect();
        const c = performance.now();
        const q1 = recalc();
        st = b - a;
        la = c - b;
        styleMs += st;
        layoutMs += la;
        rcIn = q0 === null ? null : q1 - q0;
        if (rcIn !== null) flushRc += rcIn;
      }
      let upd = null;
      try { if (I && 'lastStyleUpdateSize' in I) upd = I.lastStyleUpdateSize; } catch (x) { upd = null; }
      if (typeof upd === 'number') { updSum += upd; if (upd > updMax) updMax = upd; }
      const rc = recalc();
      list.push({ dt: Math.round(now - t0), ph: ph === null ? null : Math.round(ph * 1000), rc: rc === null || r0 === null ? null : rc - r0, upd: upd, st: st === null ? null : Math.round(st * 1000) / 1000, la: la === null ? null : Math.round(la * 1000) / 1000, fl: rcIn });
      if (idle) { if (now - t0 >= P.idleMs) break; } else if ((ph >= 1 ? ++post > 2 : false) || now - t0 > P.capMs) break;
    }
    const t1 = performance.now();
    mark('fwx:' + arm + ':sw:end');
    const r1 = recalc();
    return {
      stage: idle ? 'idle' : 'flip', frames: f, ms: Math.round(t1 - t0), recalc: r0 === null ? null : r1 - r0, timing: timing,
      styleUs: timing ? Math.round(styleMs * 1000) : null, layoutUs: timing ? Math.round(layoutMs * 1000) : null, flushRc: timing ? flushRc : null,
      updSum: updSum, updMax: updMax, list: list,
    };
  };
  // Diagnostic sets (INFERRED attribution only, not part of the Lean decision): -a pauses every running document animation, -o every running one except sweepDoc.
  const animInv = (all) => all.map((a) => {
    const e = a.effect, t = e && e.target;
    const tg = t ? (t.localName || '') + '.' + String(t.className && t.className.baseVal !== undefined ? t.className.baseVal : t.className || '').slice(0, 40) : null;
    let tm = null;
    try { tm = e ? e.getComputedTiming().iterations : null; } catch (x) { tm = null; }
    return [a.constructor.name, a.animationName || a.transitionProperty || a.id || '', tg, a.playState, tm === Infinity ? 'inf' : tm];
  });
  const sweepArm = async (arm, kind, setCh, timing) => {
    const paused = setCh === '-p';
    X.arm = arm;
    X.suppress = new Set();
    X.created.length = 0;
    const out = { arm: arm, mode: 'timed', stages: [], engaged: false, sw: { kind: kind, paused: paused, timing: timing } };
    out.scrollY = await toBottom();
    await sleep(300);
    const sa = sweepAnims();
    out.sw.ident = sa.ident;
    let toPause = paused ? sa.hit : [];
    if (setCh === '-a' || setCh === '-o') {
      const all = document.getAnimations();
      out.sw.inv = animInv(all);
      toPause = all.filter((a) => a.playState === 'running' && (setCh === '-a' || !sa.hit.includes(a)));
      out.sw.set = setCh;
      out.sw.pausedN = toPause.length;
    }
    if (toPause.length) {
      for (const a of toPause) a.pause();
      await raf(); await raf(); await sleep(250);
    }
    out.sw.states = sa.hit.map((a) => a.playState);
    out.sw.ttnt = I && typeof I.timeToNextAnimationTick === 'function' ? sa.hit.map((a) => { const v = I.timeToNextAnimationTick(a); return v === Infinity ? 'inf' : v; }) : null;
    if (kind === 'idle') {
      out.engaged = true;
      out.stages.push(await swWindow(arm, true, 0, timing));
    } else {
      out.wheels = 0;
      const tw = performance.now();
      while (X.created.length === 0 && out.wheels < 3) {
        wheel(120);
        out.wheels++;
        const t0 = performance.now();
        while (X.created.length === 0 && performance.now() - t0 < 3000) await raf();
        if (X.created.length === 0) { await toBottom(); await sleep(400); }
      }
      if (X.created.length > 0) {
        out.engaged = true;
        out.tracks = X.created.length;
        await raf();
        out.stages.push(await swWindow(arm, false, tw, timing));
      }
    }
    for (const a of toPause) a.play();
    await sleep(900);
    if (kind !== 'idle') {
      X.arm = arm + '~back';
      wheel(-120);
      await sleep(1500);
      X.arm = arm;
    }
    out.nav = nav().className;
    return out;
  };

  const S = X.rs = { cur: null, blockRaf: false, blockTimer: false, fine: null };
  if (P.rs) {
    S.partOf = (n) => {
      const e = n && n.nodeType === 1 ? n : n && n.parentElement;
      const p = e && e.closest ? e.closest('[data-fw]') : null;
      return p ? p.getAttribute('data-fw') : e ? e.localName : 'doc';
    };
    S.add = (k) => { if (S.cur) S.cur.add(k); };
    S.onRecs = (recs) => {
      for (const r of recs) {
        const part = S.partOf(r.target);
        const what = r.type === 'attributes' ? r.attributeName : r.type === 'childList' ? 'childList' : 'text';
        S.add('mut:' + part + '#' + what);
        if (S.fine) {
          const e = r.target.nodeType === 1 ? r.target : r.target.parentElement;
          const fk = part + '|' + (e ? e.localName + '.' + String(e.className && e.className.baseVal !== undefined ? e.className.baseVal : e.className || '').slice(0, 40) : '?') + '|' + what;
          S.fine[fk] = (S.fine[fk] || 0) + 1;
        }
      }
    };
    const site = () => String(new Error().stack || '').split('\n').slice(2, 5).map((l) => l.replace(/https?:\/\/[^\/\s)]+\//g, '').slice(0, 70)).join('>');
    window.requestAnimationFrame = function (cb) {
      if (typeof cb !== 'function') return origRaf(cb);
      const s = site();
      return origRaf(function (t) { if (S.blockRaf) return undefined; S.add('raf:' + s); return cb.call(this, t); });
    };
    const wrapTimer = (orig) => function (fn, ms) {
      if (typeof fn !== 'function') return orig.apply(null, arguments);
      const s = site();
      const rest = Array.prototype.slice.call(arguments, 2);
      return orig.apply(null, [function () { if (S.blockTimer) return undefined; S.add('timer:' + s); return fn.apply(this, arguments); }, ms].concat(rest));
    };
    window.setTimeout = wrapTimer(origST);
    window.setInterval = wrapTimer(origSI);
    for (const m of ['insertRule', 'deleteRule', 'replaceSync', 'replace', 'addRule', 'removeRule']) {
      const f = CSSStyleSheet.prototype[m];
      if (typeof f === 'function') CSSStyleSheet.prototype[m] = function () { S.add('cssom:' + m); return f.apply(this, arguments); };
    }
    S.cn = { ro: 0, io: 0, mql: 0, roT: {}, ioT: {} };
    for (const t of ['scroll', 'scrollend', 'resize', 'pointermove', 'pointerdown', 'pointerup', 'pointerover', 'touchstart', 'touchmove', 'wheel', 'transitionrun', 'transitionstart', 'transitionend', 'transitioncancel', 'animationstart', 'animationiteration', 'animationend', 'animationcancel', 'visibilitychange', 'focusin', 'focusout', 'mouseover', 'mousemove', 'readystatechange']) window.addEventListener(t, () => S.add('ev:' + t), true);
    for (const nm of ['ResizeObserver', 'IntersectionObserver']) {
      const Orig = window[nm];
      if (typeof Orig !== 'function') continue;
      const tg = nm === 'ResizeObserver' ? 'ro' : 'io';
      const obs = Orig.prototype.observe;
      Orig.prototype.observe = function (el) { const k = S.partOf(el); S.cn[tg + 'T'][k] = (S.cn[tg + 'T'][k] || 0) + 1; return obs.apply(this, arguments); };
      window[nm] = class extends Orig { constructor(cb, o) { const s = site(); super(typeof cb === 'function' ? function () { S.add(tg + ':' + s); return cb.apply(this, arguments); } : cb, o); S.cn[tg]++; } };
    }
    const origQM = window.queueMicrotask && window.queueMicrotask.bind(window);
    if (origQM) window.queueMicrotask = function (fn) { if (typeof fn !== 'function') return origQM(fn); const s = site(); return origQM(function () { S.add('micro:' + s); return fn.apply(this, arguments); }); };
    const origMM = window.matchMedia && window.matchMedia.bind(window);
    if (origMM) window.matchMedia = function (q) { const m = origMM(q); S.cn.mql++; try { m.addEventListener('change', () => S.add('mql:' + String(q).slice(0, 40))); } catch (x) { } return m; };
    for (const nm of ['CSSStyleDeclaration', 'CSSStyleProperties']) {
      const proto = window[nm] && window[nm].prototype;
      if (!proto) continue;
      for (const k of Object.getOwnPropertyNames(proto)) {
        const d = Object.getOwnPropertyDescriptor(proto, k);
        if (!d || !d.configurable) continue;
        if (typeof d.value === 'function' && (k === 'setProperty' || k === 'removeProperty')) proto[k] = function () { if (this.parentRule) S.add('cssom:rule.' + k); return d.value.apply(this, arguments); };
        else if (d.set) Object.defineProperty(proto, k, { get: d.get, set(v) { if (this.parentRule) S.add('cssom:rule.set'); d.set.call(this, v); }, configurable: true, enumerable: d.enumerable });
      }
    }
    for (const C of [window.Document, window.ShadowRoot]) {
      const d = C && Object.getOwnPropertyDescriptor(C.prototype, 'adoptedStyleSheets');
      if (d && d.set) Object.defineProperty(C.prototype, 'adoptedStyleSheets', { get: d.get, set(v) { S.add('cssom:adopted'); d.set.call(this, v); }, configurable: true, enumerable: d.enumerable });
    }
    for (const [C, m] of [[Element, 'scrollIntoView'], [Element, 'scrollTo'], [Element, 'scrollBy'], [HTMLElement, 'focus'], [Window, 'scrollTo'], [Window, 'scrollBy']]) {
      const f = C.prototype[m];
      if (typeof f === 'function') C.prototype[m] = function () { S.add('call:' + m); return f.apply(this, arguments); };
    }
  }
  const QSETS = P.qsets || {};
  const isQ = (v) => Object.prototype.hasOwnProperty.call(QSETS, v);
  const MU = X.mute = { set: null, undo: [] };
  const muted = (el, what) => !!(MU.set && el && el.nodeType === 1 && MU.set.has(S.partOf(el) + '#' + what));
  const muteOn = (list) => {
    MU.set = new Set(list);
    const patch = (start, name, make) => {
      let o = start;
      let d = null;
      while (o && !(d = Object.getOwnPropertyDescriptor(o, name))) o = Object.getPrototypeOf(o);
      if (!d) return;
      Object.defineProperty(o, name, make(d));
      MU.undo.push(() => Object.defineProperty(o, name, d));
    };
    const keep = (t, k) => { const v = t[k]; return typeof v === 'function' ? v.bind(t) : v; };
    const attrOf = (k) => 'data-' + String(k).replace(/[A-Z]/g, (c) => '-' + c.toLowerCase());
    patch(Element.prototype, 'setAttribute', (d) => ({ ...d, value: function (n) { return muted(this, String(n).toLowerCase()) ? undefined : d.value.apply(this, arguments); } }));
    patch(Element.prototype, 'removeAttribute', (d) => ({ ...d, value: function (n) { return muted(this, String(n).toLowerCase()) ? undefined : d.value.apply(this, arguments); } }));
    patch(Element.prototype, 'className', (d) => ({ ...d, set(v) { if (!muted(this, 'class')) d.set.call(this, v); } }));
    patch(HTMLElement.prototype, 'tabIndex', (d) => ({ ...d, set(v) { if (!muted(this, 'tabindex')) d.set.call(this, v); } }));
    patch(Element.prototype, 'classList', (d) => ({ ...d, get() {
      const real = d.get.call(this);
      if (!muted(this, 'class')) return real;
      return new Proxy(real, { get(t, k) { return k === 'add' || k === 'remove' || k === 'replace' ? function () { } : k === 'toggle' ? function (x) { return t.contains(x); } : keep(t, k); }, set() { return true; } });
    } }));
    patch(HTMLElement.prototype, 'style', (d) => ({ ...d, get() {
      const real = d.get.call(this);
      if (!muted(this, 'style')) return real;
      return new Proxy(real, { get(t, k) { return k === 'setProperty' || k === 'removeProperty' ? function () { return ''; } : keep(t, k); }, set() { return true; } });
    } }));
    patch(HTMLElement.prototype, 'dataset', (d) => ({ ...d, get() {
      const real = d.get.call(this);
      const el = this;
      return new Proxy(real, { get(t, k) { return keep(t, k); }, set(t, k, v) { if (muted(el, attrOf(k))) return true; t[k] = v; return true; }, deleteProperty(t, k) { if (muted(el, attrOf(k))) return true; delete t[k]; return true; } });
    } }));
  };
  const muteOff = () => {
    MU.set = null;
    while (MU.undo.length) MU.undo.pop()();
  };
  const RS_ARM = /^rs-(warm|idle|flip)(?:-(floor|obs|obsf|blockraf|blocktimer|cancel|hide|empty|smil|nat|pall|pallf|q[a-z]+|pb[a-z]+))?$/;
  const lastSize = () => { try { return I && 'lastStyleUpdateSize' in I ? I.lastStyleUpdateSize : null; } catch (x) { return null; } };
  const tkRead = () => {
    if (!I || typeof I.timeToNextAnimationTick !== 'function') return null;
    const byEl = new Map();
    let m = 0;
    let q = 0;
    let d = 0;
    let a = 0;
    for (const x of X.created) {
      const t = I.timeToNextAnimationTick(x.a);
      if (t === Infinity) d++; else if (t > 0) q++; else m++;
      if (typeof I.acceleratedAnimationsForElement === 'function') {
        if (!byEl.has(x.el)) byEl.set(x.el, I.acceleratedAnimationsForElement(x.el).map((y) => norm(y.property)));
        if (byEl.get(x.el).includes(norm(x.tag.prop))) a++;
      }
    }
    return [m, q, d, a];
  };
  const rsWindow = async (idle, tw, v, kt, ms) => {
    const rec = v === 'obs' || v === 'obsf' || v === 'pallf' || isQ(v);
    const fl = v === 'obsf' || v === 'pallf';
    const dur = P.durationMs;
    const ref = X.created.find((c) => !c.tag.held);
    const phase = () => {
      if (ref) {
        if (ref.a.playState === 'idle') return 9;
        const c = ref.a.currentTime;
        if (c !== null && c !== undefined) return c / dur;
      }
      return (performance.now() - tw) / dur;
    };
    const mo = rec ? new MutationObserver(S.onRecs) : null;
    if (mo) mo.observe(document, { attributes: true, childList: true, subtree: true, characterData: true });
    S.cur = rec ? new Set() : null;
    S.blockRaf = v === 'blockraf';
    S.blockTimer = v === 'blocktimer';
    const frames = [];
    let prev = recalc();
    const layNow = () => (P.lay && I ? ['layoutUpdateCount', 'compositingUpdateCount', 'layerFlushCount'].map((n) => (typeof I[n] === 'function' ? I[n]() : 0)) : null);
    let prevL = layNow();
    const t0 = performance.now();
    let post = 0;
    try {
      for (;;) {
        let mid = null;
        let pz = [];
        let pre = 0;
        await new Promise((res) => origRaf(() => {
          const a0 = recalc();
          pre = a0 !== null && prev !== null ? a0 - prev : 0;
          if (fl) { const a = recalc(); document.getAnimations(); mid = recalc(); if (a !== null && mid > a) pz.push(lastSize()); }
          const ch = new MessageChannel();
          ch.port1.onmessage = () => { ch.port1.close(); res(); };
          ch.port2.postMessage(0);
        }));
        if (mo) S.onRecs(mo.takeRecords());
        const now = performance.now();
        const c = recalc();
        const base = fl && mid !== null ? mid : prev;
        const z = pz;
        if (c !== null && base !== null && c > base) z.push(lastSize());
        const ks = S.cur ? Array.from(S.cur) : [];
        if (S.cur) S.cur = new Set();
        const nl = layNow();
        const y = nl && prevL ? nl.map((x, i) => x - prevL[i]) : undefined;
        prevL = nl;
        const fr = { r: c === null || prev === null ? 0 : c - prev, p: pre, k: ks.map((k) => { let i = kt.indexOf(k); if (i < 0) { kt.push(k); i = kt.length - 1; } return i; }), z: z, g: GH.read ? GH.read() : undefined, y: y };
        const ph = phase();
        if (P.tk && !idle) { fr.u = tkRead(); fr.t = Math.round(now - t0); fr.h = Math.min(9999, Math.round(ph * 1000)); }
        frames.push(fr);
        prev = c;
        if (idle) { if (now - t0 >= (ms || P.rsIdleMs)) break; } else if (P.rsWin) {
          if (frames.length >= P.rsWin || now - t0 > 4 * P.capMs) break;
        } else if ((ph >= 1 ? ++post > 2 : false) || now - t0 > P.capMs) break;
      }
    } finally {
      if (mo) mo.disconnect();
      S.cur = null;
      S.blockRaf = false;
      S.blockTimer = false;
    }
    return frames;
  };
  const PB = {
    pbon: { c: 1, g: 1, p: 1, t: 1, m: 1 }, pboff: { c: 0, g: 0, p: 0, t: 0, m: 0 }, pbconly: { c: 1, g: 0, p: 0, t: 0, m: 0 },
    pbnotk: { c: 1, g: 1, p: 1, t: 0, m: 1 }, pbnoph: { c: 1, g: 1, p: 0, t: 1, m: 1 }, pbnogh: { c: 1, g: 0, p: 1, t: 1, m: 1 },
    pbnomc: { c: 1, g: 1, p: 1, t: 1, m: 0 }, pbpon: { c: 1, g: 1, p: 1, t: 1, m: 1 }, pbpoff: { c: 0, g: 0, p: 0, t: 0, m: 0 },
  };
  // Page::updateRendering counts only after startTrackingRenderingUpdates (Page.cpp:2396@862f17d), so the first read turns the counter on; windows read deltas.
  const RU = { on: false };
  const ruNow = () => {
    try {
      if (!I || typeof I.renderingUpdateCount !== 'function') return null;
      if (!RU.on && typeof I.startTrackingRenderingUpdates === 'function') { I.startTrackingRenderingUpdates(); RU.on = true; }
      return I.renderingUpdateCount();
    } catch (x) { return null; }
  };
  const hop = () => new Promise((res) => { const ch = new MessageChannel(); ch.port1.onmessage = () => { ch.port1.close(); res(); }; ch.port2.postMessage(0); });
  const pbWindow = async (cfg) => {
    const dur = P.durationMs;
    const ref = X.created.find((c) => !c.tag.held);
    const phase = () => {
      if (ref) {
        if (ref.a.playState === 'idle') return 9;
        const c = ref.a.currentTime;
        if (c !== null && c !== undefined) return c / dur;
      }
      return 0;
    };
    const frames = [];
    let n = 0;
    let prev = recalc();
    const c0 = prev;
    const u0 = ruNow();
    const t0 = performance.now();
    while (n < P.rsWin && performance.now() - t0 <= 4 * P.capMs) {
      let pre = 0;
      await new Promise((res) => origRaf(() => {
        if (cfg.c) { const a0 = recalc(); pre = a0 !== null && prev !== null ? a0 - prev : 0; }
        if (!cfg.m) { res(); return; }
        const ch = new MessageChannel();
        ch.port1.onmessage = () => { ch.port1.close(); res(); };
        ch.port2.postMessage(0);
      }));
      n++;
      if (cfg.c) {
        const c = recalc();
        const fr = { r: c === null || prev === null ? 0 : c - prev, p: pre };
        prev = c;
        if (cfg.g && GH.read) fr.g = GH.read();
        if (cfg.t) fr.u = tkRead();
        if (cfg.p) fr.h = Math.min(9999, Math.round(phase() * 1000));
        fr.t = Math.round(performance.now() - t0);
        frames.push(fr);
      }
    }
    if (!cfg.m) await hop();
    const c1 = recalc();
    const u1 = ruNow();
    return { frames: frames, tot: { n: n, r: c0 !== null && c1 !== null ? c1 - c0 : 0, u: u0 !== null && u1 !== null ? u1 - u0 : null, ms: Math.round(performance.now() - t0), src: 'raf' } };
  };
  const pbNoRaf = async () => {
    const c0 = recalc();
    const u0 = ruNow();
    const t0 = performance.now();
    await sleep(1500);
    const c1 = recalc();
    const u1 = ruNow();
    return { frames: [], tot: { n: u0 !== null && u1 !== null ? u1 - u0 : 0, r: c0 !== null && c1 !== null ? c1 - c0 : 0, u: u0 !== null && u1 !== null ? u1 - u0 : null, ms: Math.round(performance.now() - t0), src: 'update' } };
  };
  // Internals::styleChangeType first runs styleScope().flushPendingUpdate() (Internals.cpp:961-966@862f17d).
  const PD = {
    pbdn: { t: 0 }, pbpd: { t: 0 }, pbpdt: { t: 1 },
    pbphide: { t: 0, hide: 'el' }, pbphidep: { t: 0, hide: 'part' }, pbphides: { t: 0, hide: 'set' },
    pbpft: { t: 0, fl: 'T' }, pbpfh: { t: 0, fl: 'H' },
    pbpan: { t: 0, an: 1 },
  };
  const DN = { names: new WeakMap(), nodes: new Map(), cnt: new Map(), ref: null };
  const DTY = ['NoStyleChange', 'AnimationInvalid', 'InlineStyleInvalid', 'InlineStyleChange', 'FullStyleChange'];
  const DCAP = 600;
  const partName = (el) => { let c = el; while (c) { const p = c.closest ? c.closest('[data-fw]') : null; if (p && p !== document.documentElement) return p.getAttribute('data-fw'); if (p) return '-'; const r = c.getRootNode ? c.getRootNode() : null; c = r && r.host ? r.host : null; } return '-'; };
  const nameOf = (n) => {
    let v = DN.names.get(n);
    if (v) return v;
    const ty = n.nodeType;
    if (ty === 9) v = ['d:document', '-'];
    else if (ty === 11) { const h = n.host ? nameOf(n.host) : ['e:?', '-']; v = [h[0] + '::shadow', h[1]]; }
    else if (ty === 3) {
      const p = n.parentNode;
      const pn = p ? nameOf(p) : ['e:?', '-'];
      v = ['t:' + pn[0].slice(2) + '/#text[' + (p ? Array.prototype.indexOf.call(p.childNodes, n) : 0) + ']', pn[1]];
    } else {
      const seg = [];
      let c = n;
      while (c && c.nodeType === 1) {
        const par = c.parentNode;
        const cls = (c.getAttribute('class') || '').split(/\s+/)[0];
        seg.push(c.localName + (c.id ? '#' + c.id : '') + (cls ? '.' + cls : '') + '[' + (par && par.children ? Array.prototype.indexOf.call(par.children, c) : 0) + ']');
        if ((c.hasAttribute('data-fw') && c !== document.documentElement) || c === document.documentElement) break;
        if (par && par.nodeType === 11 && par.host) { seg.push('shadow'); c = par.host; } else c = par;
      }
      const part = partName(n);
      v = ['e:' + part + '|' + seg.reverse().join('>'), part];
    }
    DN.names.set(n, v);
    if (!DN.nodes.has(v[0])) DN.nodes.set(v[0], n);
    return v;
  };
  const dirtRead = (typed, K) => {
    const w0 = performance.now();
    const dirty = [];
    let total = 0;
    const visit = (root) => {
      const tw = document.createTreeWalker(root, 5);
      let n = tw.nextNode();
      while (n) {
        total++;
        if (I.nodeNeedsStyleRecalc(n)) dirty.push(n);
        if (n.nodeType === 1 && n.shadowRoot) { total++; if (I.nodeNeedsStyleRecalc(n.shadowRoot)) dirty.push(n.shadowRoot); visit(n.shadowRoot); }
        n = tw.nextNode();
      }
    };
    total++;
    if (I.nodeNeedsStyleRecalc(document)) dirty.push(document);
    visit(document);
    const capped = dirty.length > DCAP;
    const use = capped ? dirty.slice(0, DCAP) : dirty;
    const ids = [];
    const types = [];
    const seen = new Set();
    const put = (s, t) => {
      if (seen.has(s)) return;
      seen.add(s);
      let i = K.idx.get(s);
      if (i === undefined) { i = K.kt.length; K.kt.push(s); K.idx.set(s, i); }
      ids.push(i);
      types.push(t);
    };
    for (const n of use) {
      let t = -1;
      if (typed) { try { t = DTY.indexOf(I.styleChangeType(n)); } catch (x) { } }
      const v = nameOf(n);
      put(v[0], t);
      if (v[1] !== '-') put('p:' + v[1], t);
    }
    let elN = 0;
    for (const n of dirty) if (n.nodeType === 1) elN++;
    return { ids: ids, types: types, total: total, ms: performance.now() - w0, capped: capped, dirty: dirty.length, elN: elN };
  };
  const mutStart = () => {
    const mu = new Map();
    const bump = (k) => mu.set(k, (mu.get(k) || 0) + 1);
    const mo = new MutationObserver(() => { });
    mo.observe(document, { attributes: true, characterData: true, childList: true, subtree: true });
    const take = () => {
      for (const r of mo.takeRecords()) {
        const n = r.target;
        const nm = n.nodeType === 9 ? 'document' : nameOf(n)[0];
        bump(r.type + (r.attributeName ? ':' + r.attributeName : '') + ' ' + nm);
      }
    };
    const undo = [];
    const wrap = (proto, name) => {
      const orig = proto && proto[name];
      if (typeof orig !== 'function') return;
      proto[name] = function () { bump('api:' + name); return orig.apply(this, arguments); };
      undo.push(() => { proto[name] = orig; });
    };
    if (typeof CSSStyleSheet !== 'undefined') for (const m of ['insertRule', 'deleteRule', 'replace', 'replaceSync']) wrap(CSSStyleSheet.prototype, m);
    if (typeof Element !== 'undefined') for (const m of ['animate', 'setAttribute', 'removeAttribute', 'setAttributeNS']) wrap(Element.prototype, m);
    if (typeof CSSStyleDeclaration !== 'undefined') for (const m of ['setProperty', 'removeProperty']) wrap(CSSStyleDeclaration.prototype, m);
    const stop = () => { take(); mo.disconnect(); for (const u of undo) u(); return mu; };
    return { take: take, stop: stop };
  };
  const dirtWindow = async (cfg, K) => {
    const reps = [];
    let n = 0;
    let prev = recalc();
    const c0 = prev;
    const u0 = ruNow();
    let tl = I.numberOfAnimationTimelineInvalidations();
    let inv = I.styleInvalidationTraversalCount;
    let wms = 0;
    let total = 0;
    let caps = 0;
    const ag = { h: 0, e: 0, hEl: 0, eEl: 0, cyc: 0, maxH: 0, maxE: 0, fl: 0 };
    let prevE = null;
    const mut = mutStart();
    const flush = () => { const a = recalc(); try { getComputedStyle(document.documentElement).getPropertyValue('display'); } catch (x) { } const b = recalc(); return a !== null && b !== null ? b - a : 0; };
    const t0 = performance.now();
    while (n < P.rsWin && performance.now() - t0 <= 4 * P.capMs) {
      let pre = 0;
      let h = null;
      let flH = 0;
      await new Promise((res) => origRaf(() => {
        const a0 = recalc();
        pre = a0 !== null && prev !== null ? a0 - prev : 0;
        h = dirtRead(cfg.t, K);
        if (cfg.fl === 'H') flH = flush();
        const ch = new MessageChannel();
        ch.port1.onmessage = () => { ch.port1.close(); res(); };
        ch.port2.postMessage(0);
      }));
      n++;
      const c = recalc();
      const tl1 = I.numberOfAnimationTimelineInvalidations();
      const inv1 = I.styleInvalidationTraversalCount;
      const sz = I.lastStyleUpdateSize;
      const e = dirtRead(cfg.t, K);
      let flT = 0;
      if (cfg.fl === 'T') flT = flush();
      const fl = flH + flT;
      const fr = [c === null || prev === null ? 0 : c - prev - flH, pre, h.ids, e.ids, tl1 - tl, inv1 - inv, sz];
      if (cfg.t) fr.push(h.types, e.types);
      else if (cfg.fl) fr.push(fl);
      reps.push(fr);
      if (prevE) {
        const ps = new Set(prevE);
        const hs = new Set(h.ids);
        const es = new Set(e.ids);
        for (const i of new Set([...prevE, ...h.ids, ...e.ids])) if (!(ps.has(i) && hs.has(i) && es.has(i))) { const k = K.kt[i]; DN.cnt.set(k, (DN.cnt.get(k) || 0) + 1); ag.cyc++; }
      }
      prevE = e.ids;
      ag.h += h.dirty; ag.e += e.dirty; ag.hEl += h.elN; ag.eEl += e.elN; ag.fl += fl;
      if (h.dirty > ag.maxH) ag.maxH = h.dirty;
      if (e.dirty > ag.maxE) ag.maxE = e.dirty;
      mut.take();
      prev = recalc();
      tl = tl1;
      inv = inv1;
      wms += h.ms + e.ms;
      total = e.total;
      if (h.capped || e.capped) caps++;
    }
    const mu = [...mut.stop().entries()].sort((a, b) => b[1] - a[1]).slice(0, 24);
    const c1 = recalc();
    const u1 = ruNow();
    return { reps: reps, nodes: total, caps: caps, ag: ag, mu: mu, tot: { n: n, r: c0 !== null && c1 !== null ? c1 - c0 : 0, u: u0 !== null && u1 !== null ? u1 - u0 : null, ms: Math.round(performance.now() - t0), src: 'raf', w: Math.round(wms) } };
  };
  const dirtTop = () => {
    let best = null;
    for (const [k, c] of (DN.ref || DN.cnt)) if ((k.startsWith('e:') || k.startsWith('t:')) && (best === null || c > best[1] || (c === best[1] && k < best[0]))) best = [k, c];
    const node = best ? DN.nodes.get(best[0]) : null;
    const el = node ? (node.nodeType === 1 ? node : node.nodeType === 11 ? node.host : node.parentElement) : null;
    const partEl = el && el.closest ? el.closest('[data-fw]') : null;
    let ctrl = null;
    let size = -1;
    for (const p of document.querySelectorAll('[data-fw]')) {
      if (partEl && (p === partEl || p.contains(partEl) || partEl.contains(p))) continue;
      const k = p.querySelectorAll('*').length;
      if (k > size) { size = k; ctrl = p; }
    }
    const nm = (x) => (x ? 'p:' + x.getAttribute('data-fw') : null);
    return { name: best ? best[0] : null, count: best ? best[1] : 0, el: el, part: partEl, ctrl: ctrl, names: { el: best && el ? nameOf(el)[0] : null, part: nm(partEl), ctrl: nm(ctrl) } };
  };
  const animRead = () => {
    const kinds = {};
    const els = [];
    let total = 0;
    let list = [];
    try { list = document.getAnimations(); } catch (x) { }
    for (const a of list) {
      total++;
      let kind = 'none';
      try { kind = a.timeline ? (a.timeline.constructor && a.timeline.constructor.name) || 'timeline' : 'none'; } catch (x) { }
      kinds[kind] = (kinds[kind] || 0) + 1;
      if (els.length >= 64) continue;
      let t = null;
      try { t = a.effect && a.effect.target; } catch (x) { }
      let subj = null;
      try { subj = a.timeline && (a.timeline.subject || a.timeline.source); } catch (x) { }
      els.push([t ? nameOf(t)[0] : '-', kind, a.playState, a.animationName || a.id || '', subj && subj.nodeType === 1 ? nameOf(subj)[0] : '-']);
    }
    return { total: total, kinds: kinds, els: els };
  };
  const creRun = () => new Promise((resolve) => {
    const samples = [];
    const t0 = performance.now();
    let prev = recalc();
    let still = 0;
    const take = () => {
      const now = performance.now();
      const c = recalc();
      const st = { running: 0, paused: 0, finished: 0, idle: 0 };
      let pend = 0;
      for (const x of X.created) { const s = x.a.playState; if (s in st) st[s]++; if (x.a.pending) pend++; }
      const u = tkRead() || [0, 0, 0, 0];
      samples.push([Math.round(now - t0), X.created.length, st.running, st.paused, st.finished, st.idle, pend, u[0], u[1], u[2], u[3], c !== null && prev !== null ? c - prev : 0]);
      prev = c;
      return X.created.length > 0 && st.idle === X.created.length;
    };
    const step = () => {
      if (take()) still++; else still = 0;
      if (still >= 3 || samples.length >= 300 || performance.now() - t0 > 12000) { resolve(samples); return; }
      origRaf(step);
    };
    queueMicrotask(() => { take(); origRaf(step); });
  });
  const rsArm = async (arm, kind, v) => {
    X.arm = arm;
    X.suppress = new Set();
    X.created.length = 0;
    const warm = kind === 'warm';
    const vv = warm ? 'floor' : v || 'floor';
    if (/^q/.test(vv) && !isQ(vv)) throw new Error('unknown writer set ' + vv);
    const kt = [];
    const out = { arm: arm, mode: 'timed', stages: [], engaged: false, rs: { kind: kind, v: vv, frames: [], kt: kt, reps: 0, wins: [], internals: !!(I && typeof I.styleRecalcCount === 'function') } };
    out.scrollY = await toBottom();
    await sleep(300);
    let toPause = [];
    if (vv === 'cancel') {
      const all = document.getAnimations();
      out.rs.pausedN = all.length;
      for (const a of all) { try { a.cancel(); } catch (x) { } }
      await raf(); await raf(); await sleep(250);
      out.rs.stillRunning = document.getAnimations().filter((a) => a.playState === 'running').length;
    } else if (!warm) {
      const glintEl = (a) => !!(a.effect && a.effect.target && a.effect.target.closest && a.effect.target.closest('[data-fw-dash]'));
      const keepGlint = P.gk && vv !== 'pall' && vv !== 'pallf' && !isQ(vv) && !/^pbp/.test(vv);
      toPause = vv === 'nat' ? [] : /^pb/.test(vv) && !/^pbp/.test(vv) ? [] : document.getAnimations().filter((a) => a.playState === 'running' && !(keepGlint && glintEl(a)));
      out.rs.pausedN = toPause.length;
      for (const a of toPause) a.pause();
      await raf(); await raf(); await sleep(250);
      out.rs.stillRunning = document.getAnimations().filter((a) => a.playState === 'running').length;
      out.rs.glintLive = document.getAnimations().filter((a) => a.playState === 'running' && glintEl(a)).length;
    }
    const smilSvgs = vv === 'smil' || vv === 'pall' || vv === 'pallf' || /^pbp/.test(vv) || isQ(vv) ? Array.from(document.querySelectorAll('svg')) : [];
    for (const g of smilSvgs) { try { g.pauseAnimations(); } catch (x) { } }
    if (smilSvgs.length) { out.rs.smilN = smilSvgs.length; await raf(); await raf(); await sleep(250); }
    if (GH.read) {
      const t0 = performance.now();
      while (performance.now() - t0 < 4000) { const g = GH.read(); if (g[0] !== null && g[1] !== null) break; await sleep(100); }
      out.rs.begun = GH.read();
    }
    const pd = PD[vv] || null;
    const K = { kt: kt, idx: new Map() };
    let hideEl = null;
    let hideWas = null;
    const hideSet = [];
    if (pd) { out.rs.dn = []; DN.cnt = new Map(); }
    if (pd && pd.an) out.rs.an = animRead();
    if (pd && pd.hide) {
      const tp = dirtTop();
      const pick = pd.hide === 'el' || pd.hide === 'set' ? tp.el : pd.hide === 'part' ? tp.part : tp.ctrl;
      const el = pick === document.documentElement || pick === document.body ? null : pick;
      out.rs.top = { name: tp.name, count: tp.count };
      if (pick && !el) out.rs.skipped = 'root';
      out.rs.hid = el ? (pd.hide === 'el' || pd.hide === 'set' ? tp.name : tp.names[pd.hide]) : null;
      if (el && pd.hide === 'set') {
        for (const [k, c] of (DN.ref || DN.cnt)) {
          if (!k.startsWith('e:') || 100 * c < 90 * tp.count) continue;
          const nd = DN.nodes.get(k);
          const x = nd ? (nd.nodeType === 1 ? nd : nd.parentElement) : null;
          if (x && x !== el && x !== document.documentElement && x !== document.body) hideSet.push([x, x.style.getPropertyValue('display'), x.style.getPropertyPriority('display')]);
        }
        for (const h of hideSet) h[0].style.setProperty('display', 'none', 'important');
        out.rs.hidSet = hideSet.length + 1;
      }
      if (el) {
        hideEl = el;
        hideWas = [el.style.getPropertyValue('display'), el.style.getPropertyPriority('display')];
        el.style.setProperty('display', 'none', 'important');
        await raf(); await raf(); await sleep(250);
      }
    }
    if (vv === 'hide') { document.body.style.display = 'none'; await raf(); await raf(); await sleep(250); }
    if (vv === 'empty') { document.body.replaceChildren(); await raf(); await raf(); await sleep(250); }
    S.fine = vv === 'obs' ? {} : null;
    if (isQ(vv)) out.rs.muted = QSETS[vv];
    if (kind === 'idle' && pd) {
      out.engaged = out.rs.internals;
      for (let rep = 0; rep < P.rsReps; rep++) {
        const o = await dirtWindow(pd, K);
        out.rs.dn.push({ f: o.reps, nodes: o.nodes, caps: o.caps, ag: o.ag, mu: o.mu });
        (out.rs.pb || (out.rs.pb = [])).push(o.tot);
        out.rs.wins.push(o.tot.n);
        out.rs.reps++;
        await sleep(900);
      }
    } else if (kind === 'idle') {
      out.engaged = out.rs.internals;
      out.rs.frames = await rsWindow(true, 0, vv, kt);
      out.rs.wins.push(out.rs.frames.length);
    } else {
      out.wheels = 0;
      const reps = warm ? 1 : P.rsReps;
      for (let rep = 0; rep < reps; rep++) {
        X.created.length = 0;
        X.creP = null;
        if (vv === 'pbcre') X.onFirst = () => { X.creP = creRun(); };
        const tw = performance.now();
        let w = 0;
        while (X.created.length === 0 && w < 3) {
          wheel(120);
          w++;
          out.wheels++;
          const t0 = performance.now();
          while (X.created.length === 0 && performance.now() - t0 < 3000) await raf();
          if (X.created.length === 0) { await toBottom(); await sleep(400); }
        }
        if (X.created.length === 0 && P.gh) {
          out.rs.miss = (out.rs.miss || 0) + 1;
          if (out.rs.miss > 8) break;
          wheel(-120);
          await sleep(2000);
          await toBottom();
          await sleep(600);
          rep--;
          continue;
        }
        X.onFirst = null;
        if (X.created.length === 0) break;
        out.rs.reps++;
        out.tracks = X.created.length;
        out.engaged = out.rs.internals;
        await raf();
        if (isQ(vv)) muteOn(QSETS[vv]);
        let fr;
        let tot = null;
        try {
          if (vv === 'pbcre') { fr = []; (out.rs.cre || (out.rs.cre = [])).push(await X.creP); } else if (vv === 'pbnoraf') { const o = await pbNoRaf(); fr = o.frames; tot = o.tot; } else if (pd) { const o = await dirtWindow(pd, K); fr = []; tot = o.tot; out.rs.dn.push({ f: o.reps, nodes: o.nodes, caps: o.caps, ag: o.ag, mu: o.mu }); } else if (PB[vv]) { const o = await pbWindow(PB[vv]); fr = o.frames; tot = o.tot; } else fr = await rsWindow(false, tw, vv, kt);
        } finally { if (isQ(vv)) muteOff(); }
        if (!warm) { for (const f of fr) out.rs.frames.push(f); out.rs.wins.push(tot ? tot.n : fr.length); if (tot) (out.rs.pb || (out.rs.pb = [])).push(tot); }
        await sleep(900);
        X.arm = arm + '~back';
        wheel(-120);
        await sleep(1500);
        X.arm = arm;
      }
    }
    if (pd && vv === 'pbpd' && kind === 'flip' && !DN.ref) DN.ref = DN.cnt;
    muteOff();
    if (S.fine) {
      out.rs.fine = Object.entries(S.fine).sort((a, b) => b[1] - a[1]).slice(0, 15);
      S.fine = null;
    }
    if (vv === 'hide') document.body.style.display = '';
    for (const h of hideSet) { h[0].style.removeProperty('display'); if (h[1]) h[0].style.setProperty('display', h[1], h[2]); }
    if (hideEl) { hideEl.style.removeProperty('display'); if (hideWas[0]) hideEl.style.setProperty('display', hideWas[0], hideWas[1]); }
    for (const g of smilSvgs) { try { g.unpauseAnimations(); } catch (x) { } }
    for (const a of toPause) { try { a.play(); } catch (x) { } }
    await sleep(900);
    out.nav = vv === 'empty' ? '' : nav().className;
    return out;
  };

  const BS_SKIP = new Set(['SCRIPT', 'STYLE', 'LINK', 'META', 'NOSCRIPT', 'TEMPLATE', 'TITLE', 'BASE']);
  const B = X.bs = { tag: 0, css: null, parts: [], reads: {}, c: P.bsC || {} };
  const bsRaw = (el) => el.getAttribute('data-fw') || (el.localName + (el.id ? '#' + el.id : ''));
  const bsRendered = (el) => Array.from(el.children).filter((c) => !BS_SKIP.has(c.tagName) && getComputedStyle(c).display !== 'none');
  const bsKids = (el) => {
    let k = bsRendered(el);
    while (k.length === 1 && bsRendered(k[0]).length > 0) k = bsRendered(k[0]);
    return k;
  };
  const bsEnum = (parent) => {
    const sibs = bsKids(parent.el);
    const seen = {};
    return sibs.map((el) => {
      const raw = bsRaw(el);
      const n = seen[raw] || 0;
      seen[raw] = n + 1;
      const id = n ? raw + '[' + n + ']' : raw;
      el.setAttribute('data-fw-bs', String(++B.tag));
      const part = { path: parent.path ? parent.path + ' > ' + id : id, parent: parent.path, el: el, n: B.tag, kids: bsKids(el).length, tag: el.localName };
      B.parts.push(part);
      return part;
    });
  };
  const bsStyle = () => B.css || (B.css = document.head.appendChild(document.createElement('style')));
  const bsRead = async (css, v, hook) => {
    const st = bsStyle();
    await toBottom();
    await sleep(250);
    const toPause = document.getAnimations().filter((a) => a.playState === 'running');
    for (const a of toPause) a.pause();
    await raf(); await raf(); await sleep(200);
    if (hook) hook.on();
    if (css || hook) { st.textContent = css; await raf(); await raf(); await sleep(250); }
    const sm = document.querySelectorAll('animate,animateTransform,animateMotion,set').length;
    const kt = [];
    const t0 = performance.now();
    const fr = await rsWindow(true, 0, v, kt, P.bsIdleMs);
    const r = { sm: sm, frames: fr.length, recalcs: fr.reduce((s, f) => s + f.r, 0), pre: fr.reduce((s, f) => s + (f.p || 0), 0), ms: Math.round(performance.now() - t0), paused: toPause.length };
    if (v === 'obs') { r.kt = kt; r.fr = fr; }
    st.textContent = '';
    if (hook) hook.off();
    for (const a of toPause) { try { a.play(); } catch (x) { } }
    await sleep(300);
    return r;
  };
  const bsRate = (r) => (r.frames === 0 ? 0 : Math.floor((r.recalcs * 100) / r.frames));
  const bsEnds = () => {
    const ok = (r) => r.frames >= B.c.minFrames;
    const full = (B.reads.full || []).filter(ok).map(bsRate);
    const hid = (B.reads.hidden || []).filter(ok).map(bsRate);
    if (!full.length || !hid.length) return null;
    const hi = Math.min(100, ...full);
    const lo = Math.max(0, ...hid);
    return { hi: hi, lo: lo, band: Math.floor(Math.max(0, hi - lo) / B.c.bandDen) };
  };
  const bsHidePart = async (part) => {
    const r = await bsRead('[data-fw-bs="' + part.n + '"]{display:none!important}', 'floor');
    return { path: part.path, parent: part.parent, kids: part.kids, tag: part.tag, frames: r.frames, recalcs: r.recalcs, pre: r.pre, ms: r.ms, paused: r.paused };
  };
  const BS_FEAT = [
    ['sticky', (g) => g('position') === 'sticky'], ['fixed', (g) => g('position') === 'fixed'],
    ['container', (g) => !['', 'normal'].includes(g('container-type'))], ['contentVis', (g) => !['', 'visible'].includes(g('content-visibility'))],
    ['animTimeline', (g) => !['', 'auto'].includes(g('animation-timeline'))], ['scrollTl', (g) => !['', 'none'].includes(g('scroll-timeline-name'))],
    ['viewTl', (g) => !['', 'none'].includes(g('view-timeline-name'))], ['anchor', (g) => !['', 'none'].includes(g('anchor-name'))],
    ['cssAnim', (g) => !['', 'none'].includes(g('animation-name'))], ['willChange', (g) => !['', 'auto'].includes(g('will-change'))],
    ['snap', (g) => !['', 'none'].includes(g('scroll-snap-type'))], ['contain', (g) => !['', 'none'].includes(g('contain'))],
    ['backdrop', (g) => !['', 'none'].includes(g('backdrop-filter'))], ['filter', (g) => !['', 'none'].includes(g('filter'))],
    ['scrollable', (g) => /auto|scroll/.test(g('overflow-x') + g('overflow-y'))], ['ovAnchor', (g) => !['', 'auto'].includes(g('overflow-anchor'))],
  ];
  const BS_TAGS = ['video', 'canvas', 'iframe', 'svg', 'animate', 'animateTransform', 'animateMotion', 'set', 'img', 'picture', 'input', 'textarea', 'marquee', 'dialog'];
  const bsFeatures = (root) => {
    const out = {};
    const add = (k) => { out[k] = (out[k] || 0) + 1; };
    for (const el of [root].concat(Array.from(root.querySelectorAll('*')))) {
      const cs = getComputedStyle(el);
      const g = (p) => cs.getPropertyValue(p);
      for (const [k, f] of BS_FEAT) { try { if (f(g)) add(k); } catch (x) { } }
      if (BS_TAGS.includes(el.localName)) add('<' + el.localName + '>');
      if (el.isContentEditable) add('editable');
    }
    return out;
  };
  const bsRules = () => {
    const out = { sheets: document.styleSheets.length, rules: 0, kinds: {}, hits: {} };
    const pats = { has: /:has\(/, hover: /:hover/, focus: /:focus/, target: /:target/, scrollFn: /\b(scroll|view)\(/, viewTransition: /view-transition/, sticky: /sticky/, timeline: /animation-timeline|scroll-timeline|view-timeline/, container: /container-type|@container/, contentVis: /content-visibility/ };
    const walk = (rules) => {
      for (const r of Array.from(rules)) {
        out.rules++;
        const k = r.constructor && r.constructor.name;
        out.kinds[k] = (out.kinds[k] || 0) + 1;
        const t = r.cssText || '';
        for (const pk in pats) if (pats[pk].test(t)) out.hits[pk] = (out.hits[pk] || 0) + 1;
        if (r.cssRules) walk(r.cssRules);
      }
    };
    for (const sh of Array.from(document.styleSheets)) { try { walk(sh.cssRules); } catch (x) { out.blocked = (out.blocked || 0) + 1; } }
    out.adopted = document.adoptedStyleSheets ? document.adoptedStyleSheets.length : -1;
    return out;
  };
  const BS_RE = /^bs-(facts|full-a|full-b|hidden-a|hidden-b|obs|l1|l2|deep|kill|hold|pause)$/;
  const bsArm = async (arm, kind) => {
    X.arm = arm;
    const out = { arm: arm, mode: 'timed', stages: [], engaged: !!(I && typeof I.styleRecalcCount === 'function'), bs: { kind: kind } };
    const top = { path: '', el: document.body };
    if (kind === 'facts') {
      const l1 = bsEnum(top);
      for (const p of l1) bsEnum(p);
      out.bs.parts = B.parts.map((p) => ({ path: p.path, parent: p.parent, kids: p.kids, tag: p.tag, feat: bsFeatures(p.el) }));
      out.bs.body = bsFeatures(document.body);
      out.bs.rules = bsRules();
      out.bs.cn = { ro: S.cn.ro, io: S.cn.io, mql: S.cn.mql, roT: S.cn.roT, ioT: S.cn.ioT };
      out.bs.active = document.activeElement ? bsRaw(document.activeElement) : null;
    } else if (kind === 'full-a' || kind === 'full-b') {
      const r = await bsRead('', 'floor');
      (B.reads.full = B.reads.full || []).push(r);
      out.bs.read = r;
    } else if (kind === 'hidden-a' || kind === 'hidden-b') {
      const r = await bsRead('body{display:none!important}', 'floor');
      (B.reads.hidden = B.reads.hidden || []).push(r);
      out.bs.read = r;
    } else if (kind === 'obs') {
      const r = await bsRead('', 'obs');
      out.rs = { kind: 'idle', v: 'obs', kt: r.kt, frames: r.fr, reps: 0 };
      out.bs.read = { frames: r.frames, recalcs: r.recalcs, pre: r.pre, ms: r.ms };
    } else if (kind === 'l1' || kind === 'l2') {
      const want = kind === 'l1' ? B.parts.filter((p) => p.parent === '') : B.parts.filter((p) => p.parent !== '');
      out.bs.level = kind;
      out.bs.reads = [];
      for (const p of want.slice(0, 40)) out.bs.reads.push(await bsHidePart(p));
      B.reads[kind] = out.bs.reads;
    } else if (kind === 'kill') {
      out.bs.reads = [];
      const svgs = Array.from(document.querySelectorAll('svg'));
      const smil = { on: () => { for (const g of svgs) { try { g.pauseAnimations(); } catch (x) { } } }, off: () => { for (const g of svgs) { try { g.unpauseAnimations(); } catch (x) { } } } };
      const r = await bsRead('', 'floor', smil);
      out.bs.reads.push({ path: 'kill/smil', parent: 'kill', kids: 0, sm: r.sm, frames: r.frames, recalcs: r.recalcs, pre: r.pre, ms: r.ms, paused: r.paused });
    } else if (kind === 'pause') {
      out.bs.reads = [];
      const all = Array.from(document.querySelectorAll('svg'));
      const dash = all.filter((g) => !!g.closest('[data-fw-dash]'));
      const other = all.filter((g) => !g.closest('[data-fw-dash]'));
      const secs = {};
      for (const g of all) { const a = g.closest('[data-fw]'); const k = a ? a.getAttribute('data-fw') : '-'; secs[k] = (secs[k] || 0) + 1; }
      out.bs.info = { total: all.length, dash: dash.length, other: other.length, secs: secs, smilNow: document.querySelectorAll('animate,animateTransform,animateMotion,set').length };
      for (const grp of [['dash', dash], ['other', other]]) {
        const list = grp[1];
        const hook = { on: () => { for (const g of list) { try { g.pauseAnimations(); } catch (x) { } } }, off: () => { for (const g of list) { try { g.unpauseAnimations(); } catch (x) { } } } };
        const r = await bsRead('', 'floor', hook);
        out.bs.reads.push({ path: 'pause/' + grp[0], parent: 'pause', kids: 0, n: list.length, sm: r.sm, frames: r.frames, recalcs: r.recalcs, pre: r.pre, ms: r.ms, paused: r.paused });
      }
    } else if (kind === 'hold') {
      out.bs.reads = [];
      const at = B.parts.find((p) => p.path === B.at);
      out.bs.at = B.at || null;
      if (at) {
        const hideSet = (nodes) => nodes.map((p) => '[data-fw-bs="' + p.n + '"]{display:none!important}').join('');
        let sib = [];
        for (let c = at; c; c = B.parts.find((p) => p.path === c.parent)) sib = sib.concat(B.parts.filter((p) => p.parent === c.parent && p !== c));
        const kids = B.parts.filter((p) => p.parent === at.path);
        const arms = kids.map((k) => [k.path, kids.filter((o) => o !== k)]).concat([['bare', kids]]);
        for (const a of arms) {
          const r = await bsRead(hideSet(sib.concat(a[1])), 'floor');
          out.bs.reads.push({ path: 'only/' + a[0], parent: 'only', kids: 0, sm: r.sm, frames: r.frames, recalcs: r.recalcs, pre: r.pre, ms: r.ms, paused: r.paused });
        }
      }
    } else if (kind === 'deep') {
      out.bs.reads = [];
      const e = bsEnds();
      out.bs.ends = e;
      const dropped = (r) => e && r.frames >= B.c.minFrames && bsRate(r) <= e.lo + e.band;
      const lowest = (rs) => rs.filter(dropped).sort((a, b) => bsRate(a) - bsRate(b))[0];
      let cur = lowest(B.reads.l1 || []);
      let at = cur;
      if (cur) cur = lowest((B.reads.l2 || []).filter((r) => r.parent === cur.path));
      for (let d = 0; cur && d < 6 && out.bs.reads.length < 24; d++) {
        at = cur;
        const part = B.parts.find((p) => p.path === cur.path);
        if (!part || part.kids === 0) break;
        const kids = bsEnum(part);
        const rs = [];
        for (const k of kids) rs.push(await bsHidePart(k));
        for (const r of rs) out.bs.reads.push(r);
        cur = lowest(rs);
      }
      out.bs.at = at ? at.path : null;
      B.at = out.bs.at;
    }
    await sleep(100);
    return out;
  };

  const timedArm = async (arm) => {
    X.arm = arm;
    X.suppress = armSet(arm);
    X.created.length = 0;
    const out = { arm: arm, mode: 'timed', stages: [], engaged: false };
    out.scrollY = await toBottom();
    await sleep(300);
    if (arm === 'idle') {
      if (P.mid) {
        const m = await midWindow(arm, true, performance.now());
        out.stages.push(m.stage);
        out.samples = m.samples;
        out.frames = m.frames;
        out.listed = m.listed;
      } else out.stages.push(await windowFrames(arm, 'flip', P.windowMs, 0, false));
      out.nav = nav().className;
      return out;
    }
    out.wheels = 0;
    if (P.mid) out.layBefore = layersBefore();
    const tw = performance.now();
    while (X.created.length === 0 && out.wheels < 3) {
      wheel(120);
      out.wheels++;
      const t0 = performance.now();
      while (X.created.length === 0 && performance.now() - t0 < 3000) await raf();
      if (X.created.length === 0) { await toBottom(); await sleep(400); }
    }
    if (X.created.length > 0) {
      out.engaged = true;
      out.tracks = X.created.length;
      // The engine that runs a slow frame clock (WebKitTestRunner) can finish the tween before the mid-window readout: read the tracks
      // at creation and one frame later, each with its play state, so a reading of a settled (idle) track can be told apart.
      out.early = [{ at: 'create', rows: readout() }];
      if (P.mid) out.pre = flushSamples();
      const e0 = performance.now();
      await raf();
      out.early.push({ at: 'raf1', dt: Math.round(performance.now() - e0), rows: readout(), docAnims: document.getAnimations().length });
      if (P.mid) {
        const m = await midWindow(arm, false, tw);
        out.stages.push(m.stage);
        out.samples = m.samples;
        out.frames = m.frames;
        out.listed = m.listed;
        out.rendered = X.created.map((c) => !!(c.el.getClientRects && c.el.getClientRects().length > 0));
      } else {
        out.stages.push(await windowFrames(arm, 'flip', P.windowMs, 0, true));
        out.table = X.table;
        out.docAnims = X.docAnims;
        X.table = null;
      }
    }
    await sleep(900);
    X.arm = arm + '~back';
    wheel(-120);
    await sleep(1500);
    X.arm = arm;
    out.nav = nav().className;
    return out;
  };

  X.run = async () => {
    const t = {};
    try {
      if (I && typeof I.startTrackingStyleRecalcs === 'function') I.startTrackingStyleRecalcs();
      for (let i = 0; i < 100 && !(window.__fw && window.__fw.hydrated); i++) await sleep(50);
      await sleep(P.settleMs);
      if (P.mode === 'scrubbed') { window.scrollTo(0, document.documentElement.scrollHeight); await sleep(1800); } else { await toBottom(); await sleep(2800); }
      t.facts = { ua: navigator.userAgent, w: innerWidth, h: innerHeight, dpr: devicePixelRatio, mode: P.mode, hydrated: !!(window.__fw && window.__fw.hydrated), panel: !!document.querySelector('[data-fw="morph-panel"]') };
      for (const arm of P.arms) {
        const swm = SW_ARM.exec(arm);
        const rsm = RS_ARM.exec(arm);
        const bsm = BS_RE.exec(arm);
        let r;
        if (P.gh && rsm) {
          try { r = await rsArm(arm, rsm[1], rsm[2] || ''); } catch (e) { muteOff(); X.errors.push(arm + ': ' + String((e && e.message) || e)); continue; }
        } else r = bsm ? await bsArm(arm, bsm[1]) : rsm ? await rsArm(arm, rsm[1], rsm[2] || '') : swm ? await sweepArm(arm, swm[1], swm[2] || '', !!swm[3]) : P.mode === 'scrubbed' ? await scrubbedArm(arm) : await timedArm(arm);
        X.rows.push(r);
      }
    } catch (e) {
      X.errors.push(String((e && e.message) || e) + ' ' + String((e && e.stack) || '').slice(0, 400));
    }
    t.rows = X.rows;
    t.tags = X.tags;
    t.errors = X.errors;
    t.accelProps = X.accelProps || null;
    return t;
  };
}

export function probeSource({ mode, arms = ARMS, sweepFrames = 60, windowMs = 560, settleMs = 2500, mid = null, durationMs = 680, capMs = 3000, listAnims = true, idleMs = 1000, rsReps = 4, rsWin = 0, tk = false, rsIdleMs = 2500, bsIdleMs = 2000, bsC = BS_C, gh = false, gk = false, lay = false, qsets = null } = {}) {
  if (mode !== 'scrubbed' && mode !== 'timed') throw new Error(`mode ${mode}`);
  if (mid && mode !== 'timed') throw new Error('mid readouts are for the timed mode');
  return `(${pageProbe.toString()})(${JSON.stringify({ mode, arms, sweepFrames, windowMs, settleMs, props: PROPS, mid, durationMs, capMs, listAnims, idleMs, rs: arms.some((a) => /^(rs|bs)-/.test(String(a))), rsReps, rsWin, tk, rsIdleMs, bsIdleMs, bsC, gh, gk, lay, qsets })});`;
}
