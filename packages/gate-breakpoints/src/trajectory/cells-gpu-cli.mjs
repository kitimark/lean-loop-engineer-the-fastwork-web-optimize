import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { cellsOfRaw, tally } from './cells-gpu.mjs';

const arg = (argv, name, dflt = '') => { const i = argv.indexOf(name); return i < 0 ? dflt : (argv[i + 1] ?? dflt); };

function rawFiles(input) {
  if (statSync(input).isDirectory()) return readdirSync(input).filter((f) => /^raw-.+\.json$/.test(f)).map((f) => join(input, f));
  return [input];
}

export function reduceCells(raw) {
  const units = cellsOfRaw(raw);
  const lines = tally(raw.engine, units);
  const md = [`## cells-gpu ${raw.engine} (${raw.version ?? '?'}) search=${raw.search || '(default)'}`, '',
    '| width | cell | part | grade | reps |', '|---|---|---|---|---|',
    ...units.map((u) => `| ${u.width} | ${u.cell} | ${u.part} | ${u.grade ?? 'not comparable'}${u.note ? ` (${u.note})` : ''} | ${JSON.stringify(u.reps)} |`), '',
    ...lines.map((l) => `- ${l}`), ''].join('\n');
  return { units, lines, md };
}

function report(raw, out) {
  const { units, lines, md } = reduceCells(raw);
  if (out !== '') {
    mkdirSync(out, { recursive: true });
    writeFileSync(join(out, `cells-${raw.engine}.json`), JSON.stringify({ engine: raw.engine, search: raw.search, units }));
    writeFileSync(join(out, `cells-${raw.engine}.md`), md);
  }
  for (const l of lines) console.log(l);
  for (const u of units) console.log(`CELL ${raw.engine} ${u.width} ${u.cell} ${u.part}: ${u.grade ?? 'not comparable'}`);
  if (process.env.GITHUB_STEP_SUMMARY) writeFileSync(process.env.GITHUB_STEP_SUMMARY, md, { flag: 'a' });
}

export async function main(argv) {
  const [cmd] = argv;
  const out = arg(argv, '--out');
  if (cmd === 'summary') {
    const input = arg(argv, '--in');
    if (input === '') { console.error('cells-gpu: summary needs --in <raw json or dir>'); return 1; }
    for (const f of rawFiles(input)) report(JSON.parse(readFileSync(f, 'utf8')), out);
    return 0;
  }
  if (cmd === 'run') {
    const widths = arg(argv, '--widths', '390,640').split(',').map(Number);
    if (widths.some((w) => ![390, 640, 641, 1280].includes(w))) { console.error('cells-gpu: widths must come from 390, 640, 641, 1280'); return 1; }
    const reps = Number(arg(argv, '--reps', '3'));
    if (!Number.isInteger(reps) || reps < 1 || reps > 5) { console.error('cells-gpu: reps must be 1 to 5'); return 1; }
    const dir = out === '' ? 'out/cells-gpu' : out;
    const { runCells } = await import('./cells-gpu-run.mjs');
    const raw = await runCells({ engineName: arg(argv, '--engine', 'chromium'), widths, search: arg(argv, '--search'), reps, env: process.env });
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, `raw-${raw.engine}.json`), JSON.stringify(raw));
    report(raw, dir);
    return 0;
  }
  console.error('usage: cells-gpu-cli.mjs summary --in <raw json or dir> [--out <dir>] | run --engine <e> --out <dir> [--widths ...] [--search ...] [--reps n]');
  return 1;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) process.exit(await main(process.argv.slice(2)));
