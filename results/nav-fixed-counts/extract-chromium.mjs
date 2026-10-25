// Glue (I/O only, no decision): reads the zones.json files of the filed Chromium runs (fw run store) and writes
// packages/contracts/golden/parts/nav-fixed-counts.chromium-bands.json, the per-band sums the Lean module Fw.Parts.NavFixedCounts reduces.
// Usage: node extract-chromium.mjs <store dir> <out.json> <arm>=<runId>:<store run dir prefix> ...
import fs from 'node:fs';

const KEYS = ['trace.Layout', 'trace.UpdateLayoutTree', 'trace.FunctionCall', 'trace.cc.Draw', 'census.layers'];

const [store, out, ...specs] = process.argv.slice(2);
const arms = [];
for (const spec of specs) {
  const [arm, rest] = spec.split('=');
  const [run, prefix] = rest.split(':');
  const dir = fs.readdirSync(`${store}/runs`).find((x) => x.startsWith(prefix));
  const manifest = JSON.parse(fs.readFileSync(`${store}/runs/${dir}/manifest.json`, 'utf8'));
  const passes = [];
  for (let vm = 1; vm <= 3; vm++) {
    const e = manifest.entries.find((x) => x.name === `chromium-counts-rewrite-r${vm}/zones.json`);
    if (!e) continue;
    const z = JSON.parse(fs.readFileSync(`${store}/objects/${e.digest.slice(0, 2)}/${e.digest.slice(2)}`, 'utf8'));
    passes.push({ vm, bands: z.zones.map((q) => ({ id: q.id, v: KEYS.map((k) => q.sums[k] ?? 0) })) });
  }
  arms.push({ arm, run: Number(run), types: KEYS, passes });
}
fs.writeFileSync(out, JSON.stringify({ schema: 'nav-fixed-counts-chromium/1', arms }) + '\n');
