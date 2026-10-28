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

export const PROPS = ['translate', 'scale', 'transform', 'opacity', 'filter', 'backdrop-filter'];
export const ARMS = ['all', ...PROPS.map((p) => `no-${p}`), 'none', 'idle', 'all-again'];

/** The tags are sealed in the page by the wrapper; the node side reads them back with this exact shape. */
export const SCHEMA = 'fw.track-accel/1';

function pageProbe(P) {
  const X = (window.__fwx = { created: [], suppress: new Set(), mode: P.mode, arm: null, n: 0, rows: [], tags: [], table: null, errors: [] });
  const CSSN = { backdropFilter: 'backdrop-filter' };
  const NONKEY = new Set(['offset', 'easing', 'composite']);
  const origAnimate = Element.prototype.animate;
  Element.prototype.animate = function (frames, opts) {
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

  const sleep = (ms) => new Promise((r) => window.setTimeout(r, ms));
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
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

  // Mid-flip readout (WebKitTestRunner): the frame clock there is slow, so the samples are taken by phase (the reference track's own
  // currentTime over the tween length), from the rAF callbacks and from a short timer poll, never by frame count.
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
      const rows = readout().map((r) => ({ id: r.id, s: r.state, p: r.pending ? 1 : 0, a: r.accel ? 1 : 0, th: r.threaded, t: r.ttnt, c: r.cur === null || r.cur === undefined ? null : Math.round(r.cur) }));
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
    const poll = () => { if (!alive) return; check(); window.setTimeout(poll, 4); };
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
        const r = P.mode === 'scrubbed' ? await scrubbedArm(arm) : await timedArm(arm);
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
export function probeSource({ mode, arms = ARMS, sweepFrames = 60, windowMs = 560, settleMs = 2500, mid = null, durationMs = 680, capMs = 3000, listAnims = true } = {}) {
  if (mode !== 'scrubbed' && mode !== 'timed') throw new Error(`mode ${mode}`);
  if (mid && mode !== 'timed') throw new Error('mid readouts are for the timed mode');
  return `(${pageProbe.toString()})(${JSON.stringify({ mode, arms, sweepFrames, windowMs, settleMs, props: PROPS, mid, durationMs, capMs, listAnims })});`;
}
