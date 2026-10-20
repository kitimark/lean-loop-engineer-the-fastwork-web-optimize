// The key of one gate cache: <prefix>-<sha256 of the canonical declared-input string>.
// Glue only: the declared inputs of each cache and the canonical string come from the Lean golden
// (packages/contracts/golden/ops/cache.jsonl, lean/Fw/Ops/Cache.lean `key`); this script refuses a set of inputs that is not exactly
// the declared one, so a key can neither miss a declared input (a stale hit, `key_complete`) nor carry an undeclared one.
//   node .github/scripts/cache-key.mjs --cache browsers --set playwright=1.64.1 [--golden <file>] [--canonical]
// Prints the key (or with --canonical the string that is hashed). Exit 2 on bad usage, 1 on a mismatch with the declaration.
// The premise of Lean's `cache_sound` that this cannot prove: SHA-256 has no collision among the vectors used, and the
// cached step reads nothing but the declared inputs.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const argv = process.argv.slice(2);
const die = (m, code = 1) => { console.error(`cache-key: ${m}`); process.exit(code); };
const arg = (n, d) => { const i = argv.indexOf(`--${n}`); return i < 0 ? d : argv[i + 1]; };
const cache = arg('cache');
if (!cache) die('usage: cache-key.mjs --cache <name> --set name=value ... [--canonical]', 2);
const goldenPath = resolve(arg('golden', 'packages/contracts/golden/ops/cache.jsonl'));

const sets = [];
for (let i = 0; i < argv.length; i++) if (argv[i] === '--set') sets.push(argv[i + 1] ?? '');
const env = new Map();
for (const s of sets) {
  const eq = s.indexOf('=');
  if (eq <= 0) die(`--set wants name=value, got "${s}"`, 2);
  const n = s.slice(0, eq);
  const v = s.slice(eq + 1);
  if (/[=\n]/.test(n) || /\n/.test(v)) die(`name or value of ${n} holds "=" (name) or a newline`, 2);
  if (env.has(n)) die(`${n} is set twice`, 2);
  env.set(n, v);
}

const lines = readFileSync(goldenPath, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const def = lines.find((l) => l.cache === cache && l.role === 'base');
if (!def) die(`no cache named ${cache} in ${goldenPath}`, 2);
const missing = def.decl.filter((n) => !env.has(n));
const extra = [...env.keys()].filter((n) => !def.decl.includes(n));
if (missing.length || extra.length) die(`${cache} declares [${def.decl}]: missing [${missing}], undeclared [${extra}]`);

const canonical = def.decl.map((n) => `${n}=${env.get(n)}`).join('\n');
if (argv.includes('--canonical')) { process.stdout.write(canonical + '\n'); process.exit(0); }
const digest = createHash('sha256').update(canonical).digest('hex').slice(0, 40);
process.stdout.write(`${def.prefix}-${digest}\n`);
