// Leg 2 of smoothness-webkit-cadence: Mobile Safari in the iOS Simulator, one session, every arm on one origin, the WebKit Timeline read
// per frame of each window. Glue only: the zone binning and the clock-offset rule are Lean's (reduce.mjs); the arm identity check is
// the gate's (`runCheck`); the arm list is Lean's dedup of the flags (`sessionPlan`).
//
// The Simulator has no wheel device, so the windows are scripted inside the page (recorder.mjs `heroJs`, `endJs`), on the same
// schedule as the macOS leg. The Timeline is on in every window, so the cadence read here is labelled "Timeline on". The A/A arm is
// the faithful rewrite visited a second time on the same tree (one origin per tab): that bounds revisit noise, not server noise.
import { withSession } from '../session.mjs';
import { loadFresh, pageInfo } from '../page.mjs';
import { startTimeline } from '../timeline.mjs';
import { findDevice } from '../sim.mjs';
import { sessionPlan } from '../device-arms.mjs';
import { RECORDER_SRC, TO_END_JS, heroJs, endJs, pageOf, intervalsOf } from './recorder.mjs';
import { profileWindow, toHundredths } from './reduce.mjs';
import { orderFor, HERO_BURST, END_PUSH } from '../../../gate-breakpoints/src/smooth/schedule.mjs';
import { hitches } from '../../../gate-breakpoints/src/smooth/reduce.mjs';
import { runCheck } from '../../../gate-breakpoints/src/trajectory/reduce.mjs';

/** The arms of the session as `withSession` wants them, and the identity each must show (`want`: the config hash, null for the original). */
export function simArms(plan, siteDir, lookSearch) {
  const out = [
    { id: 'orig', site: 'orig', tree: { dir: null }, search: '' },
    { id: 'base', site: 'rewrite', tree: { dir: siteDir, search: '' }, search: '' },
    { id: 'aa', site: 'rewrite', tree: { dir: siteDir, search: '' }, search: '' },
  ];
  if (plan.kept.includes('look')) out.push({ id: 'look', site: 'rewrite', tree: { dir: siteDir, search: lookSearch }, search: lookSearch });
  if (plan.kept.includes('v2')) out.push({ id: 'v2', site: 'rewrite', tree: { dir: siteDir, search: '?preset=v2-proved' }, search: '?preset=v2-proved' });
  return out;
}

/** Run the leg. Returns the result object the report reads (same shape as the macOS leg's, `leg: 'sim'`). */
export async function runSimCadence({ siteDir, lookSearch, reps = 6, settleMs = 2500, log = (s) => console.error(s) }) {
  const plan = sessionPlan(lookSearch);
  const arms = simArms(plan, siteDir, lookSearch);
  const device = findDevice();
  const started = Date.now();
  const rows = [];
  let refused = false;
  let ua = '';
  await withSession(async (ctx) => {
    for (let rep = 0; rep < reps && !refused; rep++) {
      for (const a of orderFor(arms, rep)) {
        for (const win of ['hero', 'end']) {
          const t0 = Date.now();
          ctx.setArm(a.id);
          await loadFresh(ctx.c, { clock: 'pinned', settleMs });
          const info = await pageInfo(ctx.c);
          ua = info.ua;
          const want = ctx.armHash(a.id);
          const ident = runCheck([{ site: a.site, want, config: info.fw?.configHash ?? null, mode: info.fw?.mode ?? null }]);
          const row = { arm: a.id, window: win, rep, mode: 'events', config: info.fw?.configHash ?? null, fwMode: info.fw?.mode ?? null };
          if (ident !== 'ok') {
            refused = true;
            rows.push({ ...row, ok: false, reason: 'refused:config', profiles: null });
            log(`webkit sim ${a.id} ${win}: REFUSED config (${JSON.stringify(info.fw)})`);
            break;
          }
          await ctx.c.evaluate(RECORDER_SRC);
          if (win === 'end') await ctx.c.runAsync(TO_END_JS);
          const tl = await startTimeline(ctx.c);
          const rec = await ctx.c.runAsync(win === 'hero' ? heroJs(HERO_BURST) : endJs(END_PUSH), { pollMs: 250 });
          await tl.stop();
          const pw = profileWindow(pageOf(rec, toHundredths), tl.top);
          const ivs = intervalsOf(rec.ts);
          rows.push({ ...row, frames: rec.ts.length, hitches: hitches(ivs), ivs, ok: pw.ok, reason: pw.reason ?? null, off: pw.off ?? null, offA: pw.offA ?? null, offB: pw.offB ?? null, profiles: pw.profiles, records: tl.top.length });
          log(`webkit sim rep ${rep} ${a.id} ${win}: ${rec.ts.length} frames, ${tl.top.length} records, window ${pw.ok ? 'kept' : `refused (${pw.reason})`} in ${Date.now() - t0} ms`);
        }
        if (refused) break;
      }
    }
  }, { keep: true, arms: Object.fromEntries(arms.map((a) => [a.id, a.tree])), log });
  return {
    leg: 'sim', engine: 'mobile-safari', runtime: device.runtime, device: device.name, ua, width: 430, search: lookSearch, reps, cadenceReps: 0,
    plan: { kept: plan.kept, dropped: plan.dropped, flags: plan.flags }, arms: arms.map((a) => a.id),
    hero: HERO_BURST, end: END_PUSH, refused, wallSeconds: Math.round((Date.now() - started) / 1000), rows,
  };
}
