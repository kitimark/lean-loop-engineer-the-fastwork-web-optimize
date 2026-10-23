#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { runMacMorph } from './macmorph.mjs';
import { analyze, macMd } from './macreport.mjs';
import { snapshotRoot } from '../session.mjs';

const [cmd, ...rest] = process.argv.slice(2).filter((a) => a !== '--');
const { values: v } = parseArgs({
  args: rest,
  options: { site: { type: 'string' }, search: { type: 'string', default: '' }, reps: { type: 'string', default: '4' }, out: { type: 'string' }, files: { type: 'string' }, json: { type: 'string' }, 'job-index': { type: 'string' }, jobs: { type: 'string' } },
});
const log = (s) => console.error(s);

async function main() {
  if (cmd === 'run') {
    if (!v.site) throw new Error('usage: run --site <apps/site/dist/aot> [--search ?fw=...] [--reps 4] [--out file]');
    const { webkit } = createRequire(join(process.cwd(), 'package.json'))('playwright-core');
    const idx = Number(v['job-index'] ?? process.env.FW_MATRIX_JOB ?? '');
    const res = await runMacMorph({ webkit, snapshotDir: snapshotRoot(), siteDir: v.site, search: v.search, reps: Number(v.reps), log });
    if (Number.isInteger(idx) && idx > 0) res.jobIndex = idx;
    const file = resolve(v.out ?? 'out/mac-morph.json');
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, `${JSON.stringify(res)}\n`);
    const ok = res.runs.filter((r) => r.outcome === 'ok').length;
    log(`wrote ${file}: ${ok} of ${res.runs.length} runs accepted by the phase rule`);
    if (!ok) throw new Error('no run was accepted by the phase rule');
  } else if (cmd === 'report') {
    if (!v.files) throw new Error('usage: report --files a.json,b.json,c.json [--jobs 1,2,3] [--json file]');
    const files = v.files.split(',').map((f) => JSON.parse(readFileSync(resolve(f), 'utf8')));
    const named = v.jobs?.split(',').map(Number);
    if (named && named.length !== files.length) throw new Error('--jobs needs one matrix job index per file');
    const a = analyze(named ? files.map((f, i) => ({ ...f, jobIndex: named[i] })) : files);
    console.log(macMd(a));
    if (v.json) writeFileSync(resolve(v.json), `${JSON.stringify(a, null, 1)}\n`);
  } else throw new Error('usage: mac-cli.mjs run|report');
}

main().catch((e) => { console.error(e.stack || String(e)); process.exit(e.exitCode ?? 1); });
