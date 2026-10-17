// Run-to-run comparison of two counts.json files (the harness self-check, not a verdict).
//   node src/compare.mjs out/swipe-v1/a/counts.json out/swipe-v1/b/counts.json
// Prints: byte identity of the files, then for every count type the number of frames whose value differs, the largest
// absolute difference, and the difference of the run totals. A count type with zero differing frames is
// "deterministic" in the sense of PLAN V-i for these two runs; the README defines stable and quarantined.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const [fa, fb] = process.argv.slice(2).filter((a) => a !== '--');
const ta = readFileSync(fa), tb = readFileSync(fb);
const sha = (b) => createHash('sha256').update(b).digest('hex');
const a = JSON.parse(ta), b = JSON.parse(tb);
console.log(`file a sha256 ${sha(ta).slice(0, 16)}  b sha256 ${sha(tb).slice(0, 16)}  byte-identical: ${ta.equals(tb)}`);
const types = new Set();
for (const f of [...a.frames, ...b.frames]) for (const k of Object.keys(f.counts)) types.add(k);
const rows = [];
let total = 0;
for (const k of [...types].sort()) {
  let differing = 0, maxAbs = 0, sa = 0, sb = 0, firstDiff = null;
  const n = Math.max(a.frames.length, b.frames.length);
  for (let i = 0; i < n; i++) {
    const va = a.frames[i]?.counts[k] ?? 0, vb = b.frames[i]?.counts[k] ?? 0;
    sa += va; sb += vb;
    if (va !== vb) { differing++; maxAbs = Math.max(maxAbs, Math.abs(va - vb)); firstDiff ??= i; }
  }
  total += sa;
  rows.push({ type: k, framesDiffering: differing, maxAbsDiff: maxAbs, totalA: sa, totalB: sb, firstDiffFrame: firstDiff });
}
const w = Math.max(...rows.map((r) => r.type.length));
console.log(`${'type'.padEnd(w)}  differing/${a.frames.length}  maxAbs  totalA  totalB  firstDiff`);
for (const r of rows) console.log(`${r.type.padEnd(w)}  ${String(r.framesDiffering).padStart(10)}  ${String(r.maxAbsDiff).padStart(6)}  ${String(r.totalA).padStart(6)}  ${String(r.totalB).padStart(6)}  ${r.firstDiffFrame ?? '-'}`);
const rl = new Set([...Object.keys(a.runLevel), ...Object.keys(b.runLevel)]);
for (const k of [...rl].sort()) console.log(`runLevel ${k}: a=${a.runLevel[k] ?? 0} b=${b.runLevel[k] ?? 0}`);
const metaSame = JSON.stringify(a.meta) === JSON.stringify(b.meta);
console.log(`meta equal: ${metaSame}; frames a/b: ${a.frames.length}/${b.frames.length}; scrollY equal: ${a.frames.every((f, i) => f.scrollY === b.frames[i]?.scrollY)}`);
if (process.argv.includes('--json')) console.log(JSON.stringify(rows));
// --show TYPE[,TYPE]: list the frames where a type differs, with both values and the scrollY.
const si = process.argv.indexOf('--show');
if (si >= 0) {
  for (const t of process.argv[si + 1].split(',')) {
    const lines = [];
    for (let i = 0; i < Math.max(a.frames.length, b.frames.length); i++) {
      const va = a.frames[i]?.counts[t] ?? 0, vb = b.frames[i]?.counts[t] ?? 0;
      if (va !== vb) lines.push(`${i}@y${a.frames[i]?.scrollY}:${va}/${vb}`);
    }
    console.log(`${t}: ${lines.join(' ')}`);
  }
}
