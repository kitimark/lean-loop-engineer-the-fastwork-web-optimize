// Merges the per-shard run files of ONE engine into the single file `cli.mjs summary` reads (<engine>.json).
// Glue only: no verdict logic. It checks that the parts fit together, then writes the same layout as run.mjs does.
//   node .github/scripts/merge-gate.mjs --out <file> [--sweeps <file>] [--gen <path>] <shard.json> ...
// Checks (exit 1 on any failure):
//   - every file has the same header (browser, gen hash, snapshot, site build, property lists);
//   - the shard probes are exactly the ids of the gen file, each once, and are written in gen order;
//   - the sweeps file (if given) holds no probes and exactly the sweeps of spec.mjs; shard files hold no sweeps.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const argv = process.argv.slice(2);
const files = [];
const opt = {};
for (let i = 0; i < argv.length; i++) {
  if (argv[i].startsWith('--')) { opt[argv[i].slice(2)] = argv[++i]; } else files.push(argv[i]);
}
if (!opt.out || files.length === 0) { console.error('usage: merge-gate.mjs --out FILE [--sweeps FILE] [--gen PATH] shard.json ...'); process.exit(2); }

const spec = await import(pathToFileURL(resolve('packages/gate-breakpoints/src/spec.mjs')).href);
const { gen } = spec.loadGen(opt.gen ? resolve(opt.gen) : undefined);
const wantIds = gen.matrix.probes.map((p) => p.id);
const wantSweeps = spec.sweepDefs(gen).map((s) => s.id);
const fail = (m) => { console.error(`merge-gate: ${m}`); process.exit(1); };

const load = (f) => JSON.parse(readFileSync(f, 'utf8'));
const shardRuns = files.map((f) => ({ f, run: load(f) }));
const sweepRun = opt.sweeps ? { f: opt.sweeps, run: load(opt.sweeps) } : null;
const all = sweepRun ? [...shardRuns, sweepRun] : shardRuns;

const head = JSON.stringify(all[0].run.header);
for (const { f, run } of all) {
  if (run.header.schema !== 'fw.gate-breakpoints.run/1') fail(`${f}: unknown schema ${run.header.schema}`);
  if (JSON.stringify(run.header) !== head) fail(`${f}: header differs from ${all[0].f}`);
}
const byId = new Map();
for (const { f, run } of shardRuns) {
  if (run.sweeps.length !== 0) fail(`${f}: a shard file holds sweeps`);
  for (const rec of run.probes) {
    if (byId.has(rec.id)) fail(`probe ${rec.id} appears twice (again in ${f})`);
    byId.set(rec.id, rec);
  }
}
const missing = wantIds.filter((id) => !byId.has(id));
const extra = [...byId.keys()].filter((id) => !wantIds.includes(id));
if (missing.length || extra.length) fail(`probe set differs from the gen file: missing ${missing.length} (${missing.slice(0, 5)}), extra ${extra.length} (${extra.slice(0, 5)})`);
let sweeps = [];
if (sweepRun) {
  if (sweepRun.run.probes.length !== 0) fail(`${sweepRun.f}: the sweeps file holds probes`);
  sweeps = sweepRun.run.sweeps;
  const got = sweeps.map((s) => s.id);
  if (JSON.stringify(got) !== JSON.stringify(wantSweeps)) fail(`sweeps ${got} differ from spec ${wantSweeps}`);
}

const lines = [
  '{"header":' + JSON.stringify(all[0].run.header) + ',',
  '"probes":[',
  wantIds.map((id) => JSON.stringify(byId.get(id))).join(',\n'),
  '],',
  '"sweeps":[',
  sweeps.map((r) => JSON.stringify(r)).join(',\n'),
  ']}',
];
mkdirSync(dirname(resolve(opt.out)), { recursive: true });
writeFileSync(opt.out, lines.join('\n') + '\n');
console.log(`merged ${shardRuns.length} shard files, ${wantIds.length} probes, ${sweeps.length} sweeps -> ${opt.out}`);
