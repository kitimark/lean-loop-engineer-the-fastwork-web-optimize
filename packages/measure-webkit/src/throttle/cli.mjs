#!/usr/bin/env node
// node src/throttle/cli.mjs run [--site dir] [--arms original,rewrite,lift,unthrottle] [--rounds 2] [--cycles 4] [--vm n] [--out file]
//   Real touches on Mobile Safari in the booted Simulator (XCUITest driver) while the page records frames; one pass per arm and round, the
//   order rotated each round. original = the read-only snapshot; rewrite = the default prerendered build (--site); lift = the rewrite with
//   ?fw=engine.scroll:throttle-lift; unthrottle = the rewrite with ?fw=engine.scroll:unthrottle; unthrottle-follow = ?fw=engine.scroll:unthrottle-follow
//   --mode finish: the page is scrolled to 300 px above its end, then real drags past the end open the morph panel and back (finish zone
//   counts, scrollY reversals while open, open lateness; --drag 480 --velocity 150 by default).
// node src/throttle/cli.mjs build-driver --dir d  build the touch driver once, before the Simulator boots (run --driver d uses it)
// node src/throttle/cli.mjs report --in a.json,b.json [--md file]   the still-run table and the verdict per job and pooled
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { withSession } from '../session.mjs';
import { watch } from '../watchdog.mjs';
import { findDevice, shutdownDevice } from '../sim.mjs';
import { loadavg } from 'node:os';
import { buildDriver, cleanup, dragPass, findDriver, stop, initPass, step, terminal, setTouchHooks, lastTouch, resetTouch, SIM_TOUCH } from './driver.mjs';
import { armPass } from './probe.mjs';
import { loadFresh } from '../page.mjs';
import { excludeReason, reportMd, ARMS, SHIPPED_ARM, FOLLOW_ARM } from './report.mjs';
import { movingMd } from './follow-report.mjs';
import { finishPass } from './finish-probe.mjs';
import { excludeReason as finishExclude, reportMd as finishMd } from './finish-report.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: {
    site: { type: 'string' }, arms: { type: 'string', default: 'rewrite,lift,original' }, rounds: { type: 'string', default: '2' },
    cycles: { type: 'string', default: '4' }, rotate: { type: 'string', default: '0' }, drag: { type: 'string' }, velocity: { type: 'string' }, mode: { type: 'string', default: 'drags' },
    target: { type: 'string', default: 'springboard' }, hold: { type: 'string', default: '600' }, 'no-warmup': { type: 'boolean', default: false }, settle: { type: 'string', default: '6000' }, vm: { type: 'string', default: '1' },
    out: { type: 'string' }, dir: { type: 'string' }, driver: { type: 'string' }, in: { type: 'string' }, md: { type: 'string' }, keep: { type: 'boolean', default: true },
  },
  allowNegative: true,
});
const log = (s) => console.error(s);
const SEARCH = { lift: '?fw=engine.scroll:throttle-lift', unthrottle: '?fw=engine.scroll:unthrottle', 'unthrottle-follow': '?fw=engine.scroll:unthrottle-follow' };
const siteOf = (arm) => {
  if (arm === 'original') return null;
  if (!v.site) throw new Error(`arm ${arm} needs --site (the prerendered build)`);
  return { dir: v.site, search: SEARCH[arm] ?? '' };
};
const rotate = (arms, r) => arms.map((_, i) => arms[(i + r) % arms.length]);

