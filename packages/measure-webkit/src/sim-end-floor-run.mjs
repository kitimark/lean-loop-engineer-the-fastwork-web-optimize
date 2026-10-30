// sim-end-floor run: the Simulator session loop. Per round and arm (the arm order rotated by the round): a fresh load of that arm's
// prerendered tree, a Timeline recording over the page script (scroll to the end, settle, N rAF frames; up one viewport and back, settle,
// N rAF frames), then the window tally per stage. Recording only; the verdicts are sim-end-floor.mjs (Lean Fw.Device.SimEndFloor).
import { withSession } from './session.mjs';
import { loadFresh, pageInfo } from './page.mjs';
import { findDevice } from './sim.mjs';
import { reconnect } from './wip.mjs';
import { attempts, T } from './timeouts.mjs';
import { startTimeline } from './timeline.mjs';
import { ARMS, STAGES, WIN_RAF, endFloorJs, windowOf } from './sim-end-floor.mjs';

export const SCHEMA = 'fw.webkit.endfloor/1';

/** Arm order of round r: the list rotated by r (round 0 = as given). */
export const rotate = (xs, r) => xs.map((_, i) => xs[(i + r) % xs.length]);

export const armTrees = (siteDir) => Object.fromEntries(ARMS.map((a) => [a.id, { dir: siteDir, search: a.search }]));

export async function runEndFloor({ siteDir, rounds = 3, settleMs = 2500, onProgress = null, onRound = null, log = (s) => console.error(s) }) {
  const device = findDevice();
  const started = Date.now();
  const out = [];
  const meta = { runtime: device.runtime, device: device.name, ua: '', winRaf: WIN_RAF, settleMs };
  let error = null;
  const snapshot = () => ({ schema: SCHEMA, meta, incomplete: error, wallSeconds: Math.round((Date.now() - started) / 1000), rounds: out });

  const oneArm = async (ctx, id) => {
    ctx.setArm(id);
    // the page resolves its config from location.search at run time, so the reload must carry the arm's query; the server answers "/" with the arm's HTML
    const search = ARMS.find((a) => a.id === id).search;
    await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + search)}); scrollTo({ top: 0, behavior: 'instant' }); location.search`);
    await loadFresh(ctx.c, { clock: 'pinned', settleMs });
    const info = await pageInfo(ctx.c);
    meta.ua = info.ua;
    const want = ctx.armHash(id);
    if (info.fw?.configHash !== want) throw new Error(`arm ${id}: page config ${info.fw?.configHash} is not the wanted ${want}`);
    const tl = await startTimeline(ctx.c);
    let page;
    try { page = await ctx.c.runAsync(endFloorJs({ settleMs }), { pollMs: 1000, timeoutMs: T(180000) }); } catch (e) { await tl.stop().catch(() => {}); throw e; }
    const rows = await tl.stop();
    const arm = { config: info.fw?.configHash ?? null, mode: info.fw?.mode ?? null, hydrated: info.fw?.hydrated ?? null, maxY: page.maxY, anims: page.anims, animsBack: page.animsBack, animsPaused: page.animsPaused };
    for (const stage of STAGES) arm[stage] = { ...windowOf(rows, stage, page[stage].raf), cls: page[stage].cls, y: page[stage].y, pageMs: page[stage].pageMs };
    return arm;
  };

  try {
    await withSession(async (ctx) => {
      await reconnect(ctx, { log });
      for (let round = 0; round < rounds; round++) {
        const r = { round: round + 1, order: rotate(ARMS, round).map((a) => a.id), arms: {} };
        out.push(r);
        for (const id of r.order) {
          let got = null;
          for (let attempt = 1; !got; attempt++) {
            await ctx.check?.();
            try { got = await oneArm(ctx, id); } catch (e) {
              if (attempt >= attempts()) throw e;
              log(`  end-floor ${id} round ${round + 1} attempt ${attempt} failed (${e.message}); reconnecting and retrying from a fresh load`);
              await reconnect(ctx, { log });
            }
          }
          r.arms[id] = got;
          log(`end-floor round ${round + 1} ${id}: ${STAGES.map((s) => `${s} raf ${got[s].raf} seen ${got[s].seen} recalcs ${got[s].recalcs}`).join('; ')}`);
          onProgress?.(snapshot());
        }
        onRound?.(round + 1, rounds, snapshot());
      }
    }, { keep: true, arms: armTrees(siteDir), log });
  } catch (e) {
    error = e.message;
    log(`end-floor: INCOMPLETE after ${out.length} rounds (${error})`);
  }
  return snapshot();
}
