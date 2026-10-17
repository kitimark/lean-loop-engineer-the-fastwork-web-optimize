// Determinism classes over N runs of the same profile and target (harness self-check, not a verdict), decided by
// fwcore (Lean Fw.Measure.SelfCheck, op measure.selfCheck; nothing decided here).
//   node src/classes.mjs out/P/a/counts.json out/P/b/counts.json out/P/c/counts.json [--md]
// For every count type, against the first run: the largest number of frames that differ, the spread of the run total
// (max - min), and the class (thresholds and the GC-bound list live in Lean: SelfCheck.harness):
//   deterministic  0 frames differ in every pair (the type is identical frame by frame)
//   stable         at most 2% of the frames differ and the total spread is at most max(3, 0.2% of the mean total)
//   shifting       more frames differ, but the total spread is at most max(3, 2% of the mean total): work moves by one
//                  frame (an event handled in frame k or k+1), run totals can be trusted
//   quarantined    GC-bound types that differ, or a total that moves more than 2%
// Also printed: byte identity of the files and equal meta (raw file facts), and fwcore's phase+scrollY check per frame.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { call } from './fwcore.mjs';

const files = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const md = process.argv.includes('--md');
const bufs = files.map((f) => readFileSync(f));
const runs = bufs.map((b) => JSON.parse(b));
const { rows, frames: n, framesAligned } = call([{ op: 'measure.selfCheck', runs: runs.map((r) => ({ frames: r.frames })) }])[0];
const metaEqual = runs.every((r) => JSON.stringify(r.meta) === JSON.stringify(runs[0].meta));
console.log(`runs ${runs.length}, frames ${n}, byte-identical files: ${bufs.every((b) => b.equals(bufs[0]))} (sha256 ${bufs.map((b) => createHash('sha256').update(b).digest('hex').slice(0, 8)).join(' ')}), meta equal: ${metaEqual}, phase+scrollY equal per frame: ${framesAligned}`);
if (md) {
  for (const cls of ['deterministic', 'stable', 'shifting', 'quarantined']) {
    const list = rows.filter((r) => r.class === cls);
    console.log(`| ${cls} | ${list.map((r) => (cls === 'deterministic' ? r.type : `${r.type} (${r.maxDiffFrames} fr, spread ${r.spread})`)).join(', ')} |`);
  }
} else {
  for (const r of rows) console.log(`${r.class.padEnd(13)} ${r.type.padEnd(40)} framesDiffering<=${String(r.maxDiffFrames).padStart(3)} totals ${r.totals.join('/')}`);
}
