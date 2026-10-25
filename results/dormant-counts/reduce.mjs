// Reduces filed runs (the store of `fw run`) to one record per sample: per-500 px bin count sums and, on WebKit, the layer
// census per scroll state. Glue only: the verdicts are decided by lean/Fw/Parts/DormantCounts.lean from the file this writes.
//
//   node reduce.mjs --store <.fw-console/store> --out zones.json <engine>/<name>=<run id> ...
//
// WebKit: one sample = one Simulator VM = one webkit-sim-r<n>/r<n>-session-1.json; its value in a cell is the sum over its
// two passes. Chromium: one sample = one run of the counts lane = one chromium-counts-rewrite-r<n>/zones.json (the per-frame
// sums per 500 px zone of the swipe phase, written by the lane) with its counts.json meta (viewport, last scroll position).
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { COUNT_TYPES, zones } from '../../packages/measure-webkit/src/reduce.mjs';

const args = process.argv.slice(2);
const opt = (k) => { const i = args.indexOf(k); return i < 0 ? null : args.splice(i, 2)[1]; };
const store = opt('--store');
const out = opt('--out');
const arms = args.map((a) => { const [id, runId] = a.split('='); const [engine, name] = id.split('/'); return { engine, name, runId }; });
if (!store || !out || arms.length === 0) throw new Error('usage: reduce.mjs --store <dir> --out <file> <engine>/<name>=<run id> ...');

const manifests = readdirSync(`${store}/runs`).filter((d) => existsSync(`${store}/runs/${d}/manifest.json`))
  .map((d) => JSON.parse(readFileSync(`${store}/runs/${d}/manifest.json`, 'utf8')));
const object = (digest) => JSON.parse(readFileSync(`${store}/objects/${digest.slice(0, 2)}/${digest.slice(2)}`, 'utf8'));
const METRICS = [...COUNT_TYPES, 'paintArea'];

function webkitVm(entry, vm) {
  const file = object(entry.digest);
  const bins = Object.fromEntries(METRICS.map((m) => [m, new Map()]));
  const census = new Map();
  for (const p of file.passes) {
    for (const z of zones(p.scroll.ys, p.scroll.reduced.perStep, p.scroll.reduced.perStepPaintArea)) {
      COUNT_TYPES.forEach((t, j) => bins[t].set(z.y0, (bins[t].get(z.y0) ?? 0) + z.counts[j]));
      bins.paintArea.set(z.y0, (bins.paintArea.get(z.y0) ?? 0) + z.paintArea);
    }
    for (const c of p.census) {
      const o = census.get(c.requestedY) ?? { y: c.requestedY, layers: 0, bytes: 0 };
      o.layers += c.layerCount;
      o.bytes += c.memoryBytes;
      census.set(c.requestedY, o);
    }
  }
  const i = file.passes[0].info;
  return {
    vm, passes: file.passes.length, vh: i.vh, maxY: i.maxY,
    bins: METRICS.map((m) => ({ m, v: [...bins[m]].sort((a, b) => a[0] - b[0]) })),
    census: [...census.values()],
  };
}

function chromiumRun(m, r) {
  const find = (n) => m.entries.find((e) => e.name === `chromium-counts-rewrite-r${r}/${n}`);
  const zs = object(find('zones.json').digest);
  const meta = object(find('counts.json').digest).meta;
  const bins = new Map();
  for (const z of zs.zones) {
    const g = /^y(\d+)$/.exec(z.id);
    if (!g) continue;
    for (const [k, v] of Object.entries(z.sums)) {
      if (!bins.has(k)) bins.set(k, []);
      bins.get(k).push([Number(g[1]), v]);
    }
  }
  return {
    vm: r, passes: 1, vh: meta.innerHeightPx, maxY: meta.maxScrollPx,
    bins: [...bins].map(([m, v]) => ({ m, v: v.sort((a, b) => a[0] - b[0]) })),
    census: [],
  };
}

const result = { schema: 'fw.dormant-counts.zones/1', zonePx: 500, arms: [] };
for (const a of arms) {
  const m = manifests.find((x) => x.runId === a.runId && x.engine === a.engine);
  if (!m) throw new Error(`${a.engine} run ${a.runId} is not filed in ${store}`);
  const vms = [];
  for (const e of m.entries) {
    const g = (a.engine === 'webkit' ? /^webkit-sim-r(\d+)\/r\d+-session-1\.json$/ : /^chromium-counts-rewrite-r(\d+)\/zones\.json$/).exec(e.name);
    if (g) vms.push(a.engine === 'webkit' ? webkitVm(e, Number(g[1])) : chromiumRun(m, Number(g[1])));
  }
  vms.sort((x, y) => x.vm - y.vm);
  result.arms.push({ engine: a.engine, name: a.name, runId: a.runId, profile: m.profile, fw: m.fw, sha: m['git' + 'Sha'], vms });
}
writeFileSync(out, JSON.stringify(result) + '\n');
for (const a of result.arms) console.log(a.engine, a.name, a.runId, a.profile, 'samples', a.vms.map((v) => `${v.vm}(${v.passes}p)`).join(' '));
