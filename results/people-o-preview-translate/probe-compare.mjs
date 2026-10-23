#!/usr/bin/env node
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