async function main() {
  switch (cmd) {
    case 'run': {
      const arms = v.arms.split(',');
      const udid = findDevice().udid;
      const driver = v.driver ? findDriver(resolve(v.driver)) : await buildDriver({ udid, log });
      log(`load ${loadavg()[0].toFixed(0)} before the first pass`);
      if (!['drags', 'finish'].includes(v.mode)) throw new Error(`unknown --mode ${v.mode}; drags or finish`);
      const finish = v.mode === 'finish';
      const drag = { cycles: Number(v.cycles), dragPt: Number(v.drag ?? (finish ? 480 : 360)), velocity: Number(v.velocity ?? (finish ? 150 : 120)),
        holdMs: Number(v.hold), mode: v.mode, target: v.target };
      const passOf = finish ? finishPass : armPass;
      const reasonOf = finish ? finishExclude : excludeReason;
      const passes = [], failed = [], machine = [];
      const file = resolve(v.out ?? 'out/throttle.json');
      const outDir = dirname(file);
      mkdirSync(outDir, { recursive: true });
      // written after every pass: a stalled job still reports the passes it finished
      const save = () => writeFileSync(file, JSON.stringify({ vm: v.vm, drag, passes, failed, machine }) + '\n');
      const scrub = (t) => t.replace(/[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}/gi, '<id>').replace(/\/Users\/[^/\s]+/g, '<home>');
      const summary = (t) => { const { logFile, ...rest } = t; return rest; };
      // the driver's log tail and its mark timeline of every touch run, as out/<vm>-driver-<tag>.log (the lane keeps out/<vm>-*)
      const persist = (t) => {
        try {
          let tail = '';
          try { tail = scrub(readFileSync(t.logFile, 'utf8').slice(-4000)); } catch { /* no log written */ }
          writeFileSync(join(outDir, `${v.vm}-driver-${t.tag}.log`), `${JSON.stringify(summary(t))}\n${tail}\n`);
        } catch (e) { log(`driver log not kept: ${e.message}`); }
      };
      const pageUp = (c) => async () => { const s = await c.evaluate('document.readyState'); return s === 'complete' || s === 'interactive'; };
      const firstCap = Number(process.env.FW_TOUCH_FIRST_CAP_S); // debug only: stop the first measured touch run after this many s, to walk the restart path
      if (Number.isFinite(firstCap) && firstCap > 0) setTouchHooks({ capOnceS: firstCap });
      // one session that loads the page and runs one touch cycle, unrecorded; true when the session came up and the driver ran
      const warmUp = async (why) => {
        let ok = false;
        try {
          await withSession(async (ctx) => {
            await loadFresh(ctx.c, { clock: 'pinned', settleMs: 2000 });
            setTouchHooks({ page: pageUp(ctx.c) });
            try {
              const r = await dragPass(driver, { udid, tag: 'warm-up', log, ...drag, cycles: 1 });
              log(`${why}: touches ${r.code === 0 ? 'done' : `failed (code ${r.code}${r.killedBy ? `, ${r.killedBy}` : ''})`}`);
            } finally { if (lastTouch()) persist(lastTouch()); }
            ok = true;
          }, { keep: v.keep, site: siteOf(arms.find((a) => a !== 'original') ?? 'original') });
        } catch (e) { log(`${why} failed: ${e.message}`); } finally { setTouchHooks({ page: null }); }
        return ok;
      };
      // The Lean restart step (Fw.Device.SimTouch): shut the Simulator down (it kills the stuck XCUITest runner with it), boot it in a new
      // session and run the warm-up again; ok when that came up within restartS.
      const restart = async (tag) => {
        const t0 = Date.now();
        log(`${tag}: restarting the Simulator`);
        let ok = false;
        try { ok = shutdownDevice(udid, { log }); } catch (e) { log(`${tag}: shutdown failed: ${e.message}`); }
        if (ok) ok = await warmUp(`${tag}: restart warm-up`);
        const s = Math.round((Date.now() - t0) / 1000);
        log(`${tag}: restart ${ok && s <= SIM_TOUCH.restartS ? 'ok' : 'failed'} in ${s} s`);
        return ok && s <= SIM_TOUCH.restartS;
      };
      // One pass of an arm, driven by the Lean machine: probe, touches, and on a failure one Simulator restart and one more try.
      // A record that is unusable for another reason (the page was lost) gets one more machine run, outside the machine, only when
      // the first run used no restart, so a pass never restarts the Simulator more than once.
      const runArm = async (arm, round) => {
        const tag = `${arm}-r${round + 1}`;
        let st = initPass(), rec = null, last = null, extra = 0;
        const events = [];
        const feed = (e) => { events.push(e); st = step(st, e); log(`${tag}: ${e} -> ${st.phase} (attempt ${st.attempt}, restarts ${st.restarts})`); };
        for (;;) {
          while (!terminal(st)) {
            if (st.phase === 'restarting') { feed((await restart(tag)) ? 'restartOk' : 'restartFail'); continue; }
            rec = null; resetTouch();
            try {
              rec = await withSession((ctx) => { setTouchHooks({ page: pageUp(ctx.c) }); return passOf(ctx, { driver, udid, drag, settleMs: Number(v.settle), tag }); },
                { keep: v.keep, site: siteOf(arm) });
              feed('readyYes'); feed(rec.drag.code === 0 ? 'touchesOk' : 'touchesFail');
            } catch (e) {
              log(`${tag} failed: ${e.message}`);
              const t = lastTouch();
              if (t?.code === 0) { feed('readyYes'); feed('touchesOk'); } // the touches were clean, a later step failed (the recorder): not a driver fault
              else if (t?.ready?.ready) { feed('readyYes'); feed('touchesFail'); } else feed('readyNo');
            } finally { setTouchHooks({ page: null }); if (lastTouch()) { last = summary(lastTouch()); persist(lastTouch()); } }
          }
          const bad = st.phase === 'done' ? reasonOf({ arm, round: round + 1, vm: v.vm, ...rec }) : null;
          if (bad && extra < 1 && st.restarts === 0) { extra++; log(`${tag} not usable (${bad}); trying once more`); st = initPass(); continue; }
          break;
        }
        machine.push({ tag, phase: st.phase, attempt: st.attempt, restarts: st.restarts, extra, events });
        if (rec) passes.push({ arm, round: round + 1, vm: v.vm, attempt: st.attempt + extra, ...rec, touch: last });
        if (st.phase !== 'done') failed.push(`${tag}: ${st.phase}`);
        else if (!rec) failed.push(`${tag}: done without a record`);
        save();
      };
      try {
        // The first session on a fresh Simulator drops its openurl and asks again, and the first XCUITest run relaunches Safari: both
        // reload the page after the recorder started (the first measured pass was lost that way in 4 of 6 CI jobs). One warm-up
        // session loads the page and runs one touch cycle, unrecorded, before the arms.
        if (!v['no-warmup']) await warmUp('warm-up');
        for (let round = 0; round < Number(v.rounds); round++) {
          for (const arm of rotate(arms, round + Number(v.rotate))) await runArm(arm, round);
        }
      } finally { stop(); if (!v.driver) cleanup(driver); }
      save();
      log(`wrote ${file} (${passes.length} passes${failed.length ? `, ${failed.length} failed` : ''})`);
      if (!passes.length) throw new Error('no pass completed');
      break;
    }
    case 'build-driver': {
      if (!v.dir) throw new Error('usage: build-driver --dir d');
      await buildDriver({ dir: resolve(v.dir), log });
      log(`load ${loadavg()[0].toFixed(0)} after the build`);
      break;
    }
    case 'report': {
      if (!v.in) throw new Error('usage: report --in a.json,b.json [--md file]');
      const jobs = v.in.split(',').map((f) => JSON.parse(readFileSync(resolve(f), 'utf8')));
      const vms = jobs.map((j, i) => ({ vm: `job ${j.vm ?? i + 1}`, passes: j.passes }));
      const isFinish = jobs.some((j) => j.drag?.mode === 'finish');
      const present = [...Object.values(ARMS), SHIPPED_ARM, FOLLOW_ARM].filter((a) => vms.some((x) => x.passes.some((p) => p.arm === a)));
      const md = (isFinish ? finishMd : reportMd)(vms) + (isFinish ? '' : movingMd(vms, present));
      if (v.md) writeFileSync(resolve(v.md), md); else console.log(md);
      break;
    }
    default:
      console.error('usage: run|build-driver|report');
      process.exitCode = 2;
  }
}
const guard = watch();
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = e.exitCode ?? 1; }).finally(() => guard.done(process.exitCode ?? 0));
