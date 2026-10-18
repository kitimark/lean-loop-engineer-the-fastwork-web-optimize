// Splits the probe list into N shards for the CI matrix (glue: the probe ids are checked against the Lean matrix).
//   node src/shards.mjs [--shards 2] [--probes id,id,...] [--parts a,b]
// Prints {"shard":["s0",...],"probes":{"s0":"id,id",...}}. Part ids are checked against the gate's anchors.json (exit 2 on an unknown id).
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const arg = (n, d) => { const i = argv.indexOf(`--${n}`); return i < 0 ? d : argv[i + 1]; };
const n = Number(arg('shards', '2'));
if (!Number.isInteger(n) || n < 1 || n > 16) { console.error('--shards must be an integer 1..16'); process.exit(2); }
const defaults = JSON.parse(readFileSync(join(HERE, '..', 'probes.default.json'), 'utf8')).probes;
const wanted = (arg('probes', '') || defaults.join(',')).split(',').map((x) => x.trim()).filter(Boolean);
const gen = JSON.parse(readFileSync(resolve(HERE, '../../../apps/site/src/breakpoints.gen.json'), 'utf8'));
const known = new Set(gen.matrix.probes.map((p) => p.id));
const badProbe = wanted.filter((p) => !known.has(p));
if (wanted.length === 0 || badProbe.length > 0) { console.error(`unknown probe ${badProbe.join(', ') || '(empty list)'}`); process.exit(2); }
const partsArg = arg('parts', '');
if (partsArg) {
  const ids = Object.keys(JSON.parse(readFileSync(resolve(HERE, '../../gate-breakpoints/src/anchors.json'), 'utf8')).parts);
  const bad = partsArg.split(',').map((x) => x.trim()).filter((x) => x && !ids.includes(x));
  if (bad.length > 0) { console.error(`unknown part ${bad.join(', ')}; known: ${ids.join(', ')}`); process.exit(2); }
}
const m = Math.min(n, wanted.length);
const shards = Array.from({ length: m }, () => []);
wanted.forEach((id, i) => shards[i % m].push(id));
process.stdout.write(JSON.stringify({ shard: shards.map((_, i) => `s${i}`), probes: Object.fromEntries(shards.map((s, i) => [`s${i}`, s.join(',')])) }) + '\n');
