import { withSession } from '../session.mjs';
import { loadFresh, pageInfo } from '../page.mjs';
import { startTimeline } from '../timeline.mjs';
import { findDevice } from '../sim.mjs';
import { sessionPlan } from '../device-arms.mjs';
import { reconnect } from '../wip.mjs';
import { attempts, T } from '../timeouts.mjs';
import { RECORDER_SRC, TO_END_JS, heroJs, endJs, pageOf, intervalsOf } from './recorder.mjs';
import { profileWindow, toHundredths } from './reduce.mjs';
import { orderFor, HERO_BURST } from '../../../gate-breakpoints/src/smooth/schedule.mjs';
import { BOUND_JS, endPushFor } from '../../../gate-breakpoints/src/smooth/bound.mjs';
import { hitches, hundredthsFrom } from '../../../gate-breakpoints/src/smooth/reduce.mjs';
import { runCheck } from '../../../gate-breakpoints/src/trajectory/reduce.mjs';

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

export async function runSimCadence({ siteDir, lookSearch, reps = 6, settleMs = 2500, only, holdMs, log = (s) => console.error(s) }) {
  const end = endPushFor(holdMs);
  const plan = only ? { kept: [], dropped: [], flags: {} } : sessionPlan(lookSearch);
  const arms = simArms(plan, siteDir, lookSearch, only);
  const device = findDevice();
  const started = Date.now();
  const rows = [];
  const raws = [];
  let refused = false;
  let error = null;
  let ua = '';

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
    const tl = await startTimeline(ctx.c, { stopMs: T(7500) });
    const rec = await ctx.c.runAsync(win === 'hero' ? heroJs(HERO_BURST) : endJs(end), { pollMs: 250 });
    await tl.stop();
    const pw = profileWindow(pageOf(rec, toHundredths), tl.top);
    raws.push({ arm: a.id, window: win, rep, raw: pw.raw });
    return { row: { ...row, frames: rec.ts.length, hitches: hitches(intervalsOf(rec.ts)), ivs: intervalsOf(rec.ts), th: hundredthsFrom(rec.ts), ok: pw.ok, reason: pw.reason ?? null, off: pw.off ?? null, offA: pw.offA ?? null, offB: pw.offB ?? null, profiles: pw.profiles, records: tl.top.length } };
  };

  try {
    await withSession(async (ctx) => {
      for (let rep = 0; rep < reps && !refused; rep++) {
        for (const a of orderFor(arms, rep)) {
          for (const win of ['hero', 'end']) {
            const t0 = Date.now();
            let got = null;
            for (let attempt = 1; !got; attempt++) {
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
            log(`webkit sim rep ${rep} ${a.id} ${win}: ${got.row.frames} frames, ${got.row.records} records, window ${got.row.ok ? 'kept' : `refused (${got.row.reason})`} in ${Date.now() - t0} ms`);
          }
          if (refused) break;
        }
      }
    }, { keep: true, arms: Object.fromEntries(arms.map((a) => [a.id, a.tree])), log });
  } catch (e) {
    error = e.message;
    log(`webkit sim: INCOMPLETE after ${rows.length} windows (${error})`);
  }
  return {
    leg: 'sim', engine: 'mobile-safari', runtime: device.runtime, device: device.name, ua, width: 430, search: lookSearch, reps, cadenceReps: 0,
    plan: { kept: plan.kept, dropped: plan.dropped, flags: plan.flags }, arms: arms.map((a) => a.id),
    hero: HERO_BURST, end, refused, incomplete: error, wallSeconds: Math.round((Date.now() - started) / 1000), rows, raws,
  };
}
