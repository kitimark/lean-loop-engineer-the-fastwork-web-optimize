// usage: node gaps.mjs <probes.jsonl> [minGapS]   the sampler's gaps above minGapS (default 60) with swap-outs and free memory around them
import { readFileSync } from 'node:fs';

const [file, min = '60'] = process.argv.slice(2);
const rows = readFileSync(file, 'utf8').trim().split('\n').map((l) => JSON.parse(l)).sort((a, b) => a.atMs - b.atMs);
for (let i = 1; i < rows.length; i++) {
  const g = (rows[i].atMs - rows[i - 1].atMs) / 1000;
  if (g <= Number(min)) continue;
  const at = new Date(rows[i - 1].atMs).toISOString().slice(11, 19);
  console.log(`${at} gap ${g.toFixed(0)}s swapOuts ${rows[i - 1].swapOuts} -> ${rows[i].swapOuts} (+${rows[i].swapOuts - rows[i - 1].swapOuts}) free ${rows[i - 1].freePct}% -> ${rows[i].freePct}%`);
}
console.log(`n=${rows.length}`);
