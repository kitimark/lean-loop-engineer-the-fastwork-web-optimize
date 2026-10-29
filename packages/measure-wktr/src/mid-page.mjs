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
// With `P.mid` (timed, task geom-webkit-midflip) the arms are read at those phases of the tween instead (state, pending, accelerated,
// threaded flag, `timeToNextAnimationTick`, per-frame recalc counts) before the settle cancel.

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
    // Task geom-recalc-bisect: the candidates geom-recalc-source left unwrapped. Each logs a key in the frame it runs (only while S.cur is set).
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
  const RS_ARM = /^rs-(warm|idle|flip)(?:-(floor|obs|obsf|blockraf|blocktimer|cancel|hide|empty))?$/;
  const lastSize = () => { try { return I && 'lastStyleUpdateSize' in I ? I.lastStyleUpdateSize : null; } catch (x) { return null; } };
  const rsWindow = async (idle, tw, v, kt, ms) => {
    const rec = v === 'obs' || v === 'obsf';
    const fl = v === 'obsf';
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
        frames.push({ r: c === null || prev === null ? 0 : c - prev, p: pre, k: ks.map((k) => { let i = kt.indexOf(k); if (i < 0) { kt.push(k); i = kt.length - 1; } return i; }), z: z });
        prev = c;
        if (idle) { if (now - t0 >= (ms || P.rsIdleMs)) break; } else {
          const ph = phase();
          if ((ph >= 1 ? ++post > 2 : false) || now - t0 > P.capMs) break;
        }
      }
    } finally {
      if (mo) mo.disconnect();
      S.cur = null;
      S.blockRaf = false;
      S.blockTimer = false;
    }
    return frames;
  };
  const rsArm = async (arm, kind, v) => {
    X.arm = arm;
    X.suppress = new Set();
    X.created.length = 0;
    const warm = kind === 'warm';
    const vv = warm ? 'floor' : v || 'floor';
    const kt = [];
    const out = { arm: arm, mode: 'timed', stages: [], engaged: false, rs: { kind: kind, v: vv, frames: [], kt: kt, reps: 0, internals: !!(I && typeof I.styleRecalcCount === 'function') } };
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
      toPause = document.getAnimations().filter((a) => a.playState === 'running');
      out.rs.pausedN = toPause.length;
      for (const a of toPause) a.pause();
      await raf(); await raf(); await sleep(250);
      out.rs.stillRunning = document.getAnimations().filter((a) => a.playState === 'running').length;
    }
    if (vv === 'hide') { document.body.style.display = 'none'; await raf(); await raf(); await sleep(250); }
    if (vv === 'empty') { document.body.replaceChildren(); await raf(); await raf(); await sleep(250); }
    S.fine = vv === 'obs' ? {} : null;
    if (kind === 'idle') {
      out.engaged = out.rs.internals;
      out.rs.frames = await rsWindow(true, 0, vv, kt);
    } else {
      out.wheels = 0;
      const reps = warm ? 1 : P.rsReps;
      for (let rep = 0; rep < reps; rep++) {
        X.created.length = 0;
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
        if (X.created.length === 0) break;
        out.rs.reps++;
        out.tracks = X.created.length;
        out.engaged = out.rs.internals;
        await raf();
        const fr = await rsWindow(false, tw, vv, kt);
        if (!warm) for (const f of fr) out.rs.frames.push(f);
        await sleep(900);
        X.arm = arm + '~back';
        wheel(-120);
        await sleep(1500);
        X.arm = arm;
      }
    }
    if (S.fine) {
      out.rs.fine = Object.entries(S.fine).sort((a, b) => b[1] - a[1]).slice(0, 15);
      S.fine = null;
    }
    if (vv === 'hide') document.body.style.display = '';
    for (const a of toPause) { try { a.play(); } catch (x) { } }
    await sleep(900);
    out.nav = vv === 'empty' ? '' : nav().className;
    return out;
  };

  // Task geom-recalc-bisect. Arms bs-*: idle, every running animation paused, one subtree hidden at a time by a probe stylesheet
  // (display:none on [data-fw-bs=n], a tag this probe sets on the subtree root; the part id is its data-fw, else tag#id, repeated ids
  // get [n]). The page only schedules which subtrees to read (stand-in of Lean cls/descend); the verdict is decided offline.
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
      // Stage 2 (Lean carrier): run r2 (40808745010) read 15 features removed one at a time; only the SMIL pause dropped the rate in 3 of 3 jobs, so only it stays as the control.
      out.bs.reads = [];
      const svgs = Array.from(document.querySelectorAll('svg'));
      const smil = { on: () => { for (const g of svgs) { try { g.pauseAnimations(); } catch (x) { } } }, off: () => { for (const g of svgs) { try { g.unpauseAnimations(); } catch (x) { } } } };
      const r = await bsRead('', 'floor', smil);
      out.bs.reads.push({ path: 'kill/smil', parent: 'kill', kids: 0, sm: r.sm, frames: r.frames, recalcs: r.recalcs, pre: r.pre, ms: r.ms, paused: r.paused });
    } else if (kind === 'pause') {
      // Stage 3 (Lean pauser): only the timelines of one svg group are paused; 'dash' are the svgs inside [data-fw-dash] (the secure-network glint), 'other' all the rest.
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
      // Stage 2 (Lean holder): only one child of the part the hide descent ended at stays shown (its ancestors' other children and its siblings hidden); 'bare' hides all its children.
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
        const r = bsm ? await bsArm(arm, bsm[1]) : rsm ? await rsArm(arm, rsm[1], rsm[2] || '') : swm ? await sweepArm(arm, swm[1], swm[2] || '', !!swm[3]) : P.mode === 'scrubbed' ? await scrubbedArm(arm) : await timedArm(arm);
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

/** The init script for one mode. params: mode, arms, sweepFrames, windowMs, settleMs. */
export function probeSource({ mode, arms = ARMS, sweepFrames = 60, windowMs = 560, settleMs = 2500, mid = null, durationMs = 680, capMs = 3000, listAnims = true, idleMs = 1000, rsReps = 4, rsIdleMs = 2500, bsIdleMs = 2000, bsC = BS_C } = {}) {
  if (mode !== 'scrubbed' && mode !== 'timed') throw new Error(`mode ${mode}`);
  if (mid && mode !== 'timed') throw new Error('mid readouts are for the timed mode');
  return `(${pageProbe.toString()})(${JSON.stringify({ mode, arms, sweepFrames, windowMs, settleMs, props: PROPS, mid, durationMs, capMs, listAnims, idleMs, rs: arms.some((a) => /^(rs|bs)-/.test(String(a))), rsReps, rsIdleMs, bsIdleMs, bsC })});`;
}
