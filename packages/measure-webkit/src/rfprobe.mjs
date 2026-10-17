// RenderingFrame probe (improvement #8): which Timeline start configuration, if any, yields RenderingFrame records on
// iOS 27.0's Mobile Safari over ios_webkit_debug_proxy. Each configuration captures the same 3 s of activity (60 scroll
// steps of 2 rAFs, then 1 s idle) on one loaded page and counts record types. Counts only; no timing is read.
import { sleep } from './sim.mjs';
import { startTimeline } from './timeline.mjs';
import { tally } from './reduce.mjs';
import { RAF_HELPER } from './page.mjs';

const ALL = ['Timeline', 'ScriptProfiler', 'Heap', 'CPU', 'Memory', 'Animation'];
export const CONFIGS = [
  { name: 'A current: [Timeline], depth 1', opts: { instruments: ['Timeline'], depth: 1 } },
  { name: 'B no setInstruments, depth 1', opts: { instruments: null, depth: 1 } },
  { name: 'C [Timeline], default depth', opts: { instruments: ['Timeline'], depth: 0 } },
  { name: 'D [Timeline, ScriptProfiler]', opts: { instruments: ['Timeline', 'ScriptProfiler'], depth: 1 } },
  { name: 'E [Timeline, Animation]', opts: { instruments: ['Timeline', 'Animation'], depth: 1 } },
  { name: 'F all instruments', opts: { instruments: ALL, depth: 1 } },
  { name: 'G [Timeline] + setAutoCaptureEnabled(false)', opts: { instruments: ['Timeline'], depth: 1, autoCapture: false } },
];

const ACTIVITY = (n) => `(async () => { ${RAF_HELPER}
  for (let k = 0; k < ${n}; k++) { scrollTo({ top: (k % 40) * 60, behavior: 'instant' }); await raf(); await raf(); }
  await new Promise((r) => setTimeout(r, 1000)); return scrollY; })()`;

export async function probe(c, { steps = 60, log = () => {} } = {}) {
  const out = [];
  for (const cfg of CONFIGS) {
    let row;
    try {
      const tl = await startTimeline(c, cfg.opts);
      await c.runAsync(ACTIVITY(steps), { pollMs: 500 });
      await sleep(300);
      const rows = await tl.stop();
      const t = tally(rows);
      const byType = {};
      for (const r of rows) byType[r[0]] = (byType[r[0]] || 0) + 1;
      row = { name: cfg.name, renderingFrame: byType.RenderingFrame || 0, composite: t.counts.Composite, raf: t.counts.FireAnimationFrame, records: rows.length, types: Object.keys(byType).sort() };
    } catch (e) { row = { name: cfg.name, error: e.message }; }
    log(`${cfg.name}: ${row.error ? 'ERROR ' + row.error : `RenderingFrame ${row.renderingFrame}, Composite ${row.composite}, rAF ${row.raf}, ${row.records} records`}`);
    out.push(row);
    try { await c.send('Timeline.stop'); } catch { /* not running */ }
    await sleep(500);
  }
  return out;
}
