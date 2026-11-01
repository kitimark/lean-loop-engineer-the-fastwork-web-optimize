import { withSession } from '../session.mjs';
import { loadFresh, pageInfo } from '../page.mjs';
import { startTimeline } from '../timeline.mjs';
import { findDevice, sleep } from '../sim.mjs';
import { sessionPlan } from '../device-arms.mjs';
import { reconnect } from '../wip.mjs';
import { attempts, T } from '../timeouts.mjs';
import { RECORDER_SRC, TO_END_JS, heroJs, endJs, endTouchJs, pageOf, intervalsOf } from './recorder.mjs';
import { openDriver, startServer, stopServer, touchWindow, logTail, TOUCH_COUNT_JS, TOUCH_BUDGET, laneAfter, timelinePlan, variantFor } from '../touch-push.mjs';
import { profileWindow, toHundredths } from './reduce.mjs';
import { orderFor, HERO_BURST } from '../../../gate-breakpoints/src/smooth/schedule.mjs';
import { BOUND_JS, endPushFor } from '../../../gate-breakpoints/src/smooth/bound.mjs';
import { hitches, hundredthsFrom } from '../../../gate-breakpoints/src/smooth/reduce.mjs';
import { runCheck } from '../../../gate-breakpoints/src/trajectory/reduce.mjs';
import { startsWindow, untilDeadline, WINDOW_RESERVE_MS, READY_ALLOW_MS, planReps, repsLife, outcome, groupsFor } from '../walk-budget.mjs';

const BLOCK_MS = 15 * 60000;

// Node's HTTP client (undici) threw `setTypeOfService EINVAL` out of a socket write on a loaded runner and ended the process after 7 windows (run 41345594217 job 4).
// That fault belongs to one request, which the harness's own timeout and retry then handle; any other uncaught error still ends the process.
export const isSocketTosFault = (e) => e?.code === 'EINVAL' && e?.syscall === 'setTypeOfService';

export function guardSocketFault(log, proc = process) {
  const on = (e) => {
    if (isSocketTosFault(e)) { log(`webkit sim: ignored a socket fault (${e.message}); the request it belonged to times out and is retried`); return; }
    console.error(e?.stack ?? String(e));
    proc.exit(1);
  };
  proc.on('uncaughtException', on);
  return () => proc.removeListener('uncaughtException', on);
}

export function simArms(plan, siteDir, lookSearch, only) {
  const out = [
    { id: 'orig', site: 'orig', tree: { dir: null }, search: '' },
    { id: 'base', site: 'rewrite', tree: { dir: siteDir, search: '' }, search: '' },
    { id: 'aa', site: 'rewrite', tree: { dir: siteDir, search: '' }, search: '' },
  ];
  if (only?.includes('bound')) out.push({ id: 'bound', site: 'rewrite', tree: { dir: siteDir, search: '' }, search: '' });
  if (only) {
    if (only.includes('look') && lookSearch) out.push({ id: 'look', site: 'rewrite', tree: { dir: siteDir, search: lookSearch }, search: lookSearch });
    if (only.includes('v2')) out.push({ id: 'v2', site: 'rewrite', tree: { dir: siteDir, search: '?preset=v2-proved' }, search: '?preset=v2-proved' });
    const missing = only.filter((id) => !out.some((a) => a.id === id));
    if (missing.length) throw new Error(`arms not available: ${missing.join(', ')}`);
    return out.filter((a) => only.includes(a.id));
  }
  if (plan.kept.includes('look')) out.push({ id: 'look', site: 'rewrite', tree: { dir: siteDir, search: lookSearch }, search: lookSearch });
  if (plan.kept.includes('v2')) out.push({ id: 'v2', site: 'rewrite', tree: { dir: siteDir, search: '?preset=v2-proved' }, search: '?preset=v2-proved' });
  return out;
}

const CONTROLS = ['base', 'aa'];

// Lean Fw.Measure.WalkBudget: the walk plan, made when the Simulator is booted, the touch driver runs and Safari is open. Touch end pushes are the
// decision window of the touch lanes, so with the driver up each arm walks only its end window (`endOnly`); otherwise hero and end (`full`).
export function planSim({ deadlineMs, nowMs, touchOn, armIds, repsArg = 'auto' }) {
  const shape = touchOn ? 'endOnly' : 'full';
  const n = armIds.length;
  const wins = shape === 'endOnly' ? ['end'] : ['hero', 'end'];
  if (deadlineMs == null) return { shape, wins, repPlan: null, reps: repsArg !== 'auto' ? Number(repsArg) : repsLife(shape, n) };
  const out = outcome(deadlineMs, nowMs, shape, n);
  const controls = armIds.filter((a) => CONTROLS.includes(a)).length;
  const groups = out === 'ok' ? 1 : groupsFor(deadlineMs, nowMs, shape, controls, n - controls);
  return { shape, wins, repPlan: { shape, outcome: out, reps: planReps(deadlineMs, nowMs, shape, n), groups }, reps: repsArg !== 'auto' ? Number(repsArg) : planReps(deadlineMs, nowMs, shape, n) };
}

