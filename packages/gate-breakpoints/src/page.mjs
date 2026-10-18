// Code that runs inside the page. Everything exported as a function here is self-contained (no closure over module
// scope), because the engines serialise it with toString() and evaluate it in the page. No decisions are made here:
// the page only reports what it sees. The pass/fail rule is in verdict.mjs.

/**
 * Init script, injected before any page script in both arms and both engines. It pins `Date` (new Date(), Date.now())
 * to one instant and seeds Math.random (mulberry32), so the countdown and any random layout choice are identical
 * between the two arms and between runs. It leaves timers, requestAnimationFrame and performance.now native (the frozen-clock
 * gate run, src/freeze.mjs, has the engine's page clock replace them before this script runs; Date then stays pinned here).
 */
export const PIN_SRC = `(() => {
  const FIXED = Date.parse('2026-10-01T00:00:00+07:00');
  const RealDate = Date;
  function FakeDate(...a) {
    if (!new.target) return new RealDate(FIXED).toString();
    return a.length === 0 ? new RealDate(FIXED) : new RealDate(...a);
  }
  FakeDate.prototype = RealDate.prototype;
  FakeDate.now = () => FIXED;
  FakeDate.parse = RealDate.parse;
  FakeDate.UTC = RealDate.UTC;
  Object.defineProperty(FakeDate, 'name', { value: 'Date' });
  window.Date = FakeDate;
  let s = 0x9e3779b9 >>> 0;
  Math.random = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
})();`;

/**
 * The freeze pass over the document's CSS and Web animations (Lean Fw.Gate.Freeze.freezeAct), run by the frozen-clock gate
 * before every observation: a finite animation or transition jumps to its end (`finish()`), an infinite one is paused at the
 * middle of its first iteration. The timer-restarted strokes and copy animations, the resize-triggered transitions and the
 * infinite floats of hero.cue.* are then at a fixed state whenever and however fast the machine took them there. Animations of a
 * non-document timeline (scroll-driven) and of a non-numeric duration are left alone. Self-contained (it is serialised into the
 * page by KIT_SRC). Returns { finished, paused } for the record.
 * The text between the markers is replayed against the Lean golden file (test/freeze.test.mjs).
 */
export function freezeAnimations() {
  // <freeze>
  const target = (t) => (Number.isFinite(t.iterations) ? t.delay + t.iterations * t.duration : t.delay + Math.floor(t.duration / 2));
  // </freeze>
  let finished = 0, paused = 0;
  for (const a of document.getAnimations()) {
    try {
      if (!(a.timeline instanceof DocumentTimeline)) continue;
      const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
      if (!t || typeof t.duration !== 'number') continue;
      if (Number.isFinite(t.iterations)) {
        if (a.playState !== 'finished' && a.playState !== 'idle') { a.finish(); finished++; }
      } else {
        a.pause();
        a.currentTime = target(t);
        paused++;
      }
    } catch { /* an animation that cannot be finished or paused stays as it is, and shows as running */ }
  }
  return { finished, paused };
}

/**
 * Init script of the frozen-clock gate run (after PIN_SRC): the page-side kit `window.__fwk` used by every function below when
 * present. `window.__fwClock(op, n)` is the engine's exposed binding (engines.mjs): 'step' advances the page clock by n ms and
 * answers whether a real rendering frame was confirmed; 'holdTo' advances it to the absolute fake time n; 'real' waits n real ms
 * (for what the fake clock cannot drive: network, hydration) and answers the real time. Nothing else moves the clock.
 */
export const KIT_SRC = `(() => {
  const clock = (op, n) => window.__fwClock(op, n);
  window.__fwk = {
    freeze: ${freezeAnimations.toString()},
    step: (ms) => clock('step', ms),
    sleep: (ms) => clock('step', ms),
    holdTo: (abs) => clock('holdTo', abs),
    real: (ms) => clock('real', ms),
    frame: async () => { const p = new Promise((r) => requestAnimationFrame(() => r())); const ok = await clock('step', 16); await p; return ok; },
  };
})();`;

