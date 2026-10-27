import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PKG, siteDist, startServer } from './serve.mjs';
import { PIN_SRC } from './page.mjs';
import { loadFlipCell } from './flip-cell.mjs';

export const GOLDEN = resolve(PKG, '../contracts/golden/morph-geom-timed.jsonl');

export function loadVerify(path = GOLDEN) {
  const lines = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  const v = lines.find((l) => l.fn === 'verify')?.out;
  if (!v) throw new Error(`no verify line in ${path}`);
  return v;
}

// Verdicts: TS stand-ins for Fw.Parts.MorphGeom.quietOk, keptWithin/keptAll and pushesTaken (lean/Fw/Parts/MorphGeomVerify.lean), replayed against the golden.
export function judgeQuiet(base, tol, frames) {
  return frames.length > 0 && frames.every((f) => f.moving === 0 && f.width - base <= tol && base - f.width <= tol);
}

export function keptWithin(frame, dt, before, after) {
  return after - before - dt <= frame && before + dt - after <= frame;
}

export function judgeKept(frame, lost, pairs) {
  return lost === 0 && pairs.length > 0 && pairs.every((p) => keptWithin(frame, p.dt, p.before, p.after));
}

export function judgeTrace(events) {
  let pending = false;
  for (const e of events) {
    if (e === 'push') {
      if (pending) return false;
      pending = true;
    } else if (e === 'take') {
      if (!pending) return false;
      pending = false;
    }
  }
  return !pending && events.includes('push');
}

// The mutation each fix gets: the reading that must fail when it is reverted (Fw.Parts.MorphGeom.Mutation).
export const MUTATION_RUN = { A1: 'cell', A3b: 'cell', A3c: 'cell', A4: 'verify', A3a: 'verify', A5: 'verify' };
export const MUTATION_OWNER = {
  A1: (b) => /^column\d+: not beside|^columns:|^image\d+:/.test(b),
  A3b: (b) => /^earn:/.test(b),
  A3c: (b) => /^lang:/.test(b),
};

// ---- page side: serialised into the page (init script, or page.evaluate), no closure over Node values ----

export function installFlipProbe() {
  if (window.__fwFlipProbe) return;
  const trace = [];
  const state = { deny: false, armed: 0 };
  const ids = new WeakMap();
  let nid = 0;
  const idOf = (e) => {
    let i = ids.get(e);
    if (i === undefined) {
      i = nid++;
      ids.set(e, i);
    }
    return i;
  };
  const frames = [];
  let running = false;
  window.__fwTakeTrace = (ev) => {
    trace.push({ ...ev, at: performance.now() });
    if (ev.kind === 'push') {
      state.deny = ev.to < ev.from;
      state.armed = 1;
    }
  };
  const roots = () => [document.querySelector('[data-fw="nav"]'), document.querySelector('[data-fw="morph-columns"]')];
  const anims = () => {
    const out = [];
    const seen = new Set();
    if (typeof CSSAnimation === 'undefined') return out;
    for (const root of roots()) {
      if (!root || !root.getAnimations) continue;
      for (const a of root.getAnimations({ subtree: true })) {
        if (!(a instanceof CSSAnimation) || !a.effect || !a.effect.target) continue;
        const id = idOf(a.effect.target);
        const key = `${id}|${a.animationName}|${a.effect.pseudoElement || ''}`;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({ key, t: Number(a.currentTime), paused: a.playState === 'paused' });
      }
    }
    return out;
  };
  const sample = (ts) => {
    if (!running) return;
    const nav = document.querySelector('[data-fw="nav"]');
    const tr = nav && typeof CSSTransition !== 'undefined' ? nav.getAnimations().filter((a) => a instanceof CSSTransition).map((a) => a.transitionProperty) : [];
    frames.push({
      ts,
      flip: document.documentElement.classList.contains('is-flip'),
      w: nav ? nav.getBoundingClientRect().width : null,
      bg: nav ? getComputedStyle(nav).backgroundColor : '',
      tr,
      anims: anims(),
    });
    requestAnimationFrame(sample);
  };
  window.__fwFlipProbe = {
    start() {
      frames.length = 0;
      trace.length = 0;
      running = true;
      requestAnimationFrame(sample);
    },
    stop() {
      running = false;
      return { frames: frames.slice(), trace: trace.slice() };
    },
    navWidth() {
      return document.querySelector('[data-fw="nav"]').getBoundingClientRect().width;
    },
    state,
  };
}