export function windowVerdict(pw, timelineOn) {
  return timelineOn ? { ok: pw.ok, reason: pw.reason ?? null } : { ok: true, reason: 'timeline-off' };
}

export async function runSimCadence({ siteDir, lookSearch, reps: repsArg = 'auto', settleMs = 2500, only, holdMs, touchDriver, deadlineMs = null, now = Date.now, onProgress = null, blockAfterMs = null, log = (s) => console.error(s) }) {
  const end = endPushFor(holdMs);
  const plan = only ? { kept: [], dropped: [], flags: {} } : sessionPlan(lookSearch);
  const arms = simArms(plan, siteDir, lookSearch, only);
  let reps = 0;
  let repPlan = null;
  let wins = ['hero', 'end'];
  const device = findDevice();
  const started = Date.now();
  const rows = [];
  const raws = [];
  let refused = false;
  let error = null;
  let ua = '';
  const unguard = guardSocketFault(log);
  const opened = openDriver(touchDriver);
  const touch = { driver: opened.driver, on: !!opened.driver, why: opened.why, server: null, pushes: 0 };

  const snapshot = (incomplete) => ({
    leg: 'sim', engine: 'mobile-safari', runtime: device.runtime, device: device.name, ua, width: 430, search: lookSearch, reps, repPlan, cadenceReps: 0,
    plan: { kept: plan.kept, dropped: plan.dropped, flags: plan.flags }, arms: arms.map((a) => a.id),
    hero: HERO_BURST, end, push: { driver: !!touchDriver, touch: touch.on, why: touch.on ? null : touch.why }, refused, incomplete, wallSeconds: Math.round((Date.now() - started) / 1000), rows, raws,
  });

  const readWindow = async (ctx, a, win, rep) => {
    ctx.setArm(a.id);
    await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + a.search)}); scrollTo({ top: 0, behavior: 'instant' }); location.search`);
    await loadFresh(ctx.c, { clock: 'pinned', settleMs });
    const info = await pageInfo(ctx.c);
    ua = info.ua;
    const want = ctx.armHash(a.id);
    const row = { arm: a.id, window: win, rep, mode: 'events', config: info.fw?.configHash ?? null, fwMode: info.fw?.mode ?? null };
    if (runCheck([{ site: a.site, want, config: row.config, mode: row.fwMode }]) !== 'ok') {
      log(`webkit sim ${a.id} ${win}: REFUSED config (${JSON.stringify(info.fw)})`);
      return { refused: { ...row, ok: false, reason: 'refused:config', profiles: null } };
    }
    if (a.id === 'bound') {
      const dur = await ctx.c.evaluate(BOUND_JS);
      if (dur === null || !/^0s(, 0s)*$/.test(dur)) throw new Error(`bound arm: the earn button is missing or still has transitions (transition-duration ${JSON.stringify(dur)})`);
    }
    await ctx.c.evaluate(RECORDER_SRC);
    if (win === 'end') await ctx.c.runAsync(TO_END_JS);
    const plan = timelinePlan(win === 'end' && touch.on, T(7500));
    const tl = plan.kind === 'off' ? null : await startTimeline(ctx.c, { stopMs: plan.ms });
    let rec;
    let push = 'synthetic';
    let touched = null;
    if (win === 'end' && touch.on) {
      await ctx.c.evaluate(TOUCH_COUNT_JS);
      const variant = variantFor(touch.pushes++);
      const got = await touchWindow(ctx.c, { server: touch.server, pageJs: endTouchJs, variant });
      const keep = laneAfter(TOUCH_BUDGET, true, got.obs);
      log(`webkit sim ${a.id} touch push ${touch.pushes - 1} (${variant}): ${got.outcome}, begin ${got.obs.beginAt} ms, swipe ${got.obs.swipeAt} ms, done ${got.obs.doneAt} ms, presses ${JSON.stringify(got.presses)}, ${got.obs.moves} moves`);
      if (!keep) {
        touch.on = false;
        touch.why = `${got.outcome === 'ok' ? 'the driver finished late' : got.outcome}${logTail(touch.server.run.logFile) ? `; driver log tail: ${logTail(touch.server.run.logFile)}` : ''}`;
        await stopServer(touch.server);
        touch.server = null;
        if (got.outcome !== 'ok') throw new Error(`touch push failed: ${got.outcome}`);
      }
      rec = got.result;
      push = 'touch';
      touched = { ...rec.touch, morphMax: rec.morphMax, variant, outcome: got.outcome, obs: got.obs, presses: got.presses };
    } else {
      rec = await ctx.c.runAsync(win === 'hero' ? heroJs(HERO_BURST) : endJs(end), { pollMs: 250 });
      await tl.stop();
    }
    const records = tl ? tl.top : [];
    const pw = profileWindow(pageOf(rec, toHundredths), records);
    raws.push({ arm: a.id, window: win, rep, raw: pw.raw });
    return { row: { ...row, frames: rec.ts.length, hitches: hitches(intervalsOf(rec.ts)), ivs: intervalsOf(rec.ts), th: hundredthsFrom(rec.ts), ...(win === 'end' ? { push, pushWhy: push === 'touch' ? null : touch.why, touched } : {}), ...windowVerdict(pw, !!tl), off: pw.off ?? null, offA: pw.offA ?? null, offB: pw.offB ?? null, profiles: pw.profiles, records: records.length, ...(tl ? {} : { timeline: false }) } };
  };

  let cut = null;
  let blocked = false;
  try {
    const walk = withSession(async (ctx) => {
      if (touch.on) {
        try {
          touch.server = await startServer(touch.driver, { udid: device.udid, log, readyMs: READY_ALLOW_MS });
          await reconnect(ctx, { log });
        } catch (e) { touch.on = false; touch.why = e.message; log(`webkit sim: ${e.message}`); }
      }
      const planned = planSim({ deadlineMs, nowMs: now(), touchOn: touch.on, armIds: arms.map((a) => a.id), repsArg });
      ({ reps, repPlan, wins } = planned);
      log(`webkit sim: ${reps} reps of ${arms.length} arms, ${planned.shape} windows (${repsArg === 'auto' ? `rep plan ${repPlan ? `${repPlan.outcome}${repPlan.outcome === 'ok' ? '' : `, ${repPlan.groups ?? 'no'} jobs of arms would fit`}` : 'without a deadline'}` : 'set by hand'})`);
      walk: for (let rep = 0; rep < reps && !refused; rep++) {
        for (const a of orderFor(arms, rep)) {
          for (const win of wins) {
            const t0 = Date.now();
            let got = null;
            for (let attempt = 1; !got; attempt++) {
              if (deadlineMs != null && !startsWindow(deadlineMs, now(), WINDOW_RESERVE_MS)) {
                cut = `walk deadline: no time left to start ${a.id} ${win} rep ${rep}`;
                break walk;
              }
              if (blockAfterMs != null && !blocked && Date.now() - started >= blockAfterMs) {
                blocked = true;
                log(`webkit sim: test hook, blocking the event loop for ${BLOCK_MS} ms before ${a.id} ${win} rep ${rep}`);
                Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, BLOCK_MS);
              }
              await ctx.check?.();
              try {
                got = await readWindow(ctx, a, win, rep);
              } catch (e) {
                if (attempt >= attempts()) throw e;
                log(`  webkit sim ${a.id} ${win} rep ${rep} attempt ${attempt} failed (${e.message}); reconnecting and retrying from a fresh load`);
                await reconnect(ctx, { log });
              }
            }
            if (got.refused) { refused = true; rows.push(got.refused); break; }
            rows.push(got.row);
            onProgress?.(snapshot('walk not finished: this file was written after a window and the process may have been stopped'));
            log(`webkit sim rep ${rep} ${a.id} ${win}: ${got.row.frames} frames, ${got.row.records} records, window ${got.row.ok ? 'kept' : `refused (${got.row.reason})`} in ${Date.now() - t0} ms`);
          }
          if (refused) break;
        }
      }
    }, { keep: true, arms: Object.fromEntries(arms.map((a) => [a.id, a.tree])), log });
    if (deadlineMs == null) await walk;
    else if (await untilDeadline(walk, deadlineMs, now) === 'deadline') cut = `walk deadline: abandoned a window in flight after ${rows.length} windows`;
    if (cut) { error = cut; log(`webkit sim: INCOMPLETE after ${rows.length} windows (${cut})`); }
  } catch (e) {
    error = e.message;
    log(`webkit sim: INCOMPLETE after ${rows.length} windows (${error})`);
  } finally {
    if (touch.server) await Promise.race([stopServer(touch.server), sleep(25000)]);
    unguard();
  }
  return snapshot(error);
}
