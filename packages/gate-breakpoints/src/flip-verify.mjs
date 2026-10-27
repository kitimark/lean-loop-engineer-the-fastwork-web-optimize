import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PKG, siteDist, startServer } from './serve.mjs';
import { PIN_SRC } from './page.mjs';
import { loadFlipCell, readLive } from './flip-cell.mjs';

export const GOLDEN = resolve(PKG, '../contracts/golden/morph-geom-timed.jsonl');

export function loadVerify(path = GOLDEN) {
  const lines = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  const v = lines.find((l) => l.fn === 'verify')?.out;
  if (!v) throw new Error(`no verify line in ${path}`);
  return v;
}

// Verdicts: TS stand-ins for Fw.Parts.MorphGeom.quietOk, keptWithin/keptAll and pushesTaken (lean/Fw/Parts/MorphGeomVerify.lean), replayed against the golden.
const DURATION_MS = 680; // the tween's own length (Fw.Parts.MorphGeomTimed)

export function judgeQuiet(base, tol, frames) {
  return frames.length > 0 && frames.every((f) => f.moving === 0 && f.width - base <= tol && base - f.width <= tol);
}

export function keptWithin(frame, dt, before, after) {
  return after - before - dt <= frame && before + dt - after <= frame;
}

export function judgeKept(frame, lost, pairs) {
  return lost === 0 && pairs.length > 0 && pairs.every((p) => keptWithin(frame, p.dt, p.before, p.after));
}

// Fw.Parts.MorphGeom.takenFlags: per push, was it taken (null: a take with no pending push, or a second take).
export function takenFlags(events) {
  const out = [];
  let pending = false;
  for (const e of events) {
    if (e === 'push') {
      if (pending) out.push(false);
      pending = true;
    } else if (e === 'take') {
      if (!pending) return null;
      out.push(true);
      pending = false;
    }
  }
  if (pending) out.push(false);
  return out;
}

export const pushJudged = (chance, taken) => !chance || taken;
export const judgedEnough = (judged, total) => total > 0 && 3 * total <= 4 * judged;

// Fw.Parts.MorphGeom.traceOk: every push that had a chance (the guard open in a frame with a later frame in its window) is taken, in order,
// and at least 3 of every 4 pushes are covered (had a chance, or were taken anyway).
export function judgeTrace(events, chances) {
  const ts = takenFlags(events);
  if (ts === null || ts.length !== chances.length) return false;
  return chances.every((c, i) => pushJudged(c, ts[i])) && judgedEnough(chances.filter((c, i) => c || ts[i]).length, chances.length);
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
  const state = {};
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
  const all = [];
  let running = false;
  window.__fwTakeTrace = (ev) => {
    const nav = document.querySelector('[data-fw="nav"]');
    trace.push({ ...ev, at: performance.now(), y: Math.round(window.scrollY), nav: nav ? nav.className.split(' ').filter((c) => c.startsWith('is-')).join(' ') : '', flip: document.documentElement.classList.contains('is-flip') });
    all.push(ev.kind);
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
      dark: nav ? /(^| )is-on-dark( |$)/.test(nav.className) : false,
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
    // push and take events seen since the page loaded (the warm-up included), for the drive loop's waits
    count() {
      return { push: all.filter((e) => e === 'push').length, take: all.filter((e) => e === 'take').length };
    },
    listen() {
      all.length = 0;
    },
    navWidth() {
      return document.querySelector('[data-fw="nav"]').getBoundingClientRect().width;
    },
    state,
  };
}

// Reverts one fix at run time: A1/A3b/A3c/A4 edit the stylesheet rule the fix added, A3a drops the animation-time restore, A5 makes the take guard read light at every push and every frame after it (no push can take).
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
    // The nav reads light for the take guard at every push and every frame after it: the unfixed code decided once at push start and never retried, so no push takes the timed path.
    const nav = document.querySelector('[data-fw="nav"]');
    const real = nav.classList.contains.bind(nav.classList);
    Object.defineProperty(nav.classList, 'contains', { configurable: true, value: (c) => (c === 'is-on-dark' ? false : real(c)) });
    n = 1;
  } else {
    throw new Error(`unknown mutation ${name}`);
  }
  return n;
}

// ---- the readings (pure; the phone and Safari macOS lanes call analyseFlipProbe on the raw log of window.__fwFlipProbe.stop()) ----

const MOVING = (p) => p === 'width' || p.startsWith('background');

