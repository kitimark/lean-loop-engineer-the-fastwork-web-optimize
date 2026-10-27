#!/usr/bin/env node
// Text maps of the probe's diff images (the render guard keeps images out of git). Each cell is one block of the page; its
// character is the share of red (differs by more than 12) pixels in it: ' ' < 5 %, '.' < 25 %, 'o' < 50 %, 'O' < 75 %, '#' >= 75 %.
// The probe's diff images paint pixels inside the nav box light blue (200, 215, 235), so they never count as red.
//   node maps.mjs <dir with the probe's img/> > maps.txt
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { decode } from '../../packages/visual-diff/src/diff.mjs';

const dir = resolve(process.argv[2]);
const COLS = 64, ROWS = 24;
const ch = (s) => (s >= 0.75 ? '#' : s >= 0.5 ? 'O' : s >= 0.25 ? 'o' : s >= 0.05 ? '.' : ' ');
for (const f of readdirSync(join(dir, 'img')).filter((n) => n.endsWith('.png') && n.includes('diff')).sort()) {
  const im = decode(readFileSync(join(dir, 'img', f)));
  console.log(`\n${f} (${im.width}x${im.height}, 64x24 cells; blank cells inside the nav box count as equal)`);
  for (let r = 0; r < ROWS; r++) {
    let line = '';
    for (let c = 0; c < COLS; c++) {
      const x0 = Math.floor((c * im.width) / COLS), x1 = Math.floor(((c + 1) * im.width) / COLS);
      const y0 = Math.floor((r * im.height) / ROWS), y1 = Math.floor(((r + 1) * im.height) / ROWS);
      let red = 0, n = 0;
      for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const i = 4 * (y * im.width + x); n++; if (im.data[i] === 220 && im.data[i + 1] === 40) red++; }
      line += ch(n ? red / n : 0);
    }
    console.log(`|${line}|`);
  }
}
