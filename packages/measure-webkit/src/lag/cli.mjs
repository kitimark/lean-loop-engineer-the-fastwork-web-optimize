#!/usr/bin/env node
// node src/lag/cli.mjs run [--site dir --search q] [--out file] [--passes 2]   one Simulator session of the lag probe
// node src/lag/cli.mjs cost-report --original a.json,b.json --rewrite c.json,d.json [--preset e.json] [--json file]   the per-zone cost-counter tables
// node src/lag/cli.mjs report --original a.json,b.json --faithful c.json,d.json [--json file] [--note file]   the ranked attribution
//   --note file replaces the block between the lag-report markers of a Markdown file with the report
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { withSession } from '../session.mjs';
import { watch } from '../watchdog.mjs';
import { TARGET_LOST_EXIT } from '../inspector.mjs';
import { lagSession } from './probe.mjs';
import { analyzeArm, reportMd } from './report.mjs';
import { fillBlock } from './note.mjs';
import { collectArm, costMd } from './costreport.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: {
    site: { type: 'string' }, search: { type: 'string', default: '' }, out: { type: 'string' }, keep: { type: 'boolean', default: true },
    passes: { type: 'string', default: '2' }, step: { type: 'string', default: '50' }, frames: { type: 'string', default: '2' },
    settle: { type: 'string', default: '6000' }, clock: { type: 'string', default: 'pinned' }, vendors: { type: 'string', default: 'off' },
    cost: { type: 'string', default: 'on' }, original: { type: 'string' }, rewrite: { type: 'string' }, preset: { type: 'string' }, faithful: { type: 'string' }, json: { type: 'string' }, note: { type: 'string' },
  },
  allowNegative: true,
});
const log = (s) => console.error(s);
const read = (list) => list.split(',').map((f) => JSON.parse(readFileSync(resolve(f), 'utf8')));

async function main() {
  switch (cmd) {
    case 'run': {
      const res = await withSession((ctx) => lagSession(ctx, {
        passes: Number(v.passes), clock: v.clock, settleMs: Number(v.settle), step: Number(v.step), framesPerStep: Number(v.frames), log, cost: v.cost !== 'off', costOnly: v.cost === 'only',
      }), { keep: v.keep, vendors: v.vendors, site: v.site ? { dir: v.site, search: v.search } : null });
      const file = resolve(v.out ?? 'out/lag.json');
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, JSON.stringify(res) + '\n');
      log(`wrote ${file}${res.failed.length ? ` (stopped early: ${res.failed.join('; ')})` : ''}`);
      if (res.targetLost) throw Object.assign(new Error(`the page target was lost for good (the passes kept are in ${file})`), { exitCode: TARGET_LOST_EXIT });
      if (!res.passes.length) throw new Error('no pass completed');
      break;
    }
    case 'report': {
      const arms = [['original', v.original], ['faithful', v.faithful]].filter(([, l]) => l);
      if (!arms.length) throw new Error('usage: report --original a.json,b.json --faithful c.json,d.json [--json file]');
      const analysed = arms.map(([n, l]) => [n, analyzeArm(read(l))]);
      const md = reportMd(analysed);
      if (v.note) writeFileSync(resolve(v.note), fillBlock(readFileSync(resolve(v.note), 'utf8'), md));
      else console.log(md);
      if (v.json) writeFileSync(resolve(v.json), `${JSON.stringify(Object.fromEntries(analysed), null, 1)}\n`);
      break;
    }
    case 'cost-report': {
      const arms = [['original', v.original], ['rewrite', v.rewrite], ['preset', v.preset]].filter(([, l]) => l).map(([n, l]) => [n, collectArm(read(l))]);
      if (arms.length < 2) throw new Error('usage: cost-report --original a.json,b.json --rewrite c.json,d.json [--preset e.json] [--json file]');
      console.log(costMd(arms));
      if (v.json) writeFileSync(resolve(v.json), `${JSON.stringify(Object.fromEntries(arms), null, 1)}\n`);
      break;
    }
    default:
      console.error('usage: run|report|cost-report');
      process.exitCode = 2;
  }
}
const guard = watch();
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = e.exitCode ?? 1; }).finally(() => guard.done(process.exitCode ?? 0));
