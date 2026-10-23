#!/usr/bin/env node
// Open-card probe of profile people-o-hover (TS stand-in: an equality of two lists, no Lean golden). Usage:
//   node probe-compare.mjs a=<counts.json> b=<counts.json>
// Both files carry `cardProbe.frames` (run.mjs probe pass: per frame the card rect, the rect of its face, the inline top/left/translate,
// a PNG hash of the viewport and a PNG hash of the pixels around the card). Prints, over all frames of the plan, how many frames differ
// in the card rect, the card pixels (frames where the card is found in both) and the viewport pixels, how many frames of b use the
// translate property, and the largest rect difference. Exit 0 iff the card was found in a frame and rect and card pixels agree in every
// frame of phase `scroll` where it is found in both (the opening animation of the card runs in the earlier phases and differs by
// hundredths of a pixel from run to run, so those frames are reported as `otherMaxRectDeltaPx` only); the viewport hash is reported only
// (it also holds the rest of the page).
import { readFileSync } from 'node:fs';

const [a, b] = process.argv.slice(2).map((arg) => JSON.parse(readFileSync(arg.split('=')[1], 'utf8')).cardProbe?.frames);
if (!a || !b || a.length !== b.length) { console.error('both files need cardProbe.frames of the same length'); process.exit(2); }
let both = 0, translated = 0, rectBad = 0, cardBad = 0, pageBad = 0, maxDelta = 0, otherDelta = 0;
const first = [];
a.forEach((x, i) => {
  const y = b[i];
  if (y.found && y.translate) translated++;
  if (x.png !== y.png) pageBad++;
  if (x.found !== y.found) { rectBad++; first.push({ n: i, phase: x.phase, why: 'found differs' }); return; }
  if (!x.found) return;
  const delta = Math.max(...x.rect.map((v, k) => Math.abs(v - y.rect[k])));
  if (x.phase !== 'scroll') { otherDelta = Math.max(otherDelta, delta); return; }
  both++;
  maxDelta = Math.max(maxDelta, delta);
  const rectEq = delta === 0;
  const cardEq = x.cardPng === y.cardPng;
  if (!rectEq) rectBad++;
  if (!cardEq) cardBad++;
  if ((!rectEq || !cardEq) && first.length < 5) first.push({ n: i, phase: x.phase, y: x.y, rectA: x.rect, rectB: y.rect, cardEq });
});
console.log(JSON.stringify({ frames: a.length, scrollFramesCardInBoth: both, bFramesWithTranslate: translated, rectDiffFrames: rectBad, cardPixelDiffFrames: cardBad, viewportPixelDiffFrames: pageBad, maxRectDeltaPx: maxDelta, otherMaxRectDeltaPx: otherDelta, first }));
process.exit(both > 0 && rectBad === 0 && cardBad === 0 ? 0 : 1);