// Reverts one fix at run time: A1/A3b/A3c/A4 edit the stylesheet rule the fix added, A3a drops the animation-time restore, A5 refuses the close take and every retry.
export function mutatePage(name) {
  const rules = [];
  const walk = (list) => {
    for (const r of list) {
      if (r.style) rules.push(r);
      if (r.cssRules) walk(r.cssRules);
    }
  };
  for (const s of document.styleSheets) {
    try {
      walk(s.cssRules);
    } catch {
      continue;
    }
  }
  const has = (r, re) => re.test(r.selectorText || '');
  let n = 0;
  if (name === 'A1') {
    for (const r of rules) if (has(r, /data-mg=["']?Ub["']?\]/) && r.style.display === 'flex') (r.style.setProperty('display', 'block'), n++);
  } else if (name === 'A3b') {
    for (const r of rules) if (has(r, /is-flip/) && has(r, /data-mg=["']?earn["']?\]/) && r.style.transform === 'none') (r.style.removeProperty('transform'), n++);
  } else if (name === 'A3c') {
    for (const r of rules) {
      if (has(r, /is-flip/) && has(r, /data-mg=["']?actions["']?\]/) && r.style.top === '0px') {
        r.style.setProperty('top', 'calc(50% - 24px)');
        r.style.removeProperty('bottom');
        n++;
      }
    }
  } else if (name === 'A4') {
    for (const r of rules) if (has(r, /is-flip-quiet/) && r.style.transition !== '') (r.style.removeProperty('transition'), n++);
  } else if (name === 'A3a') {
    const d = Object.getOwnPropertyDescriptor(Animation.prototype, 'currentTime');
    Object.defineProperty(CSSAnimation.prototype, 'currentTime', { configurable: true, get() { return d.get.call(this); }, set() {} });
    n = 1;
  } else if (name === 'A5') {
    const nav = document.querySelector('[data-fw="nav"]');
    const real = nav.classList.contains.bind(nav.classList);
    const st = window.__fwFlipProbe.state;
    Object.defineProperty(nav.classList, 'contains', {
      configurable: true,
      value(c) {
        if (c !== 'is-on-dark') return real(c);
        if (st.deny) return false;
        if (st.armed > 0) {
          st.armed--;
          return real(c);
        }
        return false;
      },
    });
    n = 1;
  } else {
    throw new Error(`unknown mutation ${name}`);
  }
  return n;
}

// ---- the readings (pure; the phone and Safari macOS lanes call analyseFlipProbe on the raw log of window.__fwFlipProbe.stop()) ----

const MOVING = (p) => p === 'width' || p.startsWith('background');

export function analyseFlipProbe(raw, { baseWidth, verify, expectedPushes = null }) {
  const { frames, trace } = raw;
  const tol = verify.tolPx;
  const frameMs = verify.frameMs;
  const flips = [];
  for (let i = 1; i < frames.length; i++) if (frames[i].flip !== frames[i - 1].flip) flips.push({ i, kind: frames[i].flip ? 'enter' : 'leave' });
  const a3a = flips.map(({ i, kind }) => {
    const prev = frames[i - 1];
    const cur = frames[i];
    const dtFrame = cur.ts - prev.ts;
    const pairs = [];
    let lost = 0;
    for (const b of prev.anims) {
      const a = cur.anims.find((x) => x.key === b.key);
      if (!a) lost++;
      else pairs.push({ dt: b.paused ? 0 : dtFrame, before: b.t, after: a.t });
    }
    return { kind, frame: i, lost, pairs: pairs.length, ok: judgeKept(frameMs, lost, pairs), worst: pairs.reduce((m, p) => Math.max(m, Math.abs(p.after - p.before - p.dt)), 0) };
  });
  const a4 = flips.filter((f) => f.kind === 'leave').map(({ i }) => {
    const t0 = frames[i].ts;
    const win = [];
    for (let j = i; j < frames.length && frames[j].ts - t0 <= verify.windowMs; j++) {
      if (j > i && frames[j].flip) break;
      win.push({ moving: frames[j].tr.filter(MOVING).length, width: frames[j].w });
    }
    const covered = frames[frames.length - 1].ts - t0 >= verify.windowMs;
    return {
      frame: i,
      frames: win.length,
      covered,
      moving: Math.max(0, ...win.map((f) => f.moving)),
      maxDev: Math.max(0, ...win.map((f) => Math.abs(f.width - baseWidth))),
      props: [...new Set(frames.slice(i, i + win.length).flatMap((f) => f.tr))],
      ok: covered && judgeQuiet(baseWidth, tol, win),
    };
  });
  const events = trace.filter((e) => e.kind === 'push' || e.kind === 'take').map((e) => e.kind);
  const pushes = events.filter((e) => e === 'push').length;
  const a5 = {
    events,
    pushes,
    takeMs: trace.filter((e) => e.kind === 'take').map((e) => Math.round(e.el)),
    ok: judgeTrace(events) && (expectedPushes === null || pushes === expectedPushes),
  };
  return {
    a3a: { transitions: a3a, enters: a3a.filter((t) => t.kind === 'enter').length, leaves: a3a.filter((t) => t.kind === 'leave').length, ok: a3a.length > 0 && a3a.every((t) => t.ok) },
    a4: { leaves: a4, ok: a4.length > 0 && a4.every((t) => t.ok) },
    a5,
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Entry point for every lane that has a Playwright-style page: drives `cycles` push-open and pull-out wheel pairs at the page end and returns the raw log.
export async function driveFlipProbe(page, { cycles = 2, openMs = 1800, closeMs = 2400 } = {}) {
  const size = await page.evaluate(() => ({ w: innerWidth, h: innerHeight }));
  await page.evaluate(async () => {
    const end = document.documentElement.scrollHeight;
    const from = window.scrollY;
    for (let i = 1; i <= 14; i++) {
      window.scrollTo(0, from + ((end - from) * i) / 14);
      await new Promise((r) => setTimeout(r, 60));
    }
    window.scrollTo(0, end);
  });
  await sleep(1200);
  const baseWidth = await page.evaluate(() => window.__fwFlipProbe.navWidth());
  await page.evaluate(() => window.__fwFlipProbe.start());
  await page.mouse.move(size.w / 2, size.h / 2);
  await sleep(300);
  for (let c = 0; c < cycles; c++) {
    await page.mouse.wheel(0, 120);
    await sleep(openMs);
    await page.mouse.wheel(0, -120);
    await sleep(closeMs);
  }
  const raw = await page.evaluate(() => window.__fwFlipProbe.stop());
  return { raw, baseWidth };
}

export async function runFlipVerify({ engineName, fw, outDir, mutation = null, expectFail = false, bandFilter = null, cycles = 2 }) {
  const { LAUNCHERS } = await import('../../visual-diff/src/engines.mjs');
  const { rewritePathFor } = await import('../../visual-diff/src/run.mjs');
  const verify = loadVerify();
  const cell = loadFlipCell();
  const dist = siteDist();
  const flag = rewritePathFor(dist, fw);
  const server = await startServer(dist);
  const engine = await LAUNCHERS[engineName]();
  const init = `${PIN_SRC}\n(${installFlipProbe.toString()})();`;
  const rows = [];
  try {
    for (const band of cell.bands.filter((b) => !bandFilter || bandFilter.includes(`${b.w}x${b.h}`))) {
      const env = {
        width: band.w, height: band.h, deviceWidth: band.w, deviceHeight: band.h, dpr: band.w <= 640 ? 3 : 1,
        hover: band.w <= 1024 ? 'none' : 'hover', pointer: band.w <= 1024 ? 'coarse' : 'fine', colorScheme: 'light', reducedMotion: 'no-preference',
      };
      const B = await engine.open(env, { origin: server.origin, path: flag.path + flag.search, init });
      try {
        await B.page.evaluate(async () => {
          for (let i = 0; i < 100 && !(window.__fw && window.__fw.hydrated); i++) await new Promise((r) => setTimeout(r, 50));
        });
        await sleep(1800);
        let applied = null;
        if (mutation) applied = await B.page.evaluate(mutatePage, mutation);
        const { raw, baseWidth } = await driveFlipProbe(B.page, { cycles });
        const res = analyseFlipProbe(raw, { baseWidth, verify, expectedPushes: cycles * 2 });
        const row = { band: `${band.w}x${band.h}`, baseWidth, applied, ...res };
        rows.push(row);
        process.stderr.write(`${row.band} A3a ${res.a3a.ok ? 'ok' : 'FAIL'} (enter ${res.a3a.enters}, leave ${res.a3a.leaves}) A4 ${res.a4.ok ? 'ok' : 'FAIL'} A5 ${res.a5.ok ? 'ok' : 'FAIL'} [${res.a5.events.join(',')}] take ms ${res.a5.takeMs.join('/')}\n`);
      } finally {
        await B.close().catch(() => {});
      }
    }
  } finally {
    await engine.close?.();
    server.close?.();
  }
  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, `verify-${engineName}${mutation ? `-${mutation}` : ''}.json`), `${JSON.stringify({ fw, engine: engineName, mutation, cycles, verify, rows }, null, 1)}\n`);
  const own = mutation ? { A4: 'a4', A3a: 'a3a', A5: 'a5' }[mutation] : null;
  const failed = (k) => rows.filter((r) => !r[k].ok).length;
  const summary = ['a3a', 'a4', 'a5'].map((k) => `${k} ${rows.length - failed(k)}/${rows.length}`).join(', ');
  if (mutation) {
    const caught = failed(own) > 0;
    console.log(`flip verify ${engineName} mutation ${mutation}: ${caught ? 'caught' : 'NOT caught'} (${own} failed in ${failed(own)} of ${rows.length} bands; ${summary})`);
    return expectFail ? caught : true;
  }
  const ok = failed('a3a') + failed('a4') + failed('a5') === 0;
  console.log(`flip verify ${engineName} ${fw}: ${ok ? 'pass' : 'fail'} (${summary} bands passed)`);
  return ok;
}
