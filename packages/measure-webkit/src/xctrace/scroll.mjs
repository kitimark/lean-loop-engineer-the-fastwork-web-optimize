// xctrace-ci-probe: the scripted scroll of the two zones, with a wall-clock window per sweep (I/O glue; the zone rule is lag/reduce.mjs).
// Zone A = the first viewport height of the page (the hero exit), zone B = the last viewport height (the end of the page): the
// regions A and B of Fw.Measure.WebKit.zoneIx as used by the lag probe. Each rep sweeps A top-down, then jumps to B and sweeps it.
// The page's own native requestAnimationFrame paces the steps (scrollRun.mjs does the same); no animation is seeked or replaced.
// Times are epoch ms from performance.timeOrigin + performance.now(): the page's Date is pinned by loadFresh and cannot be used.
import { RAF_HELPER } from '../page.mjs';

/** The positions of one sweep: from `from` to `to` inclusive in `step` px (the last one is exactly `to`). */
export function sweepYs(from, to, step) {
  const ys = [];
  for (let y = from; y < to; y += step) ys.push(y);
  ys.push(to);
  return ys;
}

/** Sweep plan of a page: zone A = [0, vh - 1], zone B = [maxY - vh + 1, maxY] (clamped into [0, maxY]). */
export function zonePlan({ vh, maxY }, step) {
  const a1 = Math.min(vh - 1, maxY), b0 = Math.max(0, maxY - vh + 1);
  return { A: sweepYs(0, a1, step), B: sweepYs(b0, maxY, step) };
}

const SCROLL_JS = (plan, reps, frames) => `(async () => {
  ${RAF_HELPER}
  const plan = ${JSON.stringify(plan)}, reps = ${reps}, frames = ${frames};
  const now = () => performance.timeOrigin + performance.now();
  const out = [];
  for (let rep = 0; rep < reps; rep++) {
    for (const zone of ['A', 'B']) {
      const ys = plan[zone];
      scrollTo({ top: ys[0], behavior: 'instant' });
      await raf(); await raf(); await raf();
      const t = [], t0 = now();
      for (let k = 0; k < ys.length; k++) {
        scrollTo({ top: ys[k], behavior: 'instant' });
        for (let f = 0; f < frames; f++) await raf();
        t.push(Math.round(now() * 10) / 10);
      }
      out.push({ rep, zone, t0: Math.round(t0 * 10) / 10, t1: t[t.length - 1], steps: ys.length, t });
    }
  }
  scrollTo({ top: 0, behavior: 'instant' });
  return out;
})()`;

/** Run the sweeps on a loaded page. Returns [{rep, zone, t0, t1, steps, t}] with epoch-ms times. */
export async function scrollZones(c, info, { step = 25, frames = 2, reps = 4 } = {}) {
  const plan = zonePlan(info, step);
  return c.runAsync(SCROLL_JS(plan, reps, frames), { pollMs: 1000 });
}
