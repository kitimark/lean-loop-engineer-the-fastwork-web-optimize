// Determinism classes over N runs of the same profile and target (harness self-check, not a verdict).
//   node src/classes.mjs out/P/a/counts.json out/P/b/counts.json out/P/c/counts.json [--md]
// For every count type, against the first run: the largest number of frames that differ, the spread of the run total
// (max - min), and the class:
//   deterministic  0 frames differ in every pair (the type is identical frame by frame)
//   stable         at most 2% of the frames differ and the total spread is at most max(3, 0.2% of the mean total)
//   shifting       more frames differ, but the total spread is at most max(3, 2% of the mean total): work moves by one
//                  frame (an event handled in frame k or k+1), run totals can be trusted
//   quarantined    GC-bound types that differ, or a total that moves more than 2%
// Also checked: byte identity of the files, equal meta, equal frame count and scrollY per frame.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const files = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const md = process.argv.includes('--md');
const bufs = files.map((f) => readFileSync(f));
const runs = bufs.map((b) => JSON.parse(b));
const n = runs[0].frames.length;
const types = new Set();
for (const r of runs) for (const f of r.frames) for (const k of Object.keys(f.counts)) types.add(k);
// GC-bound by nature (collection timing, not page work): always quarantined, whatever one run shows.
const GC_BOUND = new Set(['metric.Nodes', 'metric.LayoutObjects', 'metric.Documents', 'metric.Frames', 'metric.Resources', 'metric.JSEventListeners', 'trace.Layer.deleted', 'trace.MinorGC', 'trace.MajorGC']);
const rows = [];
for (const k of [...types].sort()) {
  let maxDiff = 0;
  const totals = runs.map((r) => r.frames.reduce((s, f) => s + (f.counts[k] ?? 0), 0));
  for (let j = 1; j < runs.length; j++) {
    let d = 0;
    for (let i = 0; i < n; i++) if ((runs[0].frames[i].counts[k] ?? 0) !== (runs[j].frames[i]?.counts[k] ?? 0)) d++;
    maxDiff = Math.max(maxDiff, d);
  }
  const spread = Math.max(...totals) - Math.min(...totals);
  const mean = totals.reduce((a, b) => a + b, 0) / totals.length;
  const cls = GC_BOUND.has(k) && maxDiff > 0 ? 'quarantined' : maxDiff === 0 ? 'deterministic'
    : maxDiff <= 0.02 * n && spread <= Math.max(3, 0.002 * Math.abs(mean)) ? 'stable'
    : spread <= Math.max(3, 0.02 * Math.abs(mean)) ? 'shifting' : 'quarantined';
  rows.push({ type: k, cls, maxDiffFrames: maxDiff, spread, totals });
}
const sameFrames = runs.every((r) => r.frames.length === n && r.frames.every((f, i) => f.scrollY === runs[0].frames[i].scrollY && f.phase === runs[0].frames[i].phase));
const metaEqual = runs.every((r) => JSON.stringify(r.meta) === JSON.stringify(runs[0].meta));
console.log(`runs ${runs.length}, frames ${n}, byte-identical files: ${bufs.every((b) => b.equals(bufs[0]))} (sha256 ${bufs.map((b) => createHash('sha256').update(b).digest('hex').slice(0, 8)).join(' ')}), meta equal: ${metaEqual}, phase+scrollY equal per frame: ${sameFrames}`);
if (md) {
  for (const cls of ['deterministic', 'stable', 'shifting', 'quarantined']) {
    const list = rows.filter((r) => r.cls === cls);
    console.log(`| ${cls} | ${list.map((r) => (cls === 'deterministic' ? r.type : `${r.type} (${r.maxDiffFrames} fr, spread ${r.spread})`)).join(', ')} |`);
  }
} else {
  for (const r of rows) console.log(`${r.cls.padEnd(13)} ${r.type.padEnd(40)} framesDiffering<=${String(r.maxDiffFrames).padStart(3)} totals ${r.totals.join('/')}`);
}
