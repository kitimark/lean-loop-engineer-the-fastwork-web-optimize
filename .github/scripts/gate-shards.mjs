// Splits the breakpoint matrix (Lean-generated apps/site/src/breakpoints.gen.json, 124 loads per engine) into N shards
// for the CI matrix. Glue only: the probes and their ids come from the gen file; nothing is decided here.
//   node .github/scripts/gate-shards.mjs [--shards 8] [--gen <path>]
// Prints one JSON object: {"shard":["s0",...],"probes":{"s0":"id,id,...",...}}. Each value is passed to
// `cli.mjs run --probes <value>`, whose filter is `p.id.includes(o) || p.block === o`; this script checks that the filter
// picks exactly the assigned ids (so a shard never runs a probe twice or drops one), and that the union is the whole matrix.
// Round-robin by matrix order, so the cheap and the expensive blocks spread evenly.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const argv = process.argv.slice(2);
const arg = (n, d) => { const i = argv.indexOf(`--${n}`); return i < 0 ? d : argv[i + 1]; };
const n = Number(arg('shards', '8'));
const genPath = resolve(arg('gen', 'apps/site/src/breakpoints.gen.json'));
if (!Number.isInteger(n) || n < 1 || n > 32) { console.error('--shards must be an integer 1..32'); process.exit(2); }

const gen = JSON.parse(readFileSync(genPath, 'utf8'));
const probes = gen.matrix.probes;
const ids = probes.map((p) => p.id);
if (new Set(ids).size !== ids.length) { console.error('duplicate probe ids in the gen file'); process.exit(1); }
if (probes.length !== gen.matrix.loadsPerEngine) { console.error(`gen says ${gen.matrix.loadsPerEngine} loads, file has ${probes.length}`); process.exit(1); }

const shards = Array.from({ length: n }, () => []);
ids.forEach((id, i) => shards[i % n].push(id));

// Re-implement the CLI filter only to verify it (the real filter is in packages/gate-breakpoints/src/run.mjs).
const picked = (list) => probes.filter((p) => list.some((o) => p.id.includes(o) || p.block === o)).map((p) => p.id);
const seen = new Set();
for (const [i, list] of shards.entries()) {
  if (list.length === 0) continue;
  const got = picked(list);
  if (got.length !== list.length || got.some((id) => !list.includes(id))) { console.error(`shard s${i}: the --probes filter picks ${got.length} ids, expected ${list.length}`); process.exit(1); }
  for (const id of got) { if (seen.has(id)) { console.error(`probe ${id} in two shards`); process.exit(1); } seen.add(id); }
}
if (seen.size !== ids.length) { console.error('the shards do not cover the matrix'); process.exit(1); }
for (const id of ids) if (!/^[A-Za-z0-9._-]+$/.test(id)) { console.error(`unsafe probe id ${id}`); process.exit(1); }

const used = shards.map((l, i) => [`s${i}`, l]).filter(([, l]) => l.length > 0);
const out = { shard: used.map(([k]) => k), probes: Object.fromEntries(used.map(([k, l]) => [k, l.join(',')])) };
process.stdout.write(JSON.stringify(out) + '\n');
console.error(`${probes.length} probes in ${used.length} shards: ${used.map(([k, l]) => `${k}=${l.length}`).join(' ')}`);
