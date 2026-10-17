// Per-zone baseline files of the original (task zone-baselines-chromium). GLUE ONLY: it reads one store entry
// (written by `pnpm fw ci <run id>`), asks fwcore (`measure.zoneSums`, Lean `Fw.Measure.zoneSums`) for the per-zone sums
// of every shard's frames, checks them against the `zones.json` the CI shard stored, and writes the files below.
// The zone assignment and the sums are Lean's. The cross-run reduction (lo, hi, base per zone and type, class
// attachment) is NOT done here: it is the Lean op `measure.zoneBaseline`, asked of the lead (see README in results).
//
//   node src/zone-baseline.mjs --store <dir> --target original [--sha <git sha7>] [--run <run id>] --out <dir> [--check]
//
// --store  the artifact store (default $FW_CONSOLE_DIR/store or .fw-console/store)
// --out    results dir; writes <profile>/<target>.zones.json (fw.zonebaseline.chromium/1: per shard per zone sums) and
//          <profile>/<target>.classes.json (the run's fwcore classify over its shards, copied byte for byte)
// --check  write nothing; fail if the file in --out differs from what the store gives
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { zoneSums } from './fwcore.mjs';

const args = process.argv.slice(2);
const arg = (f, d) => { const i = args.indexOf(f); return i < 0 ? d : args[i + 1]; };
const store = arg('--store', join(process.env.FW_CONSOLE_DIR ?? '.fw-console', 'store'));
const target = arg('--target', 'original');
const runId = arg('--run');
const out = arg('--out');
const check = args.includes('--check');
if (!out) { console.error('usage: zone-baseline.mjs --store <dir> --target original [--run <id>] --out <dir> [--check]'); process.exit(2); }

const manifests = readdirSync(join(store, 'runs')).map((k) => ({ k, m: JSON.parse(readFileSync(join(store, 'runs', k, 'manifest.json'), 'utf8')) }))
  .filter(({ m }) => m.engine === 'chromium' && m.target === target && (!runId || m.runId === runId));
if (manifests.length !== 1) { console.error(`expected exactly one stored ${target} run${runId ? ` ${runId}` : ''}, found ${manifests.length} (use --run)`); process.exit(2); }
const { k: key, m } = manifests[0];

const obj = (digest) => {
  const p = join(store, 'objects', digest.slice(0, 2), digest.slice(2));
  const b = readFileSync(p);
  if (createHash('sha256').update(b).digest('hex') !== digest) throw new Error(`object ${digest} does not hash to its name`);
  return b;
};
const entry = (name) => { const e = m.entries.find((x) => x.name === name); if (!e) throw new Error(`manifest has no entry ${name}`); return obj(e.digest); };
const shards = [...new Set(m.entries.map((e) => /^(r[0-9]+)\//.exec(e.name)?.[1]).filter(Boolean))].sort();

const perShard = {};
let meta;
for (const r of shards) {
  const counts = JSON.parse(entry(`${r}/counts.json`));
  const stored = JSON.parse(entry(`${r}/zones.json`));
  const h = stored.zoneHeightPx;
  const zones = zoneSums(counts.frames, h);
  if (JSON.stringify(zones) !== JSON.stringify(stored.zones)) throw new Error(`${r}: fwcore zoneSums differs from the stored zones.json`);
  perShard[r] = { frames: counts.frames.length, zones, countsSha256: createHash('sha256').update(entry(`${r}/counts.json`)).digest('hex') };
  meta ??= { zoneHeightPx: h, browser: counts.meta?.browser, viewport: counts.meta?.viewport, pageHeight: counts.meta?.pageHeight };
}

const file = {
  schema: 'fw.zonebaseline.chromium/1',
  note: 'Per-shard per-zone sums of the raw per-frame counts (Lean Fw.Measure.zoneSums). Cross-shard reduction and part attribution are not in this file.',
  storeKey: key, target, engine: 'chromium', profile: m.profile, preset: m.preset, gitSha: m.gitSha, image: m.image, runId: m.runId,
  ...meta,
  shards: perShard,
};
const text = JSON.stringify(file, null, 1) + '\n';
const path = join(out, m.profile, `${target}.zones.json`);
if (check) {
  if (!existsSync(path) || readFileSync(path, 'utf8') !== text) { console.error(`DIFFERS: ${path}`); process.exit(1); }
  const cp = join(out, m.profile, `${target}.classes.json`);
  if (!existsSync(cp) || !readFileSync(cp).equals(entry('classes/classes.json'))) { console.error(`DIFFERS: ${cp}`); process.exit(1); }
  console.log(`identical: ${path} and ${cp}`);
} else {
  mkdirSync(join(out, m.profile), { recursive: true });
  writeFileSync(path, text);
  writeFileSync(join(out, m.profile, `${target}.classes.json`), entry('classes/classes.json'));
  console.log(`wrote ${path} (${shards.length} shards, ${Object.values(perShard)[0].zones.length} zones)`);
}
