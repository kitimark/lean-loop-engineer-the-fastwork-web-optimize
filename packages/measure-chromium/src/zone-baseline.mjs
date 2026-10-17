// Per-zone baseline files of the original (tasks zone-baselines-chromium, zone-baseline-lean). GLUE ONLY: every
// reduction and decision is Lean's (fwcore); this script reads and writes files.
//
// Mode 1 (store -> zones file): reads one store entry (written by `pnpm fw ci <run id>`), asks fwcore
// (`measure.zoneSums`, Lean `Fw.Measure.zoneSums`) for the per-zone sums of every shard's frames, checks them against
// the `zones.json` the CI shard stored, and writes <profile>/<target>.zones.json and .classes.json.
//
//   node src/zone-baseline.mjs --store <dir> --target original [--run <run id>] --out <dir> [--check]
//
// --store  the artifact store (default $FW_CONSOLE_DIR/store or .fw-console/store)
// --out    results dir; writes <profile>/<target>.zones.json (fw.zonebaseline.chromium/1: per shard per zone sums) and
//          <profile>/<target>.classes.json (the run's fwcore classify over its shards, copied byte for byte)
// --check  write nothing; fail if the file in --out differs from what the store gives
//
// Mode 2 (zones file -> baseline): sends the shards of <out>/<profile>/<target>.zones.json and the profile's frozen
// class table to fwcore `measure.zoneBaseline` (Lean `Fw.Measure.ZoneBaseline.zoneBaseline`: refuses runs whose
// zone structure differs; per zone and type the frozen class or `unlisted`, perRun, lo, hi, base = sorted index
// floor((n-1)/2); whole-run totals; detDrift) and writes <out>/<profile>/<target>.baseline.json. Re-run it after
// every refreeze of the class table (the classes in the file are those of the table it names by sha256).
//
//   node src/zone-baseline.mjs baseline --out <dir> [--profile swipe-v1] [--target original]
//        [--classes packages/measure-chromium/classes.frozen.json] [--check]
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { call, zoneSums } from './fwcore.mjs';

const args = process.argv.slice(2);
const arg = (f, d) => { const i = args.indexOf(f); return i < 0 ? d : args[i + 1]; };
if (args[0] === 'baseline') { baselineMode(); process.exit(0); }
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

/** Mode 2: the cross-shard baseline from the committed zones file (see the header). Function declaration: hoisted. */
function baselineMode() {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
  const outDir = arg('--out');
  const profile = arg('--profile', 'swipe-v1');
  const tgt = arg('--target', 'original');
  const classesPath = resolve(arg('--classes', join(root, 'packages/measure-chromium/classes.frozen.json')));
  if (!outDir) { console.error('usage: zone-baseline.mjs baseline --out <dir> [--profile p] [--target t] [--classes f] [--check]'); process.exit(2); }
  const zonesPath = join(outDir, profile, `${tgt}.zones.json`);
  const zonesText = readFileSync(zonesPath);
  const zf = JSON.parse(zonesText);
  const classesText = readFileSync(classesPath);
  const frozen = JSON.parse(classesText).profiles?.[profile];
  if (!frozen) { console.error(`${classesPath} has no profile ${profile}`); process.exit(2); }
  const sha = (b) => createHash('sha256').update(b).digest('hex');
  const shardIds = Object.keys(zf.shards).sort();
  const [b] = call([{ op: 'measure.zoneBaseline', classes: frozen.types,
    runs: shardIds.map((id) => ({ id, zones: zf.shards[id].zones })) }]);
  const file = {
    schema: 'fw.zonebaseline.chromium.baseline/1',
    note: 'Cross-shard baseline per zone and count type, and whole-run totals: fwcore measure.zoneBaseline (Lean Fw.Measure.ZoneBaseline). ' +
      'class = the type in the frozen table (unlisted = not in it; rule quarantined); perRun in the order of runs; lo, hi; ' +
      'base = the observed value at sorted index floor((n-1)/2). Raw counts are work, not milliseconds. Regenerate after every refreeze.',
    source: { zonesFile: relative(root, resolve(zonesPath)), zonesSha256: sha(zonesText), storeKey: zf.storeKey, runId: zf.runId,
      gitSha: zf.gitSha, image: zf.image, zoneHeightPx: zf.zoneHeightPx },
    classTable: { file: relative(root, classesPath), sha256: sha(classesText), profile, image: frozen.image,
      workflowRuns: frozen.workflowRuns },
    target: tgt, engine: zf.engine, profile: zf.profile,
    ...b,
  };
  const text = JSON.stringify(file, null, 1) + '\n';
  const path = join(outDir, profile, `${tgt}.baseline.json`);
  if (args.includes('--check')) {
    if (!existsSync(path) || readFileSync(path, 'utf8') !== text) { console.error(`DIFFERS: ${path}`); process.exit(1); }
    console.log(`identical: ${path}`);
  } else {
    writeFileSync(path, text);
    console.log(`wrote ${path} (${b.runs.length} runs, ${b.zones.length} zones, ${Object.keys(b.totals).length} types, ` +
      `detDrift ${b.detDrift.length}, detDriftTotals ${b.detDriftTotals.length}, tally ${JSON.stringify(b.tally)})`);
  }
}
