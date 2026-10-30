#!/usr/bin/env node
// node src/sim-end-floor-cli.mjs run --site <dist/aot> [--rounds 3] [--settle 2500] [--out out] [--name sim-end-floor]
// node src/sim-end-floor-cli.mjs searches                                 the --config queries the site build needs, one per line
// node src/sim-end-floor-cli.mjs report <sim-end-floor.json> [--out <dir>]   writes rows.txt and verdict.txt (the numbers of the note)
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
  // one pass file per finished round (tick uploads): a job lost mid-run leaves every round that ended
  const onRound = (n, of, snap) => writePassFile(file, n, of, snap);
  const res = await runEndFloor({ siteDir: resolve(site), rounds: Number(flag('--rounds') ?? 3), settleMs: Number(flag('--settle') ?? 2500), onProgress: write, onRound });
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
} else {
  console.error('usage: sim-end-floor-cli.mjs run|searches|report');
  process.exit(2);
}