/**
 * Wait until the arm has settled: fonts, hydration (rewrite) or the hero splash (original), then 3 frames and 300 ms.
 * With the frozen-clock kit (arg.holdMs, arg.readyToMs, arg.graceMs): wait in REAL time for what the fake clock cannot drive (the
 * rewrite's hydration flag; the original has none, so a real grace), hold the clock to the absolute instant holdMs, wait for the
 * original's splash in fake steps, freeze the animations, 3 frames and 300 ms of steps, then hold to readyToMs: both arms leave
 * here at the same fake instant.
 */
export async function waitReady(arg) {
  const { site, capMs } = arg;
  const K = window.__fwk;
  const t0 = performance.now();
  const sleep = K ? K.sleep : (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = K ? K.frame : () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  try { await document.fonts.ready; } catch { /* no font API */ }
  let ready = false;
  let splash = null;
  if (K) {
    const r0 = await K.real(0);
    if (site === 'rewrite') {
      while (!(window.__fw && window.__fw.hydrated) && (await K.real(50)) - r0 < capMs) { /* real time only */ }
    } else {
      while (document.readyState !== 'complete' && (await K.real(50)) - r0 < capMs) { /* real time only */ }
      await K.real(arg.graceMs);
    }
    await K.holdTo(arg.holdMs);
  }
  if (site === 'rewrite') {
    while (!(window.__fw && window.__fw.hydrated) && performance.now() - t0 < capMs) await sleep(50);
    ready = !!(window.__fw && window.__fw.hydrated);
  } else {
    const done = () => !!document.querySelector('.hero-track .hero.is-ring-splash-done');
    while (!done() && performance.now() - t0 < capMs) await sleep(50);
    splash = done();
    ready = !!document.querySelector('.hero-track .hero');
  }
  if (K) {
    // frozen clock: finish the finite animations and pause the infinite ones, give them 3 frames and 300 ms to act on that
    // (a handler of `animationend` runs, a timer restarts a stroke), freeze again, and hold to the common instant
    let awaited = K.freeze().finished;
    for (let i = 0; i < 3; i++) { await frame(); awaited += K.freeze().finished; }
    await sleep(300);
    awaited += K.freeze().finished;
    await K.holdTo(arg.readyToMs);
    awaited += K.freeze().finished;
    const left = document.getAnimations().filter((a) => {
      const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
      return t && Number.isFinite(t.iterations) && (a.playState === 'running' || a.playState === 'pending');
    }).length;
    const fw0 = window.__fw;
    return {
      ready, splash, fwMode: fw0 ? fw0.mode : null, hydrationErrors: fw0 ? (fw0.hydrationErrors ? fw0.hydrationErrors.length ?? fw0.hydrationErrors : 0) : null,
      animations: { waitedMs: Math.round(performance.now() - t0), awaited, passes: 1, left },
    };
  }
  // Every FINITE CSS animation or transition has finished, so the page is compared in its end state and never in a tail
  // (infinite ones, e.g. the call-to-action orbit, are ignored). Parts mount at different times (the original's people
  // card after hydration, long after the hero splash), so a transition can start after the first quiet moment: the wait
  // is repeated after the 3 frames and 300 ms until a whole pass finds none. Bounded by capMs; no tolerance anywhere.
  const finiteRunning = () => document.getAnimations().filter((a) => {
    const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
    return t && Number.isFinite(t.iterations) && (a.playState === 'running' || a.playState === 'pending');
  });
  const t1 = performance.now();
  let awaited = 0;
  let passes = 0;
  while (performance.now() - t1 < capMs) {
    let list = finiteRunning();
    while (list.length > 0 && performance.now() - t1 < capMs) {
      awaited += list.length;
      const left = capMs - (performance.now() - t1);
      await Promise.race([Promise.all(list.map((a) => a.finished.catch(() => {}))), sleep(left)]);
      list = finiteRunning();
    }
    for (let i = 0; i < 3; i++) await frame();
    await sleep(300);
    passes++;
    if (finiteRunning().length === 0) break;
  }
  const fw = window.__fw;
  return {
    ready, splash, fwMode: fw ? fw.mode : null, hydrationErrors: fw ? (fw.hydrationErrors ? fw.hydrationErrors.length ?? fw.hydrationErrors : 0) : null,
    animations: { waitedMs: Math.round(performance.now() - t1), awaited, passes, left: finiteRunning().length },
  };
}

/**
 * Part-declared preparation of an arm (anchors.json `prepare`, only for parts a run covers): the ONE mechanism for page states
 * that exist only after an action. `arg.steps` are the steps to run and `arg.stage` says which half. Self-contained (it is
 * serialised into the page); reports what it saw, decides nothing.
 *  - kind "mount", stage "ready" (morph.countdown, morph.columns, morph.panel): some elements exist only after the page has
 *    been near them (the morph panel mounts when the platform section is within 200% of the viewport and stays mounted). Per
 *    step: scroll so the `scrollNear` element's top is 1.5 viewports below the fold, wait for `waitFor`, then return to the
 *    top and wait out running finite animations (the idle wait, bounded by the arm cap and the frame budget: Lean
 *    Fw.Gate.Settle.idlePolicy), so every part is collected from the top in the same state. Returns { found, idle: trace }.
 *  - kind "overlay", stage "open" (overlays.drawer, overlays.signup): click `trigger`, wait for `ready` (the caller then settles and collects that one part). The caller collects that one part, then runs stage "close": click `close`,
 *    wait until `gone` no longer matches, so the next read starts from the closed page.
 */
export async function prepareInPage(arg) {
  const K = window.__fwk; // the frozen-clock kit (KIT_SRC), absent in a native run
  const sleep = K ? K.sleep : (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = K ? K.frame : () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  const running = () => document.getAnimations().filter((a) => {
    const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
    return t && Number.isFinite(t.iterations) && a.playState !== 'finished' && a.playState !== 'idle';
  }).length;
  // a real frame (true) or the 250 ms keep-alive (false)
  const realFrame = K ? K.frame : () => new Promise((resolve) => {
    let done = false;
    requestAnimationFrame(() => { if (!done) { done = true; resolve(true); } });
    setTimeout(() => { if (!done) { done = true; resolve(false); } }, 250);
  });
  // The idle wait (Lean Fw.Gate.Settle.idlePolicy, gate-shard-balance): one observation per real frame until no finite
  // animation of the document runs, or the time cap or the frame budget is spent. Returns the trace; the runner applies Lean's
  // `wait` to it and folds the outcome into the sample (an unsettled idle wait makes the sample unsettled: Settle.fold).
  const idle = async (capMs, maxFrames) => {
    const t1 = performance.now();
    const trace = [];
    let frames = 0;
    if (K) K.freeze();
    for (;;) {
      const obs = { running: running(), frames, stable: 0, hoverInside: false, t: Math.round(performance.now() - t1) };
      trace.push(obs);
      if (obs.running === 0 || capMs < obs.t || maxFrames < obs.frames) return trace;
      if (await realFrame()) frames++;
      if (K) K.freeze();
    }
  };
  const t0 = performance.now();
  const found = [];
  if (arg.stage === 'ready' || arg.stage === undefined) {
    for (const step of arg.steps) {
      const near = document.querySelector(step.scrollNear);
      if (near) {
        const top = near.getBoundingClientRect().top + window.scrollY;
        window.scrollTo({ top: Math.max(0, top - window.innerHeight * 1.5), behavior: 'instant' });
      }
      for (let i = 0; i < 3; i++) await frame();
      while (!document.querySelector(step.waitFor) && performance.now() - t0 < arg.capMs) await sleep(50);
      found.push(!!document.querySelector(step.waitFor));
    }
    window.scrollTo({ top: 0, behavior: 'instant' });
    for (let i = 0; i < 3; i++) await frame();
    await sleep(300);
    if (K) K.freeze();
    if (arg.stage === undefined) return found; // a caller outside the gate run (packages/snapshot-extract): the mount steps alone, as on main
    return { found, idle: await idle(arg.capMs, arg.maxFrames) };
  } else if (arg.stage === 'open') {
    for (const step of arg.steps) {
      const btn = document.querySelector(step.trigger);
      if (!btn) { found.push(false); continue; }
      btn.click();
      while (!document.querySelector(step.ready) && performance.now() - t0 < 5000) { if (K) K.freeze(); await sleep(50); }
      found.push(!!document.querySelector(step.ready));
      // no fixed sleep: the caller's settle wait (settleInPage) ends on the dialog's enter animation being finished and quiet
      await frame();
    }
  } else if (arg.stage === 'close') {
    for (const step of arg.steps) {
      const btn = document.querySelector(step.close);
      if (btn) btn.click();
      while (document.querySelector(step.gone) && performance.now() - t0 < 5000) { if (K) K.freeze(); await sleep(50); }
      found.push(!document.querySelector(step.gone));
      for (let i = 0; i < 2; i++) await frame();
      await sleep(100);
    }
  }
  return found;
}

/**
 * Original only: the morph panel is mounted lazily. A one-way flag is set the first time the platform section comes within
 * 200 % of the viewport (IntersectionObserver, 2.DyWL8TcE.js:13080-13089), so this scrolls there, waits for the first
 * column, and returns to the top. Self-contained (it is serialised into the page). Reports what it saw; decides nothing.
 * Not used by the gate run (anchors.json `prepare` is); packages/snapshot-extract imports it, so it stays as on main.
 */
export async function mountPanel() {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  const sel = '.start-selling-morph-col';
  const y0 = window.scrollY;
  const target = document.querySelector('#platform');
  if (target) {
    const r = target.getBoundingClientRect();
    window.scrollTo({ top: window.scrollY + r.top - window.innerHeight / 2, behavior: 'instant' });
  }
  const t0 = performance.now();
  while (!document.querySelector(sel) && performance.now() - t0 < 8000) { await frame(); await sleep(50); }
  const mounted = document.querySelectorAll(sel).length;
  window.scrollTo({ top: y0, behavior: 'instant' });
  for (let i = 0; i < 3; i++) await frame();
  await sleep(300);
  return { target: !!target, mounted, scrollY: window.scrollY };
}

/** Freeze the document's animations now: the page-side half of an observation at an instant (freeze.mjs observeAt). */
export function freezeInPage() {
  const K = window.__fwk;
  if (K) K.freeze();
  return true;
}

/**
 * After a live resize: one frame, so the engine has applied it. Nothing else is waited for here: the gate's settle wait
 * (settleInPage, Fw.Gate.Settle) follows and ends on events (two real frames, nothing running, the probed values quiet),
 * so the fixed 600 ms sleep and the drain of every finite animation are gone (sweeps-speed note, 10-18).
 */
export async function waitResize(arg) {
  const K = window.__fwk;
  if (K && arg && arg.holdTo !== undefined) {
    // frozen clock: four steps (the resize observers fire on the first real frame and what they schedule runs on the next ones),
    // then to the absolute instant every arm reaches (run.mjs: the stop base plus the post-resize advance), then the freeze
    for (let i = 0; i < 4; i++) await K.frame();
    K.freeze();
    await K.holdTo(arg.holdTo);
    K.freeze();
    return true;
  }
  await Promise.race([new Promise((r) => requestAnimationFrame(() => r())), new Promise((r) => setTimeout(r, 250))]);
  return true;
}

/**
 * The gate's settle wait (Fw.Gate.Settle). Runs after load and after each resize, with the pointer parked, before anything is
 * collected. One observation per real requestAnimationFrame (a 250 ms timer only keeps the loop alive if no frame comes; it does
 * not count as a frame): the finite animations and transitions under the probed subtree (`getAnimations`), the real frames
 * since the wait began, the run of quiet frames (every probed box, transform number and opacity within eps of the frame before:
 * this is what sees a requestAnimationFrame-driven lerp that `getAnimations` does not list), and whether the pointer is inside a
 * probed element. It stops at the first settled observation or when the budget (time or frames, Lean `spent`) is spent. The outcome is NOT decided here: the
 * runner applies Lean's `wait` (settle.mjs waitTrace) to the returned trace.
 * arg: { policy: {minFrames, minStable, eps, timeoutMs, maxFrames}, roots: [selector], hoverCapable: boolean } (an environment that cannot
 * hover never reports the pointer inside: `:hover` can stay matched there after a touch, but no hover rule applies).
 * The three predicates between the markers are replayed against the Lean golden by test/settle.test.mjs (extracted from this text).
 */
export async function settleInPage(arg) {
  const p = arg.policy;
  // <settled>
  const settled = (q, o) => o.running === 0 && q.minFrames <= o.frames && q.minStable <= o.stable && !o.hoverInside;
  // </settled>
  // <quiet>
  const quiet = (eps, u, v) => u.length === v.length && u.every((a, i) => Math.abs(a - v[i]) <= eps);
  // </quiet>
  // <spent>
  const spent = (q, o) => q.timeoutMs < o.t || q.maxFrames < o.frames;
  // </spent>
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
  const K = window.__fwk; // the frozen-clock kit (KIT_SRC): one step of the fake clock is one frame, animations are frozen at each
  const nextFrame = K ? K.frame : () => new Promise((resolve) => {
    let done = false;
    requestAnimationFrame(() => { if (!done) { done = true; resolve(true); } });
    setTimeout(() => { if (!done) { done = true; resolve(false); } }, 250);
  });
  const t0 = performance.now();
  const trace = [];
  if (K) K.freeze();
  let prev = observe().sig;
  let frames = 0, stable = 0;
  for (;;) {
    const gotFrame = await nextFrame();
    if (K) K.freeze();
    const o = observe();
    if (gotFrame) {
      frames++;
      stable = quiet(p.eps, prev, o.sig) ? stable + 1 : 0;
      prev = o.sig;
    }
    const obs = { running: o.running, frames, stable, hoverInside: o.hover, t: Math.round(performance.now() - t0) };
    trace.push(obs);
    if (settled(p, obs) || spent(p, obs)) break;
  }
  return { trace };
}

/**
 * Bring a part into view: scroll the part's first root to the top of the viewport (when one of its nodes is skipped by
 * content-visibility:auto), then wait two real frames so the engine applies the new visibility. Returns how many nodes were skipped before
 * the scroll. The gate then settles and reads the part again (Lean Fw.Gate.Settle.view).
 * arg: { roots: [selector] }
 */
export async function bringInPage(arg) {
  const skipped = (el) => { try { return !!el.checkVisibility && el.checkVisibility() && !el.checkVisibility({ contentVisibilityAuto: true }); } catch { return false; } };
  const all = [];
  for (const sel of arg.roots) for (const el of Array.from(document.querySelectorAll(sel)).slice(0, 64)) all.push(el);
  const hit = all.filter(skipped);
  // The part's first root goes to the viewport top in both arms: a scroll-driven value (a view timeline on the root) then reads the
  // same progress in each arm, whatever the page heights are (run 39086375181: centring the first skipped node gave WebKit
  // 0.4746 vs 0.3702 on --commission-shrink).
  if (hit.length > 0) window.scrollTo({ top: Math.max(0, all[0].getBoundingClientRect().top + window.scrollY), left: 0, behavior: 'instant' });
  const K = window.__fwk;
  for (let i = 0; i < 2; i++) await (K ? K.frame() : new Promise((r) => { requestAnimationFrame(() => r()); setTimeout(r, 250); }));
  if (K) K.freeze();
  return { skippedBefore: hit.length, scrollY: window.scrollY };
}

/** Back to the top of the page after bringInPage, then two real frames. */
export async function scrollTopInPage() {
  window.scrollTo(0, 0);
  const K = window.__fwk;
  for (let i = 0; i < 2; i++) await (K ? K.frame() : new Promise((r) => { requestAnimationFrame(() => r()); setTimeout(r, 250); }));
  if (K) K.freeze();
  return window.scrollY;
}

/**
 * Collect the raw facts of one arm in its current state.
 * arg: { site: 'orig'|'rewrite', conditions: [{tsId, css, legacyCss}], neutral: [{tsId, css}], dprWanted, widthWanted,
 *        parts: { [partId]: [{ role, selector, rect }] }, props: { [partId]: { [role]: string[] } } | null, filter: string }
 * With props == null, only the declared property names per role are reported (the scan that fixes the property lists).
 */
export function collectInPage(arg) {
  const mm = (q) => { try { return window.matchMedia(q).matches; } catch { return null; } };
  const out = { truth: {}, truthLegacy: {}, neutral: {}, observed: {}, viewport: {}, parts: {} };

  out.viewport = {
    innerWidth: window.innerWidth,
    innerHeight: window.innerHeight,
    clientWidth: document.documentElement.clientWidth,
    clientHeight: document.documentElement.clientHeight,
    screenWidth: window.screen.width,
    screenHeight: window.screen.height,
    dpr: window.devicePixelRatio,
    scrollY: window.scrollY,
  };
  out.observed = {
    hoverHover: mm('(hover: hover)'),
    hoverNone: mm('(hover: none)'),
    pointerFine: mm('(pointer: fine)'),
    pointerCoarse: mm('(pointer: coarse)'),
    pointerNone: mm('(pointer: none)'),
    reducedMotion: mm('(prefers-reduced-motion: reduce)'),
    dark: mm('(prefers-color-scheme: dark)'),
    widthExact: mm(`(width: ${arg.widthWanted}px)`),
    print: mm('print'),
    forcedColors: mm('(forced-colors: active)'),
  };
  for (const c of arg.conditions) {
    out.truth[c.tsId] = mm(c.css);
    out.truthLegacy[c.tsId] = c.legacyCss === null ? null : mm(c.legacyCss);
  }
  for (const n of arg.neutral) out.neutral[n.tsId] = mm(n.css);

  const filter = new RegExp(arg.filter);
  const rules = [];
  const walk = (list) => {
    for (const r of list) {
      if (r.selectorText !== undefined) { if (filter.test(r.selectorText)) rules.push(r); }
      else if (r.cssRules) walk(r.cssRules);
    }
  };
  for (const sheet of Array.from(document.styleSheets)) {
    try { walk(sheet.cssRules); } catch { /* cross-origin sheet: not part of either arm */ }
  }
  const matches = (el, sel) => { try { return el.matches(sel); } catch { return false; } };
  // Whether the engine has the node's subtree skipped (content-visibility:auto, off screen): rendered by the DOM
  // (checkVisibility() true) but not by contentVisibilityAuto. Read for every probed node BEFORE any rect or style is read: a
  // style read forces a skipped subtree's lock open for the length of the read (premise cv.read-forces-lock). An engine without
  // the option reports nothing skipped. Premise cv.skip-flag. Only when the caller asks (`flagSkipped`: the probes, which load
  // fresh): bringing a part into view starts its animations (commission typing), and a sweep carries that state to all later stops
  // (CI run 39084163586: 111 of 114 samples of one sweep ended unsettled), so sweeps read as before.
  const skippedOf = new Map();
  if (arg.props && arg.flagSkipped) {
    for (const roles of Object.values(arg.parts)) {
      for (const { selector } of roles) {
        for (const el of Array.from(document.querySelectorAll(selector)).slice(0, 64)) {
          let sk = false;
          try { sk = !!el.checkVisibility && el.checkVisibility() && !el.checkVisibility({ contentVisibilityAuto: true }); } catch { sk = false; }
          skippedOf.set(el, sk);
        }
      }
    }
  }

  for (const [pid, roles] of Object.entries(arg.parts)) {
    out.parts[pid] = {};
    for (const { role, selector, rect: wantRect, inline: inlineNames } of roles) {
      const els = Array.from(document.querySelectorAll(selector)).slice(0, 64);
      const declared = new Set();
      const items = els.map((el) => {
        for (const r of rules) {
          if (!matches(el, r.selectorText)) continue;
          for (let i = 0; i < r.style.length; i++) declared.add(r.style[i]);
        }
        const r = el.getBoundingClientRect();
        const rect = wantRect ? { x: r.x, y: r.y, w: r.width, h: r.height } : null;
        const names = arg.props && arg.props[pid] && arg.props[pid][role] ? arg.props[pid][role] : [];
        const cs = getComputedStyle(el);
        const style = {};
        for (const n of names) style[n] = cs.getPropertyValue(n);
        // An item read in a skipped subtree carries `skipped: true`: the gate brings its part into view and reads again
        // (run.mjs, Lean Fw.Gate.Settle.view); one still skipped then is masked by summary.mjs maskNotRendered.
        // `inline`: the properties of the role's anchors.json `skipIfInline` that the element's own style attribute sets (a hover
        // raise written by a script); Lean (Fw.Gate.cmpAt) leaves such a property out of that pair on the original's element only.
        const inline = (inlineNames || []).filter((n) => el.style.getPropertyValue(n) !== '');
        const item = { rect, style };
        if (inline.length > 0) item.inline = inline;
        if (skippedOf.get(el)) item.skipped = true;
        return item;
      });
      out.parts[pid][role] = { count: els.length, declared: Array.from(declared).sort(), items: arg.props ? items : [] };
    }
  }
  return out;
}

