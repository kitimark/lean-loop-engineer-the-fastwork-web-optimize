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

const ints = (x) => (typeof x === 'number' ? Number.isInteger(x) : Array.isArray(x) ? x.every(ints) : x !== null && typeof x === 'object' ? Object.values(x).every(ints) : true);

export function trimRaw(raw) {
  const keep = (rows, f) => (rows ?? []).map(f);
  const runs = raw.runs.map((u) => ({
    width: u.width, role: u.role ?? (u.site === 'orig' ? 'orig' : 'cand'),
    ...(u.morph ? { morph: { phases: Object.fromEntries(['open', 'close'].map((ph) => [ph, keep(u.morph.phases?.[ph], (r) => ({ m: r.m, rep: r.rep ?? 0, nodes: { nav: r.nodes?.nav, panel: r.nodes?.panel } }))])) } } : {}),
    ...(u.pain ? { pain: Object.fromEntries(['up', 'down'].map((d) => [d, keep(u.pain[d], (r) => ({ layer: r.layer, cls: r.cls }))])) } : {}),
    ...(u.carousel ? { carousel: keep(u.carousel, (r) => ({ v: r.v })) } : {}),
  }));
  const out = { engine: raw.engine, version: raw.version, search: raw.search, hash: raw.hash, baseHash: raw.baseHash, reps: raw.reps, layout: raw.layout, runs };
  if (!ints(runs)) throw new Error('trimRaw: a non-integer number in the rows');
  return out;
}

const gradeTok = (g) => g ?? 'null';

export function rawLines(label, raw) {
  return cellsOfRaw(raw).map((u) => {
    const extra = u.cell === 'panel-effect' ? ` lag=${u.lag.map(gradeTok).join(',')}`
      : u.cell === 'carousel' ? ` swaps=${u.swaps.join(',')} holds=${u.holds.map((h) => h.join(',')).join('/')}` : '';
    return `${label} ${u.width} ${u.cell} ${u.part} ${gradeTok(u.grade)} ${u.reps.map(gradeTok).join(',')}${extra}`;
  });
}

const fixtureFiles = (input) => (statSync(input).isDirectory() ? readdirSync(input).filter((f) => /^raw-.+\.json$/.test(f)).sort().map((f) => join(input, f)) : [input]);
const labelOf = (f) => f.replace(/^.*\//, '').replace(/^raw-/, '').replace(/\.json$/, '');

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
  if (cmd === 'trim') {
    const input = arg(argv, '--in');
    if (input === '' || out === '') { console.error('cells-gpu: trim needs --in <raw json> --out <file>'); return 1; }
    writeFileSync(out, JSON.stringify(trimRaw(JSON.parse(readFileSync(input, 'utf8')))) + '\n');
    return 0;
  }
  if (cmd === 'raw') {
    const inputs = argv.slice(1);
    if (inputs.length === 0) { console.error('cells-gpu: raw needs <fixture json or dir>...'); return 1; }
    for (const f of inputs.flatMap(fixtureFiles)) for (const l of rawLines(labelOf(f), JSON.parse(readFileSync(f, 'utf8')))) console.log(l);
    return 0;
  }
  if (cmd === 'run') {
    const widths = arg(argv, '--widths', '390,640').split(',').map(Number);
    if (widths.some((w) => ![390, 640, 641, 1280].includes(w))) { console.error('cells-gpu: widths must come from 390, 640, 641, 1280'); return 1; }
    const reps = Number(arg(argv, '--reps', '3'));
    if (!Number.isInteger(reps) || reps < 1 || reps > 5) { console.error('cells-gpu: reps must be 1 to 5'); return 1; }
    const dir = out === '' ? 'out/cells-gpu' : out;
    const { runCells } = await import('./cells-gpu-run.mjs');
    const raw = await runCells({ engineName: arg(argv, '--engine', 'chromium'), widths, search: arg(argv, '--search'), reps, only: arg(argv, '--only'), env: process.env });
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, `raw-${raw.engine}.json`), JSON.stringify(raw));
    report(raw, dir);
    return 0;
  }
  console.error('usage: cells-gpu-cli.mjs summary --in <raw json or dir> [--out <dir>] | trim --in <raw json> --out <file> | raw <fixture json or dir>... | run --engine <e> --out <dir> [--widths ...] [--search ...] [--reps n]');
  return 1;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) process.exit(await main(process.argv.slice(2)));
