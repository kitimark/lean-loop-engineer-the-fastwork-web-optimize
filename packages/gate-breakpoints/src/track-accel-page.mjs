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
      out.stages.push(await windowFrames(arm, 'flip', P.windowMs, 0, false));
      out.nav = nav().className;
      return out;
    }
    wheel(120);
    const t0 = performance.now();
    while (X.created.length === 0 && performance.now() - t0 < 2500) await raf();
    if (X.created.length > 0) {
      out.engaged = true;
      out.tracks = X.created.length;
      out.stages.push(await windowFrames(arm, 'flip', P.windowMs, 0, true));
      out.table = X.table;
      out.docAnims = X.docAnims;
      X.table = null;
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
export function probeSource({ mode, arms = ARMS, sweepFrames = 60, windowMs = 560, settleMs = 2500 } = {}) {
  if (mode !== 'scrubbed' && mode !== 'timed') throw new Error(`mode ${mode}`);
  return `(${pageProbe.toString()})(${JSON.stringify({ mode, arms, sweepFrames, windowMs, settleMs, props: PROPS })});`;
}
