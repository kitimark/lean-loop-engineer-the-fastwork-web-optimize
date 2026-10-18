// Code that runs inside the page. Everything exported as a function here is self-contained (no closure over module
// scope), because the engines serialise it with toString() and evaluate it in the page. No decisions are made here:
// the page only reports what it sees. The pass/fail rule is in verdict.mjs.

/**
 * Init script, injected before any page script in both arms and both engines. It pins `Date` (new Date(), Date.now())
 * to one instant and seeds Math.random (mulberry32), so the countdown and any random layout choice are identical
 * between the two arms and between runs. It leaves timers, requestAnimationFrame and performance.now native.
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

/** Wait until the arm has settled: fonts, hydration (rewrite) or the hero splash (original), then 3 frames and 300 ms. */
export async function waitReady(arg) {
  const { site, capMs } = arg;
  const t0 = performance.now();
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  try { await document.fonts.ready; } catch { /* no font API */ }
  let ready = false;
  let splash = null;
  if (site === 'rewrite') {
    while (!(window.__fw && window.__fw.hydrated) && performance.now() - t0 < capMs) await sleep(50);
    ready = !!(window.__fw && window.__fw.hydrated);
  } else {
    const done = () => !!document.querySelector('.hero-track .hero.is-ring-splash-done');
    while (!done() && performance.now() - t0 < capMs) await sleep(50);
    splash = done();
    ready = !!document.querySelector('.hero-track .hero');
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
 *    top and wait out running finite animations, so every part is collected from the top in the same state.
 *  - kind "overlay", stage "open" (overlays.drawer, overlays.signup): click `trigger`, wait for `ready` (the caller then settles and collects that one part). The caller collects that one part, then runs stage "close": click `close`,
 *    wait until `gone` no longer matches, so the next read starts from the closed page.
 */
export async function prepareInPage(arg) {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  const running = () => document.getAnimations().filter((a) => {
    const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
    return t && Number.isFinite(t.iterations) && a.playState !== 'finished' && a.playState !== 'idle';
  }).length;
  const idle = async (capMs) => {
    const t1 = performance.now();
    while (running() > 0 && performance.now() - t1 < capMs) await sleep(50);
  };
  const t0 = performance.now();
  const found = [];
  if (arg.stage === 'ready') {
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
    await idle(arg.capMs);
  } else if (arg.stage === 'open') {
    for (const step of arg.steps) {
      const btn = document.querySelector(step.trigger);
      if (!btn) { found.push(false); continue; }
      btn.click();
      while (!document.querySelector(step.ready) && performance.now() - t0 < 5000) await sleep(50);
      found.push(!!document.querySelector(step.ready));
      // no fixed sleep: the caller's settle wait (settleInPage) ends on the dialog's enter animation being finished and quiet
      await frame();
    }
  } else if (arg.stage === 'close') {
    for (const step of arg.steps) {
      const btn = document.querySelector(step.close);
      if (btn) btn.click();
      while (document.querySelector(step.gone) && performance.now() - t0 < 5000) await sleep(50);
      found.push(!document.querySelector(step.gone));
      for (let i = 0; i < 2; i++) await frame();
      await sleep(100);
    }
  }
  return found;
}

/**
 * After a live resize: one frame, so the engine has applied it. Nothing else is waited for here: the gate's settle wait
 * (settleInPage, Fw.Gate.Settle) follows and ends on events (two real frames, nothing running, the probed values quiet),
 * so the fixed 600 ms sleep and the drain of every finite animation are gone (sweeps-speed note, 10-18).
 */
export async function waitResize() {
  await Promise.race([new Promise((r) => requestAnimationFrame(() => r())), new Promise((r) => setTimeout(r, 250))]);
  return true;
}

/**
 * The gate's settle wait (Fw.Gate.Settle). Runs after load and after each resize, with the pointer parked, before anything is
 * collected. One observation per real requestAnimationFrame (a 250 ms timer only keeps the loop alive if no frame comes; it does
 * not count as a frame): the finite animations and transitions under the probed subtree (`getAnimations`), the real frames
 * since the wait began, the run of quiet frames (every probed box, transform number and opacity within eps of the frame before:
 * this is what sees a requestAnimationFrame-driven lerp that `getAnimations` does not list), and whether the pointer is inside a
 * probed element. It stops at the first settled observation or when the budget is spent. The outcome is NOT decided here: the
 * runner applies Lean's `wait` (settle.mjs waitTrace) to the returned trace.
 * arg: { policy: {minFrames, minStable, eps, timeoutMs}, roots: [selector], hoverCapable: boolean } (an environment that cannot
 * hover never reports the pointer inside: `:hover` can stay matched there after a touch, but no hover rule applies).
 * The two predicates between the markers are replayed against the Lean golden by test/settle.test.mjs (extracted from this text).
 */
export async function settleInPage(arg) {
  const p = arg.policy;
  // <settled>
  const settled = (q, o) => o.running === 0 && q.minFrames <= o.frames && q.minStable <= o.stable && !o.hoverInside;
  // </settled>
  // <quiet>
  const quiet = (eps, u, v) => u.length === v.length && u.every((a, i) => Math.abs(a - v[i]) <= eps);
  // </quiet>
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

/**
 * Bring a part into view: scroll the first of its nodes that the engine has skipped (content-visibility:auto) to the middle of
 * the viewport, then wait two real frames so the engine applies the new visibility. Returns how many nodes were skipped before
 * the scroll. The gate then settles and reads the part again (Lean Fw.Gate.Settle.view).
 * arg: { roots: [selector] }
 */
export async function bringInPage(arg) {
  const skipped = (el) => { try { return !!el.checkVisibility && el.checkVisibility() && !el.checkVisibility({ contentVisibilityAuto: true }); } catch { return false; } };
  const all = [];
  for (const sel of arg.roots) for (const el of Array.from(document.querySelectorAll(sel)).slice(0, 64)) all.push(el);
  const hit = all.filter(skipped);
  if (hit.length > 0) hit[0].scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
  for (let i = 0; i < 2; i++) await new Promise((r) => { requestAnimationFrame(() => r()); setTimeout(r, 250); });
  return { skippedBefore: hit.length, scrollY: window.scrollY };
}

/** Back to the top of the page after bringInPage, then two real frames. */
export async function scrollTopInPage() {
  window.scrollTo(0, 0);
  for (let i = 0; i < 2; i++) await new Promise((r) => { requestAnimationFrame(() => r()); setTimeout(r, 250); });
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
    for (const { role, selector, rect: wantRect } of roles) {
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
        return skippedOf.get(el) ? { rect, style, skipped: true } : { rect, style };
      });
      out.parts[pid][role] = { count: els.length, declared: Array.from(declared).sort(), items: arg.props ? items : [] };
    }
  }
  return out;
}

