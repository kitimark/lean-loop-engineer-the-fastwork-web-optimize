import fs from 'node:fs';

// Usage: node extract-chromium.mjs <store> <out.json> base=<runId>:<runDirPrefix> flag=<runId>:<runDirPrefix>
// The hero-exit window is the zones y00000 and y00500 (scrollY 0 to 1000; the exit runs over 0 to 1vh = 932 px).
const KEYS = ['trace.Layout', 'trace.Layout.totalObjects', 'trace.Layout.dirtyObjects', 'trace.Layout.partial',
  'trace.UpdateLayoutTree', 'trace.InvalidateLayout', 'metric.LayoutObjects'];
const WINDOW = ['y00000', 'y00500'];

const [store, out, ...specs] = process.argv.slice(2);
const sum = (zs, k) => zs.reduce((a, q) => a + (q.sums[k] ?? 0), 0);
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
    const win = z.zones.filter((q) => WINDOW.includes(q.id));
    passes.push({
      vm,
      window: { frames: win.reduce((a, q) => a + q.frames, 0), v: KEYS.map((k) => sum(win, k)) },
      all: { frames: z.zones.reduce((a, q) => a + q.frames, 0), v: KEYS.map((k) => sum(z.zones, k)) },
      zones: z.zones.map((q) => ({ id: q.id, frames: q.frames, v: KEYS.map((k) => q.sums[k] ?? 0) })),
    });
  }
  arms.push({ arm, run: Number(run), sha: manifest.gitSha, fw: manifest.fw, profile: manifest.profile, types: KEYS, passes });
}
fs.writeFileSync(out, JSON.stringify({ schema: 'hero-relayout-boundary-chromium/1', window: WINDOW, arms }) + '\n');
