
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

/** Lean Fw.Gate.Freeze.freezeAct; returns { finished, paused }. */
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
    } catch { }
  }
  return { finished, paused };
}

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

/** arg: { site, capMs, holdMs, readyToMs, graceMs }. */
export async function waitReady(arg) {
  const { site, capMs } = arg;
  const K = window.__fwk;
  const t0 = performance.now();
  const sleep = K ? K.sleep : (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = K ? K.frame : () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  try { await document.fonts.ready; } catch { }
  let ready = false;
  let splash = null;
  if (K) {
    const r0 = await K.real(0);
    if (site === 'rewrite') {
      while (!(window.__fw && window.__fw.hydrated) && (await K.real(50)) - r0 < capMs) { }
    } else {
      while (document.readyState !== 'complete' && (await K.real(50)) - r0 < capMs) { }
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
    let awaited = K.freeze().finished;
    for (let i = 0; i < 3; i++) { await frame(); awaited += K.freeze().finished; }
    await sleep(300);
    awaited += K.freeze().finished;
    await K.holdTo(arg.readyToMs);
    awaited += K.freeze().finished;
    const left = document.getAnimations().filter((a) => {
      const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
      return t && a.timeline instanceof DocumentTimeline && Number.isFinite(t.iterations) && (a.playState === 'running' || a.playState === 'pending');
    }).length;
    const fw0 = window.__fw;
    return {
      ready, splash, fwMode: fw0 ? fw0.mode : null, hydrationErrors: fw0 ? (fw0.hydrationErrors ? fw0.hydrationErrors.length ?? fw0.hydrationErrors : 0) : null,
      animations: { waitedMs: Math.round(performance.now() - t0), awaited, passes: 1, left },
    };
  }
  const finiteRunning = () => document.getAnimations().filter((a) => {
    const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
    return t && a.timeline instanceof DocumentTimeline && Number.isFinite(t.iterations) && (a.playState === 'running' || a.playState === 'pending');
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

/** arg: { stage, steps, capMs, maxFrames }; returns { found, idle }. */
export async function prepareInPage(arg) {
  const K = window.__fwk;
  const sleep = K ? K.sleep : (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = K ? K.frame : () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleep(250)]);
  const running = () => document.getAnimations().filter((a) => {
    const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
    return t && a.timeline instanceof DocumentTimeline && Number.isFinite(t.iterations) && a.playState !== 'finished' && a.playState !== 'idle';
  }).length;
  const realFrame = K ? K.frame : () => new Promise((resolve) => {
    let done = false;
    requestAnimationFrame(() => { if (!done) { done = true; resolve(true); } });
    setTimeout(() => { if (!done) { done = true; resolve(false); } }, 250);
  });
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
    if (arg.stage === undefined) return found;
    return { found, idle: await idle(arg.capMs, arg.maxFrames) };
  } else if (arg.stage === 'open') {
    for (const step of arg.steps) {
      const btn = document.querySelector(step.trigger);
      if (!btn) { found.push(false); continue; }
      btn.click();
      while (!document.querySelector(step.ready) && performance.now() - t0 < 5000) { if (K) K.freeze(); await sleep(50); }
      found.push(!!document.querySelector(step.ready));
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

export function freezeInPage() {
  const K = window.__fwk;
  if (K) K.freeze();
  return true;
}

export async function waitResize(arg) {
  const K = window.__fwk;
  if (K && arg && arg.holdTo !== undefined) {
    for (let i = 0; i < 4; i++) await K.frame();
    K.freeze();
    await K.holdTo(arg.holdTo);
    K.freeze();
    return true;
  }
  await Promise.race([new Promise((r) => requestAnimationFrame(() => r())), new Promise((r) => setTimeout(r, 250))]);
  return true;
}

/** arg: { policy: {minFrames, minStable, eps, timeoutMs, maxFrames}, roots: [selector], hoverCapable: boolean }; returns the trace. */
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
  // <counts>
  const counts = (a) => a.onDocument && a.finite && a.state !== 'finished' && a.state !== 'idle';
  // </counts>
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
        if (t && counts({ onDocument: a.timeline instanceof DocumentTimeline, finite: Number.isFinite(t.iterations), state: a.playState })) anims.add(a);
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
  const K = window.__fwk;
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

/** arg: { roots: [selector] }; returns how many nodes were skipped before the scroll. */
export async function bringInPage(arg) {
  const skipped = (el) => { try { return !!el.checkVisibility && el.checkVisibility() && !el.checkVisibility({ contentVisibilityAuto: true }); } catch { return false; } };
  const all = [];
  for (const sel of arg.roots) for (const el of Array.from(document.querySelectorAll(sel)).slice(0, 64)) all.push(el);
  const hit = all.filter(skipped);
  if (hit.length > 0) window.scrollTo({ top: Math.max(0, all[0].getBoundingClientRect().top + window.scrollY), left: 0, behavior: 'instant' });
  const K = window.__fwk;
  for (let i = 0; i < 2; i++) await (K ? K.frame() : new Promise((r) => { requestAnimationFrame(() => r()); setTimeout(r, 250); }));
  if (K) K.freeze();
  return { skippedBefore: hit.length, scrollY: window.scrollY };
}

export async function scrollTopInPage() {
  window.scrollTo(0, 0);
  const K = window.__fwk;
  for (let i = 0; i < 2; i++) await (K ? K.frame() : new Promise((r) => { requestAnimationFrame(() => r()); setTimeout(r, 250); }));
  if (K) K.freeze();
  return window.scrollY;
}

/** arg: { site, conditions, neutral, dprWanted, widthWanted, parts, props, filter }. */
export function collectInPage(arg) {
  const mm = (q) => { try { return window.matchMedia(q).matches; } catch { return null; } };
  const out = { truth: {}, truthLegacy: {}, neutral: {}, observed: {}, viewport: {}, parts: {} };

  out.viewport = {
    innerWidth: window.innerWidth,
    innerHeight: window.innerHeight,
    clientWidth: document.documentElement.clientWidth,
    clientHeight: document.documentElement.clientHeight,
    scrollWidth: document.documentElement.scrollWidth,
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
    try { walk(sheet.cssRules); } catch { }
  }
  const matches = (el, sel) => { try { return el.matches(sel); } catch { return false; } };
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
        const layoutDep = [];
        for (const n of names) {
          if (!n.startsWith('margin')) continue;
          try {
            const v = el.computedStyleMap().get(n);
            if (!(v instanceof CSSUnitValue && v.unit === 'px')) layoutDep.push(n);
          } catch (e) { }
        }
        const cs = getComputedStyle(el);
        const style = {};
        for (const n of names) style[n] = cs.getPropertyValue(n);
        const inline = (inlineNames || []).filter((n) => el.style.getPropertyValue(n) !== '');
        const item = { rect, style };
        if (inline.length > 0) item.inline = inline;
        if (layoutDep.length > 0) item.layoutDep = layoutDep;
        if (skippedOf.get(el)) item.skipped = true;
        return item;
      });
      out.parts[pid][role] = { count: els.length, declared: Array.from(declared).sort(), items: arg.props ? items : [] };
    }
  }
  return out;
}

