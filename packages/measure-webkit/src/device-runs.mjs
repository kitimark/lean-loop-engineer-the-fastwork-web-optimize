// The two measurements of a phone session on the real iPhone (I/O glue around the existing lane code).
//  - phoneCounts: the Simulator lane's determinism profile (census states, then the stepped scroll with Timeline), reduced
//    per 500 px zone by reduce.mjs; nothing new is decided here.
//  - phoneFrames: a SCRIPTED scroll (scrollTo from the page's native requestAnimationFrame, constant px/s) and the frame
//    intervals (rAF timestamp deltas). It is not a finger swipe: no touch, no compositor-driven momentum (PLAN §4.6).
import { warmUpLoad } from './perstep.mjs';
import { onePassRetrying, classifyPasses, resolveStates } from './determinism.mjs';
import { zones, COUNT_TYPES } from './reduce.mjs';
import { RAF_HELPER } from './page.mjs';
import { sleep } from './sim.mjs';

/** Counts: warm-up loads (discarded) then `passes` fresh-load passes; returns reduced data only (raw stays in `raw`). */
export async function phoneCounts(ctx, { passes, warmup, step, framesPerStep, settleMs, clock, loadFresh, log, states = '0,1500,3000,4500,max' }) {
  const readouts = [ctx.readout()];
  for (let w = 0; w < warmup; w++) await warmUpLoad(ctx, { clock, settleMs, step, framesPerStep, log, w, warmup });
  const raw = [];
  for (let i = 0; i < passes; i++) {
    log(`pass ${i + 1}/${passes}`);
    raw.push(await onePassRetrying(ctx, { states, clock, settleMs, holdMs: 1500, paintWindowMs: 2000, step, framesPerStep, mode: 'base', seek: false, seekNs: [], log }));
  }
  readouts.push(ctx.readout());
  const rows = classifyPasses(raw);
  const reduced = raw.map((p) => ({
    info: p.info,
    census: p.census.map((c) => ({ requestedY: c.requestedY, scrollY: c.scrollY, layerCount: c.layerCount, memoryBytes: c.memoryBytes, reasonCounts: c.reasonCounts, paintCountTotal: c.paintCountTotal, paintDeltaTotal: c.paintDeltaTotal })),
    steps: p.scroll.ys.length, scrollWallMs: p.scroll.scrollWallMs, total: p.scroll.reduced.total,
    zones: zones(p.scroll.ys, p.scroll.reduced.perStep, p.scroll.reduced.perStepPaintArea),
    load: p.load,
  }));
  const tally = {};
  for (const r of rows) tally[r.cls] = (tally[r.cls] || 0) + 1;
  return {
    schema: 'fw.phone.counts/1', countTypes: COUNT_TYPES, profile: { states, clock, step, framesPerStep, settleMs, warmup, passes },
    device: ctx.device, readouts, reduced, classes: rows.map((r) => ({ family: r.family, metric: r.metric, level: r.level, cls: r.cls })), classTally: tally,
    fw: raw[0].info.fw, raw,
  };
}

const FRAMES_JS = (speed) => `(async () => {
  ${RAF_HELPER}
  const maxY = document.documentElement.scrollHeight - innerHeight;
  scrollTo({ top: 0, behavior: 'instant' });
  await raf(); await raf();
  const ts = [], ys = [];
  const start = await new Promise((r) => requestAnimationFrame(r));
  await new Promise((done) => {
    const f = (t) => {
      const y = Math.min(maxY, Math.round((t - start) * ${Number(speed)} / 1000));
      scrollTo({ top: y, behavior: 'instant' });
      ts.push(Math.round(t * 100) / 100); ys.push(Math.round(scrollY * 10) / 10);
      if (y >= maxY) done(); else requestAnimationFrame(f);
    };
    requestAnimationFrame(f);
  });
  return { maxY, ts, ys };
})()`;

/** Frame statistics of one run: frame k's interval is ts[k] - ts[k-1]; it is a moving frame when scrollY differs from the previous frame's. */
export function frameStats(run, { zonePx = 500, slow = 34, bad = 50 } = {}) {
  const rows = [];
  for (let k = 1; k < run.ts.length; k++) rows.push({ dt: run.ts[k] - run.ts[k - 1], moving: run.ys[k] !== run.ys[k - 1], z: Math.floor(run.ys[k] / zonePx) });
  return rows.filter((r) => r.moving);
}
export function summarizeFrames(runs, { zonePx = 500, slow = 34, bad = 50 } = {}) {
  const all = runs.flatMap((r) => frameStats(r, { zonePx }));
  const mk = (rows) => {
    const n = rows.length, s = rows.filter((r) => r.dt > slow).length, b = rows.filter((r) => r.dt > bad).length;
    const sorted = rows.map((r) => r.dt).sort((x, y) => x - y);
    return { moving: n, over34: s, over50: b, per100Over34: n ? +(100 * s / n).toFixed(2) : null, per100Over50: n ? +(100 * b / n).toFixed(2) : null, longestMs: n ? +sorted[n - 1].toFixed(1) : null, medianMs: n ? +sorted[Math.floor(n / 2)].toFixed(2) : null };
  };
  const nz = Math.max(0, ...all.map((r) => r.z)) + 1;
  return { zonePx, thresholdsMs: { slow, bad }, total: mk(all), zones: Array.from({ length: nz }, (_, z) => ({ zone: z, y0: z * zonePx, ...mk(all.filter((r) => r.z === z)) })) };
}

/** Scripted-scroll frame timing: one discarded warm-up run, then `reps` runs, each from a fresh load. */
export async function phoneFrames(ctx, { reps, speed, settleMs, clock, loadFresh, log }) {
  const readouts = [ctx.readout()];
  const runs = [];
  for (let i = -1; i < reps; i++) {
    await loadFresh(ctx.c, { clock, settleMs, timers: 'live' });
    const r = await ctx.c.runAsync(FRAMES_JS(speed), { pollMs: 500 });
    await sleep(500);
    if (i < 0) { log('frames warm-up run discarded'); continue; }
    const d = r.ts.slice(1).map((t, k) => t - r.ts[k]).sort((a, b) => a - b);
    log(`rep ${i + 1}/${reps}: ${r.ts.length} frames, median interval ${d[Math.floor(d.length / 2)].toFixed(2)} ms, longest ${d[d.length - 1].toFixed(1)} ms`);
    runs.push({ maxY: r.maxY, ts: r.ts, ys: r.ys });
  }
  readouts.push(ctx.readout());
  return {
    schema: 'fw.phone.frames/1', kind: 'scripted scroll (rAF-driven scrollTo at constant px/s), not a finger swipe', speedPxPerS: speed,
    device: ctx.device, readouts, summary: summarizeFrames(runs), runs,
  };
}
