// Glue (I/O only, no decision): reads the webkit-sim artifacts of the four arms (gh run download --pattern 'webkit-sim-r*')
// and writes packages/contracts/golden/parts/nav-fixed-counts.webkit-passes.json, the raw per-step counts the Lean module Fw.Parts.NavFixedCounts reduces.
// Usage: node extract.mjs <out.json> <arm>=<runId>:<dir> ...   (dir holds webkit-sim-r1..r3/r<n>-session-1.json)
import fs from 'node:fs';

const TYPES = ['Layout', 'RecalculateStyles', 'FunctionCall', 'Composite'];

const [out, ...specs] = process.argv.slice(2);
const arms = [];
for (const spec of specs) {
  const [arm, rest] = spec.split('=');
  const [run, dir] = rest.split(':');
  const passes = [];
  for (let vm = 1; vm <= 3; vm++) {
    const p = `${dir}/webkit-sim-r${vm}/r${vm}-session-1.json`;
    if (!fs.existsSync(p)) continue;
    const j = JSON.parse(fs.readFileSync(p, 'utf8'));
    j.passes.forEach((ps, i) => {
      const s = ps.scroll;
      if (!s || !s.reduced || !ps.census) return;
      const names = s.reduced.countTypes;
      const ix = TYPES.map((t) => names.indexOf(t));
      if (ix.some((k) => k < 0)) throw new Error(`countTypes of ${p} lacks one of ${TYPES}`);
      passes.push({
        vm,
        pass: i + 1,
        vh: ps.info.vh,
        maxY: s.info.maxY,
        ys: s.ys,
        steps: s.reduced.perStep.map((row) => ix.map((k) => row[k])),
        census: ps.census.map((c) => [c.requestedY, c.layerCount, c.memoryBytes]),
      });
    });
  }
  arms.push({ arm, run: Number(run), types: TYPES, passes });
}
fs.writeFileSync(out, JSON.stringify({ schema: 'nav-fixed-counts/1', arms }) + '\n');
