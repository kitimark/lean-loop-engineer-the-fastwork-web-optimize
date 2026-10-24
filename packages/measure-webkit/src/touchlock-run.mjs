// The touch-lock walk (glue): for each rep and arm, load the page, put it START_GAP_PX above its end, and flick it into the end with the
// push server's real touches (a slow pan up that carries the page into its end, then one back down). Counts come from touchlock.mjs.
import { withSession } from './session.mjs';
import { loadFresh, pageInfo } from './page.mjs';
import { findDevice, sleep } from './sim.mjs';
import { reconnect } from './wip.mjs';
import { attempts } from './timeouts.mjs';
import { openDriver, startServer, stopServer, touchWindow, touchCountJs, TOUCH_BUDGET, laneAfter, logTail, variantFor } from './touch-push.mjs';
import { runCheck } from '../../gate-breakpoints/src/trajectory/reduce.mjs';
import { orderFor } from '../../gate-breakpoints/src/smooth/schedule.mjs';
import { startsWindow, untilDeadline, WINDOW_RESERVE_MS } from './walk-budget.mjs';
import { ARMS, PAN, START_GAP_PX, TAIL_MS, summarize } from './touchlock.mjs';
import { installJs, nearEndJs, windowJs } from './touchlock-page.mjs';

export const BUDGET = Object.freeze({ ...TOUCH_BUDGET, tailMs: TAIL_MS });

export function armTrees(siteDir) {
  return {
    orig: { dir: null },
    base: { dir: siteDir, search: '' },
    lock: { dir: siteDir, search: '' },
  };
}

export async function runTouchLock({ siteDir, push = PAN, reps = 6, settleMs = 2500, touchDriver, deadlineMs = null, now = Date.now, onProgress = null, log = (s) => console.error(s) }) {
  const device = findDevice();
  const started = Date.now();
  const rows = [];
  let error = null;
  let ua = '';
  const opened = openDriver(touchDriver);
  const touch = { driver: opened.driver, on: !!opened.driver, why: opened.why, server: null, pushes: 0 };
  const snapshot = (incomplete) => {
    const out = { leg: 'sim-touch-lock', runtime: device.runtime, device: device.name, ua, reps, arms: ARMS, push, startGapPx: START_GAP_PX, tailMs: TAIL_MS,
      touch: { on: touch.on, why: touch.on ? null : touch.why }, incomplete, wallSeconds: Math.round((Date.now() - started) / 1000), rows };
    return { ...out, summary: summarize(rows) };
  };

  const oneWindow = async (ctx, id, rep) => {
    ctx.setArm(id);
    await ctx.c.evaluate(`history.replaceState(null, '', '/'); scrollTo({ top: 0, behavior: 'instant' }); location.search`);
    await loadFresh(ctx.c, { clock: 'pinned', settleMs });
    const info = await pageInfo(ctx.c);
    ua = info.ua;
    const row = { arm: id, rep, config: info.fw?.configHash ?? null };
    const site = id === 'orig' ? 'orig' : 'rewrite';
    if (runCheck([{ site, want: ctx.armHash(id), config: row.config, mode: info.fw?.mode ?? null }]) !== 'ok') return { ...row, status: 'refused:config' };
    const hooks = await ctx.c.evaluate(`JSON.stringify(${installJs(id === 'lock')})`).then(JSON.parse);
    if (!hooks.nav) return { ...row, status: 'refused:nav' };
    const near = await ctx.c.runAsync(nearEndJs(START_GAP_PX));
    await ctx.c.evaluate(touchCountJs(BUDGET.tailMs));
    const variant = variantFor(touch.pushes++);
    const got = await touchWindow(ctx.c, { server: touch.server, pageJs: windowJs, variant, budget: BUDGET });
    log(`touch-lock ${id} rep ${rep} push ${touch.pushes - 1} (${variant}): ${got.outcome}, begin ${got.obs.beginAt} ms, swipe ${got.obs.swipeAt} ms, done ${got.obs.doneAt} ms, ${got.obs.moves} moves, start gap ${near.maxY - near.y}`);
    if (!laneAfter(BUDGET, true, got.obs)) {
      touch.on = false;
      touch.why = `${got.outcome === 'ok' ? 'the driver finished late' : got.outcome}${logTail(touch.server.run.logFile) ? `; driver log tail: ${logTail(touch.server.run.logFile)}` : ''}`;
      await stopServer(touch.server);
      touch.server = null;
    }
    const rec = got.result;
    if (!rec) return { ...row, status: `push:${got.outcome}`, obs: got.obs };
    const tNode = (t) => rec.origin + t;
    const firstScrollMs = rec.ev.length && rec.touch?.firstAt != null ? Math.round(tNode(rec.ev[0][2]) - rec.touch.firstAt) : null;
    const frameGaps = rec.fr.slice(1).map((f, i) => f[2] - rec.fr[i][2]);
    return { ...row, status: got.outcome, variant, obs: got.obs, presses: got.presses, startGap: near.maxY - near.y, maxY10: rec.maxY10, finalY10: rec.finalY10,
      frames: rec.fr.map((f) => [f[0], f[1], Math.round(f[2] * 10) / 10]), events: rec.ev.map((e) => [e[0], e[1], Math.round(e[2] * 10) / 10]),
      q2: { firstScrollMs, longFrames50: frameGaps.filter((g) => g > 50).length, maxFrameGap: Math.round(Math.max(0, ...frameGaps)) } };
  };

  let cut = null;
  try {
    const walk = withSession(async (ctx) => {
      if (!touch.on) throw new Error(`no touch driver: ${touch.why}`);
      touch.server = await startServer(touch.driver, { udid: device.udid, log, push });
      await reconnect(ctx, { log });
      walk: for (let rep = 0; rep < reps; rep++) {
        for (const id of orderFor(ARMS.map((a) => ({ id: a })), rep).map((a) => a.id)) {
          if (!touch.on) { cut = 'the touch lane ended'; break walk; }
          let got = null;
          for (let attempt = 1; !got; attempt++) {
            if (deadlineMs != null && !startsWindow(deadlineMs, now(), WINDOW_RESERVE_MS)) { cut = `walk deadline: no time left to start ${id} rep ${rep}`; break walk; }
            await ctx.check?.();
            try { got = await oneWindow(ctx, id, rep); } catch (e) {
              if (attempt >= attempts()) throw e;
              log(`  touch-lock ${id} rep ${rep} attempt ${attempt} failed (${e.message}); reconnecting and retrying from a fresh load`);
              await reconnect(ctx, { log });
            }
          }
          rows.push(got);
          onProgress?.(snapshot('walk not finished: written after a window'));
        }
      }
    }, { keep: true, arms: armTrees(siteDir), log });
    if (deadlineMs == null) await walk;
    else if (await untilDeadline(walk, deadlineMs, now) === 'deadline') cut = `walk deadline: abandoned a window in flight after ${rows.length} windows`;
    if (cut) { error = cut; log(`touch-lock: INCOMPLETE after ${rows.length} windows (${cut})`); }
  } catch (e) {
    error = e.message;
    log(`touch-lock: INCOMPLETE after ${rows.length} windows (${error})`);
  } finally {
    if (touch.server) await Promise.race([stopServer(touch.server), sleep(25000)]);
  }
  return snapshot(error);
}
