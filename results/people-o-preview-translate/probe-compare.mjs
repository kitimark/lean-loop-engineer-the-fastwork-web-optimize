#!/usr/bin/env node
// Open-card probe of profile people-o-hover (TS stand-in: an equality of two lists, no Lean golden). Usage:
//   node probe-compare.mjs base=<counts.json> flag=<counts.json>
// Both files carry `cardProbe.frames` (run.mjs probe pass: per frame the card rect, inline top/left/translate and a PNG hash of the
// viewport). The script prints, per frame of the plan, whether rect and PNG hash are equal, and the number of frames where the card
// was found. Exit 0 iff every frame has equal rect and equal PNG hash and the card was found in at least one frame.
import { readFileSync } from 'node:fs';

const [base, flag] = process.argv.slice(2).map((a) => JSON.parse(readFileSync(a.split('=')[1], 'utf8')).cardProbe?.frames);
if (!base || !flag) { console.error('both files need cardProbe.frames'); process.exit(2); }
const rows = Math.max(base.length, flag.length);
const bad = [];
let found = 0, written = 0;
for (let i = 0; i < rows; i++) {
  const b = base[i], f = flag[i];
  if (!b || !f) { bad.push({ n: i, why: 'frame missing' }); continue; }
  if (b.found && f.found) found++;
  if (f.found && f.translate) written++;
  const rectEq = b.found === f.found && JSON.stringify(b.rect) === JSON.stringify(f.rect);
  const pngEq = b.png === f.png;
  if (!rectEq || !pngEq) bad.push({ n: i, phase: b.phase, y: b.y, rectBase: b.rect, rectFlag: f.rect, rectEq, pngEq });
}
const maxDelta = Math.max(0, ...base.map((b, i) => (b.found && flag[i]?.found ? Math.max(...b.rect.map((v, k) => Math.abs(v - flag[i].rect[k]))) : 0)));
console.log(JSON.stringify({ frames: rows, cardFoundInBoth: found, flagFramesWithTranslate: written, maxRectDeltaPx: maxDelta, mismatches: bad.length, first: bad.slice(0, 5) }));
process.exit(bad.length === 0 && found > 0 ? 0 : 1);
