// The pass loop of the Simulator touch lanes (I/O glue shared by cli.mjs and parts-cli.mjs): a warm-up, then each pass driven by the Lean
// machine of lean/Fw/Device/SimTouch.lean (probe, touches, and on a failure one Simulator restart and one more try). The decisions
// (`step`, `terminal`, the stall rule) live in driver.mjs and are golden-checked; this file only feeds the machine its events.
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { withSession } from '../session.mjs';
import { shutdownDevice } from '../sim.mjs';
import { loadFresh } from '../page.mjs';
import { dragPass, initPass, step, terminal, setTouchHooks, lastTouch, resetTouch, SIM_TOUCH } from './driver.mjs';

const scrub = (t) => t.replace(/[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}/gi, '<id>').replace(/\/Users\/[^/\s]+/g, '<home>');
const summary = (t) => { const { logFile, ...rest } = t; return rest; };

/**
 * @param o.passOf   async (ctx, {driver, udid, drag, settleMs, tag, round}) -> the pass record ({drag: {code}, ...}, or {skipped} when no touches ran)
 * @param o.reasonOf (pass with arm, round, vm) -> why it cannot count, or null
 * @param o.warmMode drag mode of the warm-up (default: the lane's own)
 * @param o.state    {passes, failed, machine} arrays the caller writes out; `save()` is called after every pass
 * @param deps       test seams: withSession, shutdownDevice, loadFresh, dragPass, setTouchHooks, lastTouch, resetTouch
 */
export function makePassRunner(o, deps = {}) {
  const d = { withSession, shutdownDevice, loadFresh, dragPass, setTouchHooks, lastTouch, resetTouch, ...deps };
  const { driver, udid, drag, log, vm, keep, settleMs, outDir, siteOf, firstSiteArm, passOf, reasonOf, warmMode, state, save } = o;
  const pageUp = (c) => async () => { const s = await c.evaluate('document.readyState'); return s === 'complete' || s === 'interactive'; };
  // the driver's log tail and its mark timeline of every touch run, as out/<vm>-driver-<tag>.log (the lane keeps out/<vm>-*)
  const persist = (t) => {
    try {
      mkdirSync(outDir, { recursive: true });
      let tail = '';
      try { tail = scrub(readFileSync(t.logFile, 'utf8').slice(-4000)); } catch { /* no log written */ }
      writeFileSync(join(outDir, `${vm}-driver-${t.tag}.log`), `${JSON.stringify(summary(t))}\n${tail}\n`);
    } catch (e) { log(`driver log not kept: ${e.message}`); }
  };
  const firstCap = Number(process.env.FW_TOUCH_FIRST_CAP_S); // debug only: stop the first measured touch run after this many s, to walk the restart path
  if (Number.isFinite(firstCap) && firstCap > 0) d.setTouchHooks({ capOnceS: firstCap });

  // one session that loads the page and runs one touch cycle, unrecorded; true when the session came up and the driver ran
  const warmUp = async (why) => {
    let ok = false;
    try {
      await d.withSession(async (ctx) => {
        await d.loadFresh(ctx.c, { clock: 'pinned', settleMs: 2000 });
        d.setTouchHooks({ page: pageUp(ctx.c) });
        try {
          const r = await d.dragPass(driver, { udid, tag: 'warm-up', log, ...drag, cycles: 1, ...(warmMode ? { mode: warmMode } : {}) });
          log(`${why}: touches ${r.code === 0 ? 'done' : `failed (code ${r.code}${r.killedBy ? `, ${r.killedBy}` : ''})`}`);
        } finally { if (d.lastTouch()) persist(d.lastTouch()); }
        ok = true;
      }, { keep, site: siteOf(firstSiteArm) });
    } catch (e) { log(`${why} failed: ${e.message}`); } finally { d.setTouchHooks({ page: null }); }
    return ok;
  };

  // The Lean restart step: shut the Simulator down (INFERRED to end the stuck XCUITest runner), boot it in a new session and run the
  // warm-up again; ok when that came up within restartS.
  const restart = async (tag) => {
    const t0 = Date.now();
    log(`${tag}: restarting the Simulator`);
    let ok = false;
    try { ok = d.shutdownDevice(udid, { log }); } catch (e) { log(`${tag}: shutdown failed: ${e.message}`); }
    if (ok) ok = await warmUp(`${tag}: restart warm-up`);
    const s = Math.round((Date.now() - t0) / 1000);
    log(`${tag}: restart ${ok && s <= SIM_TOUCH.restartS ? 'ok' : 'failed'} in ${s} s`);
    return ok && s <= SIM_TOUCH.restartS;
  };

  // One pass of an arm, driven by the Lean machine: probe, touches, and on a failure one Simulator restart and one more try.
  // A record that is unusable for another reason (the page was lost, or a recorder failure after clean touches) gets one more machine
  // run, outside the machine, only when the first run used no restart, so a pass restarts the Simulator at most once in total.
  const runArm = async (arm, round) => {
    const tag = `${arm}-r${round + 1}`;
    let st = initPass(), rec = null, last = null, extra = 0;
    const events = [];
    const feed = (e) => { events.push(e); st = step(st, e); log(`${tag}: ${e} -> ${st.phase} (attempt ${st.attempt}, restarts ${st.restarts})`); };
    for (;;) {
      while (!terminal(st)) {
        if (st.phase === 'restarting') { feed((await restart(tag)) ? 'restartOk' : 'restartFail'); continue; }
        rec = null; d.resetTouch();
        try {
          rec = await d.withSession((ctx) => { d.setTouchHooks({ page: pageUp(ctx.c) }); return passOf(ctx, { driver, udid, drag, settleMs, tag, round: round + 1 }); },
            { keep, site: siteOf(arm) });
          feed('readyYes'); feed(rec.skipped || rec.drag?.code === 0 ? 'touchesOk' : 'touchesFail');
        } catch (e) {
          log(`${tag} failed: ${e.message}`);
          const t = d.lastTouch();
          if (t?.code === 0) { feed('readyYes'); feed('touchesOk'); } // the touches were clean, a later step failed (the recorder): not a driver fault
          else if (t?.ready?.ready) { feed('readyYes'); feed('touchesFail'); } else feed('readyNo');
        } finally { d.setTouchHooks({ page: null }); if (d.lastTouch()) { last = summary(d.lastTouch()); persist(d.lastTouch()); } }
      }
      const bad = st.phase === 'done' ? reasonOf({ arm, round: round + 1, vm, ...rec }) : null;
      if (bad && extra < 1 && st.restarts === 0) { extra++; log(`${tag} not usable (${bad}); trying once more`); st = initPass(); continue; }
      break;
    }
    state.machine.push({ tag, phase: st.phase, attempt: st.attempt, restarts: st.restarts, extra, events });
    if (rec) state.passes.push({ arm, round: round + 1, vm, attempt: st.attempt + extra, ...rec, touch: last });
    if (st.phase !== 'done') state.failed.push(`${tag}: ${st.phase}`);
    else if (!rec) state.failed.push(`${tag}: done without a record`);
    save();
  };
  return { warmUp, runArm };
}
