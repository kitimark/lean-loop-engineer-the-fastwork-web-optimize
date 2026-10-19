// node packages/engine-check/src/cli.mjs --rows <jsonl> --runs <dir>[,<dir>...] --out <dir> [--classes <file>] [--engine chromium]
// Stages every counts.json below the --runs dirs (stage.mjs), then runs `fw engine-check` on the staged dir. Exit code is engine-check's.
// node packages/engine-check/src/cli.mjs --compose <plan.json> --runs <dir> --out <dir> [--classes <file>]
// F6 composition check (compose.mjs, op measure.compose): writes <out>/<name>.json and <out>/table.md per plan comparison.
import { mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { stageRuns } from './stage.mjs';
import { classTable, render, request } from './compose.mjs';

const HERE = fileURLToPath(new URL('.', import.meta.url));

function findCounts(dir) {
  const out = [];
  const walk = (d) => {
    for (const n of readdirSync(d).sort()) {
      const p = join(d, n);
      if (statSync(p).isDirectory()) walk(p);
      else if (n === 'counts.json') out.push(p);
    }
  };
  walk(dir);
  return out;
}

function parseArgs(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i += 2) {
    const k = argv[i];
    if (!['--rows', '--runs', '--out', '--classes', '--engine'].includes(k) || argv[i + 1] === undefined) throw new Error(`usage: cli.mjs --rows f --runs d[,d] --out d [--classes f] (bad ${k})`);
    a[k.slice(2)] = argv[i + 1];
  }
  if (!a.rows || !a.runs || !a.out) throw new Error('usage: cli.mjs --rows f --runs d[,d] --out d [--classes f]');
  return a;
}

async function composeMain(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!['--compose', '--runs', '--out', '--classes'].includes(argv[i]) || argv[i + 1] === undefined) throw new Error(`usage: cli.mjs --compose plan --runs d --out d [--classes f] (bad ${argv[i]})`);
    a[argv[i].slice(2)] = argv[i + 1];
  }
  if (!a.runs || !a.out) throw new Error('usage: cli.mjs --compose plan --runs d --out d [--classes f]');
  const root = resolve(HERE, '..', '..', '..');
  const { fwcoreCall } = await import('../../../apps/runner/src/run.ts');
  const call = fwcoreCall(root);
  const plan = JSON.parse(readFileSync(a.compose, 'utf8'));
  const frozen = JSON.parse(readFileSync(a.classes ?? join(root, 'packages/measure-chromium/classes.frozen.json'), 'utf8'));
  const classes = classTable(frozen, plan.profile, plan.arm);
  mkdirSync(a.out, { recursive: true });
  const md = [];
  for (const cmp of plan.comparisons) {
    const { op: _op, ...reply } = call(request(plan, cmp, classes, a.runs));
    writeFileSync(join(a.out, `${cmp.name}.json`), JSON.stringify(reply, null, 1) + '\n');
    md.push(render(cmp.title ?? cmp.name, reply));
    const t = reply.tally;
    console.log(`${cmp.name}: ${t.composes} composes, ${t.coupled} coupled, ${t.notComparable} not comparable, ${t.reported} reported`);
  }
  writeFileSync(join(a.out, 'table.md'), md.join('\n'));
  return 0;
}

if (process.argv[2] === '--compose') process.exit(await composeMain(process.argv.slice(2)));

const a = parseArgs(process.argv.slice(2));
const engine = a.engine ?? 'chromium';
const rows = readFileSync(a.rows, 'utf8').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l)).filter((r) => r.engine === engine);
const paths = a.runs.split(',').flatMap(findCounts);
const { staged, unkeyed } = stageRuns(paths.map((path) => ({ path, counts: JSON.parse(readFileSync(path, 'utf8')) })), rows);
rmSync(a.out, { recursive: true, force: true });
for (const s of staged) {
  mkdirSync(join(a.out, s.name), { recursive: true });
  writeFileSync(join(a.out, s.name, 'counts.json'), JSON.stringify(s.counts));
}
console.log(`staged ${staged.length} files from ${paths.length} counts.json (${unkeyed.length} answer no row variant)`);
const byVariant = {};
for (const s of staged) byVariant[s.variant] = (byVariant[s.variant] ?? 0) + 1;
console.log(`files per variant: ${JSON.stringify(byVariant)}`);

writeFileSync(join(a.out, 'rows.jsonl'), rows.map((r) => JSON.stringify(r)).join('\n') + '\n');
const root = resolve(HERE, '..', '..', '..');
const args = [join(root, 'apps/runner/src/fw.ts'), 'engine-check', '--rows', join(a.out, 'rows.jsonl'), '--run', a.out, '--json', ...(a.classes ? ['--classes', a.classes] : [])];
const r = spawnSync('node', args, { cwd: root, encoding: 'utf8', maxBuffer: 1 << 28 });
if (r.status !== 0 && r.status !== 3) { console.error(r.stderr || r.stdout); process.exit(r.status ?? 1); }
const reply = JSON.parse(r.stdout);
writeFileSync(join(a.out, 'result.json'), JSON.stringify(reply, null, 1));
for (const v of reply.verdicts) {
  if (v.verdict === 'pass') continue;
  console.log(`${v.verdict.toUpperCase()} ${v.engine}/${v.scenario}/${v.variant} ${v.stage} ${v.countType} ${v.prediction} [${v.class.variant}] runs ${v.runs.variant}/${v.runs.base} sums ${v.totals.variant.join('/')} vs ${v.totals.base.join('/')} ${v.reason}`);
}
console.log(`engine-check: ${reply.tally.pass} pass, ${reply.tally.modelBug} model-bug, ${reply.tally.unusable} unusable (${reply.verdicts.length} rows)`);
process.exit(reply.tally.modelBug > 0 ? 3 : 0);
