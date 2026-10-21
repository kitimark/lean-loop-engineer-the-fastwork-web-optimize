// One probe run: an arm in a fresh Playwright WebKit, an in-page rAF loop, an idle window, then N settled wheel steps,
// with the Web Inspector Timeline read through Playwright's own page session (no second inspector client).
//
// Timeline route (research/notes/2026/10-2x-linux-webkit.md, finding 3): page._connection.toImpl(page).delegate._session is the
// server-side WKSession of the page target; Timeline.start there makes WebKit emit Timeline.eventRecorded.
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { installRaf, rendererString, settle, stamp, stopRaf } from './inpage.mjs';
import { reduceRun } from './reduce.mjs';
import { pagePath, ROOT } from './serve.mjs';

/** playwright-core 1.64.1 as the gate package pins it (this package has no Playwright dependency of its own). */
export function loadPlaywright() {
  const req = createRequire(join(ROOT, 'packages', 'gate-breakpoints', 'package.json'));
  return req('playwright-core');
}

/** Version string of the playwright-core the probe drives. */
export function playwrightVersion() {
  const req = createRequire(join(ROOT, 'packages', 'gate-breakpoints', 'package.json'));
  return req('playwright-core/package.json').version;
}

const sleep =(ms) => new Promise((ok) => setTimeout(ok, ms));

/** Reject after `ms` so a hung engine call ends the run instead of the job. */
export function withTimeout(p, ms, what) {
  let t;
  const timer = new Promise((_, no) => { t = setTimeout(() => no(new Error(`timeout after ${ms} ms: ${what}`)), ms); });
  return Promise.race([p, timer]).finally(() => clearTimeout(t));
}

/** Viewport height by width: a phone-like portrait box below 640, a laptop box above. */
export const heightOf = (width) => (width < 640 ? 844 : 800);

/**
 * Run one arm once. opts: { pw, origin, arm, steps, dy, idleMs, settleMaxMs, callMs }.
 * Returns { raw, reduced } where raw holds the Timeline records and the rAF timestamps.
 */
export async function runArm({ pw, origin, arm, steps = 10, dy = 400, idleMs = 3000, settleMaxMs = 4000, callMs = 30000 }) {
  const fps = [];
  const launchOpts = { env: { ...process.env, ...arm.env } };
  if (arm.sw === 'fps') {
    // WEBKIT_SHOW_FPS makes the compositor log `FPS: n`; it can reach the page console and the browser's stderr (read both).
    launchOpts.logger = { isEnabled: (name) => name === 'browser', log: (name, sev, msg) => { if (/FPS/i.test(String(msg))) fps.push(`stderr: ${String(msg).trim().slice(0, 160)}`); } };
  }
  const t0 = Date.now();
  const browser = await pw.webkit.launch(launchOpts);
  const raw = { arm: arm.id, steps: [], records: [], fps, renderer: null, timelineError: null, error: null, browser: browser.version() };
  try {
    const context = await browser.newContext({
      viewport: { width: arm.width, height: heightOf(arm.width) },
      deviceScaleFactor: arm.dpr,
    });
    await context.route('**/*', (route) => (route.request().url().startsWith(origin) ? route.continue() : route.abort()));
    const page = await context.newPage();
    page.on('console', (m) => { if (/FPS/i.test(m.text())) fps.push(`console: ${m.text().slice(0, 160)}`); });
    await withTimeout(page.goto(origin + pagePath(arm.page), { waitUntil: 'load' }), callMs, 'goto');
    raw.loadMs = Date.now() - t0;
    const frame = page.mainFrame();
    raw.renderer = await withTimeout(frame.evaluate(rendererString), callMs, 'renderer');
    await sleep(1000);

    let session = null;
    const rows = [];
    try {
      session = page._connection.toImpl(page).delegate._session;
      session.on('Timeline.eventRecorded', (e) => rows.push(e.record));
      await withTimeout(session.send('Timeline.start', { maxCallStackDepth: 1 }), callMs, 'Timeline.start');
    } catch (e) {
      raw.timelineError = String(e && e.message ? e.message : e);
      session = null;
    }

    await frame.evaluate(installRaf, arm.page === 'paint');
    const idle0 = await frame.evaluate(stamp, 'fw-idle0');
    await sleep(idleMs);
    const idle1 = await frame.evaluate(stamp, 'fw-idle1');

    await page.mouse.move(Math.round(arm.width / 2), Math.round(heightOf(arm.width) / 2));
    for (let i = 0; i < steps; i++) {
      const s0 = await withTimeout(frame.evaluate(stamp, `fw-s${i}`), callMs, `stamp s${i}`);
      const w0 = Date.now();
      await withTimeout(page.mouse.wheel(0, dy), callMs, `wheel ${i}`);
      const wheelMs = Date.now() - w0;
      const e = await withTimeout(frame.evaluate(settle, { label: `fw-e${i}`, maxMs: settleMaxMs }), callMs + settleMaxMs, `settle ${i}`);
      raw.steps.push({ i, t0: s0, t1: e.t, wheelMs, scrollY: e.scrollY, timedOut: e.timedOut });
    }
    const all = await frame.evaluate(stopRaf);
    if (session) {
      await withTimeout(session.send('Timeline.stop'), callMs, 'Timeline.stop').catch((e) => { raw.timelineError = String(e.message ?? e); });
      await sleep(300); // events recorded just before stop are still in flight
    }
    raw.records = rows;
    raw.idleRaf = all.filter((t) => t >= idle0 && t <= idle1);
    raw.scrollRaf = raw.steps.length ? all.filter((t) => t >= raw.steps[0].t0 && t <= raw.steps[raw.steps.length - 1].t1) : [];
    raw.idleMs = idle1 - idle0;
  } catch (e) {
    raw.error = String(e && e.message ? e.message : e);
  } finally {
    await browser.close().catch(() => {});
  }
  raw.wallMs = Date.now() - t0;
  return { raw, reduced: { ...reduceRun(raw), error: raw.error, loadMs: raw.loadMs ?? null, wallMs: raw.wallMs, browser: raw.browser, scrollTimedOutSteps: raw.steps.filter((s) => s.timedOut).length } };
}
