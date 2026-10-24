#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { runWebkitLane } from './pathpix-webkit.mjs';
import { runWebkitExitLane } from './pathpix-exit-webkit.mjs';
import { analyzeDir } from './pathpix-exit.mjs';
import { runWebkitDrawLane } from './pathpix-exit-draw-webkit.mjs';
import { analyzeDraw, drawTable } from './pathpix-exit-draw.mjs';

const { values: v } = parseArgs({
  args: process.argv.slice(2).filter((a) => a !== '--'),
  options: {
    site: { type: 'string' }, out: { type: 'string' }, layers: { type: 'string' }, 'p-layers': { type: 'string' }, 'deadline-min': { type: 'string' }, offsets: { type: 'string' }, run: { type: 'string' },
    strips: { type: 'string', default: 'changed' }, settle: { type: 'string', default: '0' }, hold: { type: 'string', default: '800' },
    'analyze-only': { type: 'boolean', default: false }, mode: { type: 'string', default: 'layers' }, flag: { type: 'string' },
  },
});
if (!v.out) {
  console.error('usage: pathpix-cli.mjs --site <dist/aot> --out <dir> [--layers a,b] [--offsets 0,4,8] [--run ID] [--strips all|changed|none] [--mode exit --flag <id:variant>] | --analyze-only --out <dir>');
  process.exit(2);
}
const out = resolve(v.out);
mkdirSync(out, { recursive: true });
if (!v['analyze-only']) {
  if (!v.site) { console.error('--site is required'); process.exit(2); }
  if (v.mode === 'draw') {
    await runWebkitDrawLane({ siteDir: resolve(v.site), out, run: v.run ?? process.env.GITHUB_RUN_ID ?? 'local' });
  } else if (v.mode === 'exit') {
    if (!v.flag) { console.error('--mode exit needs --flag'); process.exit(2); }
    await runWebkitExitLane({ siteDir: resolve(v.site), out, run: v.run ?? process.env.GITHUB_RUN_ID ?? 'local', flag: v.flag, offsetIdx: v.offsets ? v.offsets.split(',').map(Number) : null, settleMs: Number(v.settle), holdMs: Number(v.hold) });
  } else await runWebkitLane({
    siteDir: resolve(v.site), out, run: v.run ?? process.env.GITHUB_RUN_ID ?? 'local',
    layers: v.layers ? v.layers.split(',') : null, pLayers: v['p-layers'] ? v['p-layers'].split(',') : null,
    deadlineMs: v['deadline-min'] ? Number(v['deadline-min']) * 60000 : Infinity, offsetIdx: v.offsets ? v.offsets.split(',').map(Number) : null,
    settleMs: Number(v.settle), holdMs: Number(v.hold),
  });
}
mkdirSync(join(out, 'strips'), { recursive: true });
const emit = (name, png) => writeFileSync(join(out, name), png);
const drawn = JSON.parse(readFileSync(join(out, 'manifest.json'), 'utf8')).mode === 'draw';
const { res, md } = drawn
  ? (() => { const r = analyzeDraw(out, { strips: v.strips, emit }); return { res: r, md: drawTable(r) }; })()
  : analyzeDir(out, { strips: v.strips, emit });
writeFileSync(join(out, 'cells.json'), JSON.stringify(res) + '\n');
writeFileSync(join(out, 'summary.md'), md + '\n');
console.log(md);
