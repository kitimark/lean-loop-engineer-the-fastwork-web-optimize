#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { writePassFile } from './session.mjs';

const args = process.argv.slice(2).filter((a) => a !== '--');
const flag = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const [cmd] = args;

if (cmd === 'run') {
  const site = flag('--site');
  if (!site) { console.error('run needs --site <dir>'); process.exit(2); }
  const out = flag('--out') ?? 'out';
  const file = join(out, `${flag('--name') ?? 'sim-end-floor'}.json`);
  mkdirSync(out, { recursive: true });
  const write = (r) => writeFileSync(file, `${JSON.stringify(r)}\n`);
  const { runEndFloor } = await import('./sim-end-floor-run.mjs');
  const onRound = (n, of, snap) => writePassFile(file, n, of, snap);
  const res = await runEndFloor({ siteDir: resolve(site), rounds: Number(flag('--rounds') ?? 3), rotateBy: Number(flag('--rotate') ?? 0), settleMs: Number(flag('--settle') ?? 2500), onProgress: write, onRound });
  write(res);
  console.log(`sim-end-floor: ${res.rounds.length} rounds, incomplete=${res.incomplete ?? 'no'}, ${res.wallSeconds} s, ${res.meta.runtime}`);
  process.exit(res.rounds.length && !res.incomplete ? 0 : 1);
} else if (cmd === 'searches') {
  const { BUILD_SEARCHES } = await import('./sim-end-floor.mjs');
  console.log(BUILD_SEARCHES.join('\n'));
} else if (cmd === 'report') {
  const file = args[1];
  if (!file) { console.error('report needs a sim-end-floor.json file'); process.exit(2); }
  const { rowLines, verdictLines } = await import('./sim-end-floor.mjs');
  const raw = JSON.parse(readFileSync(file, 'utf8'));
  const rows = rowLines(raw), verdict = verdictLines(raw);
  const dir = flag('--out');
  if (dir) {
    mkdirSync(resolve(dir), { recursive: true });
    writeFileSync(join(resolve(dir), 'rows.txt'), `${rows.join('\n')}\n`);
    writeFileSync(join(resolve(dir), 'verdict.txt'), `${verdict.join('\n')}\n`);
  }
  console.log([...verdict, '', ...rows].join('\n'));
} else if (cmd === 'attrib') {
  const files = args.slice(1).filter((a, i, all) => !a.startsWith('--') && all[i - 1] !== '--out');
  if (!files.length) { console.error('attrib needs one or more sim-end-floor.json files (one per CI job)'); process.exit(2); }
  const { rowLines } = await import('./sim-end-floor.mjs');
  const { mergeRaws, tableLines, verdictLines } = await import('./sim-floor-attrib.mjs');
  const merged = mergeRaws(files.map((f) => JSON.parse(readFileSync(f, 'utf8'))));
  const rows = rowLines(merged), table = tableLines(merged), verdict = verdictLines(merged);
  const dir = flag('--out');
  if (dir) {
    mkdirSync(resolve(dir), { recursive: true });
    writeFileSync(join(resolve(dir), 'rows.txt'), `${rows.join('\n')}\n`);
    writeFileSync(join(resolve(dir), 'table.txt'), `${table.join('\n')}\n`);
    writeFileSync(join(resolve(dir), 'attrib.txt'), `${verdict.join('\n')}\n`);
  }
  console.log([...verdict, '', ...table].join('\n'));
} else {
  console.error('usage: sim-end-floor-cli.mjs run|searches|report|attrib');
  process.exit(2);
}
