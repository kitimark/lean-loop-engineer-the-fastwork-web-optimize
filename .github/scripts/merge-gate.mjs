// Merges the per-job run files of ONE engine into the single file `cli.mjs summary` reads (<engine>.json).
// Glue only: no verdict logic. It checks that the parts fit together, then writes the same layout as run.mjs does.
//   node .github/scripts/merge-gate.mjs --out <file> [--sweeps <file>] [--gen <path>] <job.json> ...
// A job file holds any probes and any whole sweeps (the split is Lean's, Fw.Gate.Schedule; the merge law is
// Fw.Gate.mergeGateById_eq_unsharded). `--sweeps` names one more file and is the same as listing it.
// Checks (exit 1 on any failure):
//   - every file has the same header (browser, gen hash, snapshot, site build, property lists);
//   - the probes of all files are exactly the ids of the gen file, each once, and are written in gen order;
//   - the sweeps of all files are exactly the sweeps of spec.mjs, each once and whole (a sweep is one record), and are
//     written in spec order.
//   A run narrowed by --parts names its probe scope in header.parts.scope (the union of the parts' Lean scopes,
//   src/scope.gen.json); it must equal spec.scopeFor for the covered parts, and then replaces the gen ids and spec
//   sweeps above.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const argv = process.argv.slice(2);
const files = [];
const opt = {};
for (let i = 0; i < argv.length; i++) {
  if (argv[i].startsWith('--')) { opt[argv[i].slice(2)] = argv[++i]; } else files.push(argv[i]);
}
if (!opt.out || files.length + (opt.sweeps ? 1 : 0) === 0) { console.error('usage: merge-gate.mjs --out FILE [--sweeps FILE] [--gen PATH] shard.json ...'); process.exit(2); }

const spec = await import(pathToFileURL(resolve('packages/gate-breakpoints/src/spec.mjs')).href);
const { gen } = spec.loadGen(opt.gen ? resolve(opt.gen) : undefined);
let wantIds = gen.matrix.probes.map((p) => p.id);
let wantSweeps = spec.sweepDefs(gen).map((s) => s.id);
const fail = (m) => { console.error(`merge-gate: ${m}`); process.exit(1); };

const load = (f) => JSON.parse(readFileSync(f, 'utf8'));
const all = [...files, ...(opt.sweeps ? [opt.sweeps] : [])].map((f) => ({ f, run: load(f) }));

const head = JSON.stringify(all[0].run.header);
for (const { f, run } of all) {
  if (run.header.schema !== 'fw.gate-breakpoints.run/1') fail(`${f}: unknown schema ${run.header.schema}`);
  if (JSON.stringify(run.header) !== head) fail(`${f}: header differs from ${all[0].f}`);
}
const hp = all[0].run.header.parts;
if (hp) {
  const sel = spec.selectParts(Object.keys(spec.loadAnchors().parts), hp.covered);
  const want = spec.scopeFor(sel, gen);
  if (JSON.stringify(hp.scope ?? null) !== JSON.stringify(want)) fail(`header.parts.scope ${JSON.stringify(hp.scope)} is not the Lean scope ${JSON.stringify(want)}`);
  if (want) { wantIds = want.probes; wantSweeps = want.sweeps; }
}
const byId = new Map();
const sweepById = new Map();
for (const { f, run } of all) {
  for (const rec of run.probes) {
    if (byId.has(rec.id)) fail(`probe ${rec.id} appears twice (again in ${f})`);
    byId.set(rec.id, rec);
  }
  for (const rec of run.sweeps) {
    if (sweepById.has(rec.id)) fail(`sweep ${rec.id} appears twice (again in ${f})`);
    sweepById.set(rec.id, rec);
  }
}
const missing = wantIds.filter((id) => !byId.has(id));
const extra = [...byId.keys()].filter((id) => !wantIds.includes(id));
if (missing.length || extra.length) fail(`probe set differs from the gen file: missing ${missing.length} (${missing.slice(0, 5)}), extra ${extra.length} (${extra.slice(0, 5)})`);
const missingS = wantSweeps.filter((id) => !sweepById.has(id));
const extraS = [...sweepById.keys()].filter((id) => !wantSweeps.includes(id));
if (missingS.length || extraS.length) fail(`sweeps differ from spec ${wantSweeps}: missing [${missingS}], extra [${extraS}]`);
const sweeps = wantSweeps.map((id) => sweepById.get(id));

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
console.log(`merged ${all.length} files, ${wantIds.length} probes, ${sweeps.length} sweeps -> ${opt.out}`);
