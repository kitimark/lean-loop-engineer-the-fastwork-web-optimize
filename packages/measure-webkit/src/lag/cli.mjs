#!/usr/bin/env node
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
import { parseCost, swapSetup, accentSetup } from './costmode.mjs';
import { armsOutcome, sumsLine } from './morphcost.mjs';
import { windowCells, swapMd, swapPassesOf, armLabel, pooledSummary } from './swapreport.mjs';
import { parseFreeze } from './freeze.mjs';
import { freezeSession } from './freezesession.mjs';
import { freezeAnalysis, freezeMd } from './freezereport.mjs';
import { accentSession } from './accentsession.mjs';
import { accentAnalysis, accentMd } from './accentreport.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: {
    site: { type: 'string' }, search: { type: 'string', default: '' }, out: { type: 'string' }, keep: { type: 'boolean', default: true },
    passes: { type: 'string', default: '2' }, step: { type: 'string', default: '50' }, frames: { type: 'string', default: '2' },
    settle: { type: 'string', default: '6000' }, clock: { type: 'string', default: 'pinned' }, vendors: { type: 'string', default: 'off' },
    cost: { type: 'string', default: 'off' }, swap: { type: 'boolean', default: false }, accent: { type: 'boolean', default: false }, freeze: { type: 'string' }, original: { type: 'string' }, rewrite: { type: 'string' }, preset: { type: 'string' }, faithful: { type: 'string' }, json: { type: 'string' }, sums: { type: 'string' }, summary: { type: 'string' }, arm: { type: 'string' }, run: { type: 'string' }, note: { type: 'string' }, files: { type: 'string' }, sources: { type: 'string' },
  },
  allowNegative: true,
});
const log = (s) => console.error(s);
const read = (list) => list.split(',').map((f) => JSON.parse(readFileSync(resolve(f), 'utf8')));

async function main() {
  switch (cmd) {
    case 'run': {
      const costMode = parseCost(v.cost);
      const accentLane = v.accent ? accentSetup({ accent: true, cost: costMode.cost, site: v.site }) : { accent: null, arms: null };
      if (v.accent && !accentLane.accent) throw new Error('--accent needs --cost on|only and --site');
      const sw = v.accent ? { swap: null, arms: accentLane.arms } : swapSetup({ swap: v.swap, cost: costMode.cost, site: v.site, search: v.search });
      const { swap, arms: swapArms } = sw;
      const freeze = parseFreeze(v.freeze);
      if (freeze && !swap) throw new Error('--freeze needs --swap --cost on|only with --site and --search');
      const file = resolve(v.out ?? 'out/lag.json');
      const save = (doc) => { mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, JSON.stringify({ ...doc, search: v.search }) + '\n'); };
      const opts = { passes: Number(v.passes), clock: v.clock, settleMs: Number(v.settle), step: Number(v.step), framesPerStep: Number(v.frames), log, ...costMode, swap, ...(freeze || accentLane.accent ? { save } : {}), ...(freeze?.mode ? { freezeMode: freeze.mode } : {}) };
      const body = (ctx) => (accentLane.accent ? accentSession(ctx, { ...opts, accent: accentLane.accent }) : freeze ? freezeSession(ctx, opts) : lagSession(ctx, opts));
      const res = await withSession(body, { keep: v.keep, vendors: v.vendors, site: v.site ? { dir: v.site, search: v.search } : null, arms: swapArms });
      save(res);
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
    case 'morph-verdict': {
      if (!v.original || !v.rewrite) throw new Error('usage: morph-verdict --original a.json,b.json --rewrite c.json,d.json [--json file] [--sums file --run baseId,flagId]');
      if (v.sums && !v.run) throw new Error('--sums needs --run baseId,flagId');
      const res = armsOutcome(read(v.original).flatMap((d) => d.passes), read(v.rewrite).flatMap((d) => d.passes));
      for (const r of res.rows) console.log(r.join('\t'));
      console.log(`outcome\t${res.outcome}`);
      if (v.json) writeFileSync(resolve(v.json), `${JSON.stringify(res, null, 1)}\n`);
      if (v.sums) writeFileSync(resolve(v.sums), `${sumsLine(v.run, res)}\n`);
      break;
    }
    case 'swap-report': {
      if (!v.files) throw new Error('usage: swap-report --files a.json,b.json [--sources "run id ..."] [--json file] [--out file]');
      const docs = read(v.files);
      const passes = swapPassesOf(docs);
      if (!passes.length) throw new Error('no swap pass in the files (a run with --swap --cost on|only at a query, target rewrite)');
      const cells = windowCells(passes);
      const label = armLabel(docs, v.arm);
      const md = swapMd(cells, (v.sources ?? v.files).split(';'), { label, model: label.startsWith('people.carousel') || label === 'crop', passes });
      if (v.out) writeFileSync(resolve(v.out), `${md}\n`); else console.log(md);
      if (v.json) writeFileSync(resolve(v.json), `${JSON.stringify({ schema: 'fw.webkit.lag.swap.report/1', label, passes: passes.length, cells }, null, 1)}\n`);
      if (v.summary) writeFileSync(resolve(v.summary), `${JSON.stringify({ schema: 'fw.webkit.lag.swap.summary/1', label, sources: (v.sources ?? v.files).split(';'), passes: passes.length, pooled: pooledSummary(passes) }, null, 1)}\n`);
      break;
    }
    case 'freeze-report': {
      if (!v.files) throw new Error('usage: freeze-report --files a.json,b.json [--sources "run id ..."] [--json file] [--out file]');
      const an = freezeAnalysis(read(v.files));
      if (!an.passes.free || !an.passes.frozen) throw new Error('no freeze pass in the files (a run with --swap --freeze hero-accent)');
      const md = freezeMd(an, (v.sources ?? v.files).split(';'));
      if (v.out) writeFileSync(resolve(v.out), `${md}\n`); else console.log(md);
      if (v.json) writeFileSync(resolve(v.json), `${JSON.stringify(an, null, 1)}\n`);
      break;
    }
    case 'accent-report': {
      if (!v.files) throw new Error('usage: accent-report --files a.json,b.json [--sources "run id ..."] [--json file] [--out file]');
      const an = accentAnalysis(read(v.files));
      if (!an.records) throw new Error('no accent record in the files (a run with --accent --cost only)');
      const md = accentMd(an, (v.sources ?? v.files).split(';'));
      if (v.out) writeFileSync(resolve(v.out), `${md}\n`); else console.log(md);
      if (v.json) writeFileSync(resolve(v.json), `${JSON.stringify(an, null, 1)}\n`);
      break;
    }
    default:
      console.error('usage: run|report|cost-report|morph-verdict|swap-report|freeze-report|accent-report');
      process.exitCode = 2;
  }
}
const guard = watch();
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = e.exitCode ?? 1; }).finally(() => guard.done(process.exitCode ?? 0));