// Computed colours as sRGB + alpha in 0..1 (getComputedStyle gives rgba(), color(srgb) or oklab() depending on the value).
export function parseColor(str) {
  const nums = (str.match(/-?\d*\.?\d+(?:e-?\d+)?/g) || []).map(Number);
  const alpha = str.includes('/') ? nums[nums.length - 1] : nums.length > 3 ? nums[3] : 1;
  if (str.startsWith('rgb')) return [nums[0] / 255, nums[1] / 255, nums[2] / 255, alpha];
  if (str.startsWith('color(srgb')) return [nums[0], nums[1], nums[2], alpha];
  if (str.startsWith('oklab')) {
    const [L, a, b] = nums;
    const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
    const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
    const sx = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
    const lin = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * sx, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * sx, -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * sx];
    return [...lin.map((c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * Math.abs(c) ** (1 / 2.4) - 0.055)), alpha];
  }
  return [0, 0, 0, 0];
}
export const colorDist = (a, b) => {
  const [p, q] = [parseColor(a), parseColor(b)];
  return Math.max(...p.map((v, i) => Math.abs(v - q[i])));
};
const BG_TOL = 0.02;

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
    const keys = [];
    let lost = 0;
    for (const b of prev.anims) {
      const a = cur.anims.find((x) => x.key === b.key);
      if (!a) lost++;
      else {
        keys.push(b.key);
        pairs.push({ dt: b.paused ? 0 : dtFrame, before: b.t, after: a.t });
      }
    }
    return { kind, frame: i, lost, pairs: pairs.length, ok: judgeKept(Math.max(frameMs, dtFrame) + 0.01, lost, pairs), worst: pairs.reduce((m, p) => Math.max(m, Math.abs(p.after - p.before - p.dt)), 0), detail: pairs.map((p, k) => ({ key: keys[k], dt: Math.round(p.dt * 10) / 10, delta: Math.round((p.after - p.before - p.dt) * 10) / 10 })) };
  });
  const a4 = flips.filter((f) => f.kind === 'leave').map(({ i }) => {
    const t0 = frames[i].ts;
    const win = [];
    for (let j = i; j < frames.length && frames[j].ts - t0 <= verify.windowMs; j++) {
      if (j > i && frames[j].flip) break;
      win.push(j);
    }
    const endBg = frames[win[win.length - 1]].bg;
    // a running width or background transition counts only while it is visibly off its end value (the base nav ends the close with a sub-pixel, sub-percent transition of its own)
    const quietWin = win.map((j) => ({
      moving: frames[j].tr.filter((p) => MOVING(p) && (p === 'width' ? Math.abs(frames[j].w - baseWidth) > tol : colorDist(frames[j].bg, endBg) > BG_TOL)).length,
      width: frames[j].w,
    }));
    const covered = frames[frames.length - 1].ts - t0 >= verify.windowMs;
    return {
      frame: i,
      frames: win.length,
      covered,
      moving: Math.max(0, ...quietWin.map((f) => f.moving)),
      maxDev: Math.max(0, ...quietWin.map((f) => Math.abs(f.width - baseWidth))),
      maxBgDist: Math.max(0, ...win.map((j) => colorDist(frames[j].bg, endBg))),
      props: [...new Set(frames.slice(i, i + win.length).flatMap((f) => f.tr))],
      runs: frames.slice(i, i + win.length).reduce((rs, f, k) => {
        const sig = `${f.tr.join('+') || '-'} w=${Math.round(f.w * 10) / 10}${f.flip ? ' flip' : ''}`;
        if (!rs.length || rs[rs.length - 1].sig !== sig) rs.push({ at: Math.round(f.ts - t0), sig });
        return rs;
      }, []),
      ok: covered && judgeQuiet(baseWidth, tol, quietWin),
    };
  });
  const events = trace.filter((e) => e.kind === 'push' || e.kind === 'take').map((e) => e.kind);
  const pushEvs = trace.filter((e) => e.kind === 'push');
  const pushes = pushEvs.length;
  const t0 = frames.length ? frames[0].ts : 0;
  // read from the className string, not classList.contains, which the A5 mutation overrides
  const chances = pushEvs.map((e) => {
    const win = frames.filter((f) => f.ts >= e.at && f.ts < e.at + DURATION_MS);
    const firstDark = win.findIndex((f) => f.dark);
    return firstDark >= 0 && firstDark < win.length - 1;
  });
  const flags = takenFlags(events) || [];
  const a5 = {
    log: trace.filter((e) => e.kind === 'push' || e.kind === 'take').map((e) => ({
      kind: e.kind,
      at: Math.round(e.at - t0),
      ...(e.kind === 'push' ? { dir: e.to > e.from ? 'open' : 'close', y: e.y, nav: e.nav, flip: e.flip, frames680: frames.filter((f) => f.ts >= e.at && f.ts < e.at + DURATION_MS).length } : { el: Math.round(e.el) }),
    })),
    events,
    pushes,
    chances,
    unjudged: chances.filter((c, i) => !c && !flags[i]).length,
    takeMs: trace.filter((e) => e.kind === 'take').map((e) => Math.round(e.el)),
    ok: judgeTrace(events, chances) && (expectedPushes === null || pushes === expectedPushes),
  };
  return {
    a3a: { transitions: a3a, enters: a3a.filter((t) => t.kind === 'enter').length, leaves: a3a.filter((t) => t.kind === 'leave').length, ok: a3a.length > 0 && a3a.every((t) => t.ok) },
    a4: { leaves: a4, ok: a4.length > 0 && a4.every((t) => t.ok) },
    a5,
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Polls a page-side predicate (source string) every 100 ms; resolves true when it held, false at the timeout.
const until = (page, src, ms) =>
  page.evaluate(
    ([code, limit]) =>
      new Promise((res) => {
        const f = new Function(`return (${code})`);
        const t0 = performance.now();
        const tick = () => {
          if (f()) res(true);
          else if (performance.now() - t0 > limit) res(false);
          else setTimeout(tick, 100);
        };
        tick();
      }),
    [src, ms],
  );

const FLIP_ON = "document.documentElement.classList.contains('is-flip')";
const FLIP_OFF = `!${FLIP_ON}`;
const PUSHES = (n) => `window.__fwFlipProbe.count().push >= ${n}`;
const TAKES = (n) => `window.__fwFlipProbe.count().take >= ${n}`;

// Entry point for every lane that has a Playwright-style page (the phone and the Safari macOS lanes call it with their own page object):
// scrolls to the page end, warms the wheel listeners up with one unrecorded open and close (they arm late), then records `cycles` pairs of
// wheel down (open) and wheel up (pull out), each waiting for what it started instead of a fixed time. Returns the raw log and the base width.
export async function driveFlipProbe(page, { cycles = 2, settleMs = 1500, windowMs = 1200, warmTries = 8 } = {}) {
  const size = await page.evaluate(() => ({ w: innerWidth, h: innerHeight }));
  const diag = { warm: [], cycles: [] };
  // Scroll to the true end: the page grows while sections hydrate, so one scrollTo can stop short (run 40530697810, WebKit 1024x768 and 1920x1080: y 2681 of 6352).
  const atEnd = await page.evaluate(async () => {
    let steady = 0;
    for (let i = 0; i < 80 && steady < 4; i++) {
      window.scrollTo(0, document.documentElement.scrollHeight);
      await new Promise((r) => setTimeout(r, 250));
      steady = document.documentElement.scrollHeight - window.innerHeight - window.scrollY < 2 ? steady + 1 : 0;
    }
    return steady >= 4;
  });
  diag.atEnd = atEnd;
  await sleep(1200);
  await page.mouse.move(size.w / 2, size.h / 2);
  await page.evaluate(() => window.__fwFlipProbe.listen());
  for (let k = 0; k < warmTries; k++) {
    await page.mouse.wheel(0, 120);
    if (await until(page, PUSHES(1), 2500)) {
      diag.warm.push({ try: k + 1, live: await page.evaluate(readLive) });
      await until(page, FLIP_ON, 5000);
      await sleep(settleMs);
      await page.mouse.wheel(0, -120);
      await until(page, FLIP_OFF, 8000);
      await sleep(windowMs);
      break;
    }
    diag.warm.push({ try: k + 1, live: await page.evaluate(readLive), pushed: false });
    await sleep(1000);
  }
  const baseWidth = await page.evaluate(() => window.__fwFlipProbe.navWidth());
  await page.evaluate(() => {
    window.__fwFlipProbe.listen();
    window.__fwFlipProbe.start();
  });
  await sleep(300);
  for (let c = 0; c < cycles; c++) {
    const pushed = [];
    await page.mouse.wheel(0, 120);
    pushed.push(await until(page, PUSHES(2 * c + 1), 3000));
    pushed.push(await until(page, TAKES(2 * c + 1), 3000));
    await until(page, FLIP_ON, 6000);
    await sleep(settleMs);
    await page.mouse.wheel(0, -120);
    pushed.push(await until(page, PUSHES(2 * c + 2), 3000));
    await until(page, FLIP_OFF, 8000);
    await sleep(windowMs);
    diag.cycles.push({ cycle: c + 1, openPush: pushed[0], openTake: pushed[1], closePush: pushed[2] });
  }
  diag.end = await page.evaluate(readLive);
  const raw = await page.evaluate(() => window.__fwFlipProbe.stop());
  return { raw, baseWidth, diag };
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
        width: band.w, height: band.h, deviceWidth: band.w, deviceHeight: band.h, dpr: 1, // the push and take path does not depend on pixel density; dpr 3 made the CI WebKit runner render the open panel at 2 fps (run 40530697810)
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
        const { raw, baseWidth, diag } = await driveFlipProbe(B.page, { cycles });
        const res = analyseFlipProbe(raw, { baseWidth, verify, expectedPushes: cycles * 2 });
        const row = { band: `${band.w}x${band.h}`, baseWidth, applied, diag, ...res };
        rows.push(row);
        process.stderr.write(`${row.band} A3a ${res.a3a.ok ? 'ok' : 'FAIL'} (enter ${res.a3a.enters}, leave ${res.a3a.leaves}) A4 ${res.a4.ok ? 'ok' : 'FAIL'} A5 ${res.a5.ok ? 'ok' : 'FAIL'} [${res.a5.events.join(',')}] take ms ${res.a5.takeMs.join('/')}${res.a5.unjudged ? ` (${res.a5.unjudged} push not judged: the guard had no chance)` : ''}\n`);
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
