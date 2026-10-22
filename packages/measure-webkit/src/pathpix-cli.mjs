#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { runWebkitLane } from './pathpix-webkit.mjs';
import { analyzeLane, table } from './pathpix-analyze.mjs';

const { values: v } = parseArgs({
  args: process.argv.slice(2).filter((a) => a !== '--'),
  options: {
    site: { type: 'string' }, out: { type: 'string' }, layers: { type: 'string' }, 'p-layers': { type: 'string' }, 'deadline-min': { type: 'string' }, offsets: { type: 'string' }, run: { type: 'string' },
    strips: { type: 'string', default: 'changed' }, settle: { type: 'string', default: '0' }, hold: { type: 'string', default: '800' },
    'analyze-only': { type: 'boolean', default: false },
  },
});
if (!v.out) {
  console.error('usage: pathpix-cli.mjs --site <dist/aot> --out <dir> [--layers a,b] [--offsets 0,4,8] [--run ID] [--strips all|changed|none] | --analyze-only --out <dir>');
  process.exit(2);
}
const out = resolve(v.out);
mkdirSync(out, { recursive: true });
if (!v['analyze-only']) {
  if (!v.site) { console.error('--site is required'); process.exit(2); }
  await runWebkitLane({
    siteDir: resolve(v.site), out, run: v.run ?? process.env.GITHUB_RUN_ID ?? 'local',
    layers: v.layers ? v.layers.split(',') : null, pLayers: v['p-layers'] ? v['p-layers'].split(',') : null,
    deadlineMs: v['deadline-min'] ? Number(v['deadline-min']) * 60000 : Infinity, offsetIdx: v.offsets ? v.offsets.split(',').map(Number) : null,
    settleMs: Number(v.settle), holdMs: Number(v.hold),
  });
}
mkdirSync(join(out, 'strips'), { recursive: true });
const res = analyzeLane(out, { strips: v.strips, emit: (name, png) => writeFileSync(join(out, name), png) });
writeFileSync(join(out, 'cells.json'), JSON.stringify(res) + '\n');
const md = table(res);
writeFileSync(join(out, 'summary.md'), md + '\n');
console.log(md);
