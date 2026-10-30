import { withSession } from './session.mjs';
import { loadFresh, pageInfo } from './page.mjs';
import { findDevice, simctlAsync, SAFARI } from './sim.mjs';
import { reconnect } from './wip.mjs';
import { attempts, T } from './timeouts.mjs';
import { startTimeline } from './timeline.mjs';
import { ARMS, STAGES, WIN_RAF, endFloorJs, windowOf } from './sim-end-floor.mjs';

export const SCHEMA = 'fw.webkit.endfloor/1';

export const rotate = (xs, r) => xs.map((_, i) => xs[(i + r) % xs.length]);

export const armTrees = (siteDir) => Object.fromEntries(ARMS.map((a) => [a.id, a.blank ? { blank: true } : { dir: siteDir, search: a.search }]));

const PREF_KEYS = /Threaded|ScrollDriven/i;

/** What the Simulator holds as an override of the threaded scroll-driven preferences: matching lines of the Safari and global defaults (empty = no override). */
export async function prefProbe(udid) {
  const out = {};
  for (const [name, domain] of [['safari', SAFARI], ['global', '-g']]) {
    const r = await simctlAsync(['spawn', udid, 'defaults', 'read', domain], { timeoutMs: 30000 }).catch((e) => ({ status: 1, stdout: '', stderr: e.message }));
    out[name] = r.status === 0 ? String(r.stdout).split('\n').filter((l) => PREF_KEYS.test(l)).map((l) => l.trim()) : [`read failed: ${String(r.stderr || r.stdout).trim().slice(0, 120)}`];
  }
  return out;
}

export async function runEndFloor({ siteDir, rounds = 3, rotateBy = 0, settleMs = 2500, onProgress = null, onRound = null, log = (s) => console.error(s) }) {
  const device = findDevice();
  const started = Date.now();
  const out = [];
  const meta = { runtime: device.runtime, device: device.name, ua: '', winRaf: WIN_RAF, settleMs, build: process.env.GITHUB_SHA ?? 'local', rotateBy, prefOverrides: null };
  let error = null;
  const snapshot = () => ({ schema: SCHEMA, meta, incomplete: error, wallSeconds: Math.round((Date.now() - started) / 1000), rounds: out });

  const oneArm = async (ctx, id) => {
    ctx.setArm(id);
    const spec = ARMS.find((a) => a.id === id);
    const search = spec.search;
    await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + search)}); scrollTo({ top: 0, behavior: 'instant' }); location.search`);
    await loadFresh(ctx.c, { clock: 'pinned', settleMs });
    const info = await pageInfo(ctx.c);
    meta.ua = info.ua;
    const want = ctx.armHash(id);
    if ((info.fw?.configHash ?? null) !== want) throw new Error(`arm ${id}: page config ${info.fw?.configHash} is not the wanted ${want}`);
    const tl = await startTimeline(ctx.c);
    let page;
    try { page = await ctx.c.runAsync(endFloorJs({ settleMs, act: spec.act ?? null }), { pollMs: 1000, timeoutMs: T(180000) }); } catch (e) { await tl.stop().catch(() => {}); throw e; }
    const rows = await tl.stop();
    const arm = { config: info.fw?.configHash ?? null, mode: info.fw?.mode ?? null, hydrated: info.fw?.hydrated ?? null, maxY: page.maxY, anims: page.anims, animsBack: page.animsBack, animsPaused: page.animsPaused, animsActed: page.animsActed, cancelled: page.cancelled };
    for (const stage of STAGES) arm[stage] = { ...windowOf(rows, stage, page[stage].raf), cls: page[stage].cls, y: page[stage].y, pageMs: page[stage].pageMs };
    return arm;
  };

  try {
    await withSession(async (ctx) => {
      await reconnect(ctx, { log });
      meta.prefOverrides = await prefProbe(device.udid);
      log(`end-floor: preference overrides ${JSON.stringify(meta.prefOverrides)}`);
      for (let round = 0; round < rounds; round++) {
        const r = { round: round + 1, order: rotate(ARMS, rotateBy + round).map((a) => a.id), arms: {} };
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
