import { readFileSync, writeFileSync } from 'node:fs';
import { readArm } from '../../packages/measure-chromium/src/offscreen-windows.mjs';

const [dir, out] = process.argv.slice(2);
const runs = readArm(dir, 30);
const rows = runs.map((r) => {
  const counts = JSON.parse(readFileSync(r.path, 'utf8'));
  const inp = counts.meta?.input ?? {};
  const total = counts.frames.length;
  const lastSwipe = Math.max(...counts.frames.map((f, i) => (f.phase === 'tail' ? -1 : i)));
  const row = {
    path: r.path.replace(dir, ''), total, readerEnd: r.end, lastSwipeFrame: lastSwipe, afterEnd: lastSwipe - r.end,
    endReason: inp.endReason, endFrame: inp.endFrame, tailFrames: inp.tailFrames, endGapPx: inp.endGapPx,
    windows: Object.fromEntries(r.windows.map((w) => [w.name, w.vec.n])),
  };
  return row;
});
for (const r of rows) console.log(JSON.stringify(r));
if (out) writeFileSync(out, JSON.stringify(rows, null, 1) + '\n');
