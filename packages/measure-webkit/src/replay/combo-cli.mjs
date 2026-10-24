#!/usr/bin/env node
// node packages/measure-webkit/src/replay/combo-cli.mjs run --dist apps/site/dist/aot --profile <ci profile.json> --arms "<search>;<search>;..." [--throttle 6] [--reps 1] [--out dir] [--keep-frames]
//   node ... table --in out/run.json
import { parseArgs } from 'node:util';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { loadPlaywright, playwrightVersion } from '../linux/run.mjs';
import { startServer } from '../../../gate-breakpoints/src/serve.mjs';
import { canonSearch } from '../../../contracts/src/flag-key.mjs';
import { comboPass } from './combo-replay.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: { dist: { type: 'string' }, profile: { type: 'string', multiple: true }, arms: { type: 'string' }, throttle: { type: 'string', default: '6' }, reps: { type: 'string', default: '1' }, out: { type: 'string', default: 'out/combo' }, in: { type: 'string' }, settle: { type: 'string', default: '4000' }, frames: { type: 'boolean', default: false } },
});
const log = (s) => console.error(s);

export function table(run) {
  const rows = ['| profile | arm | rep | frames | reversals no finger | jumps >= 20 px (max px) | script jumps >= 20 px (max px) | script writes (finger down / free) | px written (down / free) |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- |'];
  for (const p of run.passes) {
    const m = p.metrics;
    rows.push(`| ${p.profile} | ${p.armName} | ${p.rep} | ${m.frames} | ${m.reversalsNoFinger} | ${m.jumps.n} (${m.jumps.max}) | ${m.scriptJumps.n} (${m.scriptJumps.max}) | ${m.writes.n} (${m.writes.down} / ${m.writes.free}) | ${Math.round(m.writes.pxDown)} / ${Math.round(m.writes.pxFree)} |`);
  }
  return `${rows.join('\n')}\n`;
}

async function main() {
  if (cmd === 'table') { process.stdout.write(table(JSON.parse(readFileSync(resolve(v.in), 'utf8')))); return; }
  if (cmd !== 'run' || !v.dist || !v.profile?.length || !v.arms) { console.error('usage: run --dist <site dist> --profile <p.json>... --arms "<name>=<search>;..." | table --in run.json'); process.exitCode = 2; return; }
  const root = resolve(v.dist);
  const cfg = JSON.parse(readFileSync(join(root, 'configs.json'), 'utf8'));
  const arms = v.arms.split(';').map((s) => s.trim()).filter(Boolean).map((s) => {
    const i = s.indexOf('=');
    const name = i < 0 ? s : s.slice(0, i);
    const search = i < 0 ? s : s.slice(i + 1);
    const hash = cfg.bySearch[canonSearch(search)];
    if (hash === undefined) throw new Error(`arm ${name}: "${search}" is not prerendered in ${root}`);
    return { name, search, file: `/${cfg.byHash[hash]}` };
  });
  const pw = loadPlaywright();
  const browser = await pw.chromium.launch(process.env.FW_CHROMIUM ? { executablePath: process.env.FW_CHROMIUM } : {});
  const passes = [];
  try {
    for (const pf of v.profile) {
      const profile = JSON.parse(readFileSync(resolve(pf), 'utf8'));
      for (const arm of arms) {
        const srv = await startServer(root, (p) => (p === '/' || p === '/index.html' ? arm.file : null));
        try {
          for (let rep = 1; rep <= Number(v.reps); rep++) {
            const r = await comboPass({ browser, origin: srv.origin, search: arm.search, profile, throttle: Number(v.throttle), settleMs: Number(v.settle), log });
            const { rec, ...rest2 } = r;
            passes.push({ profile: profile.id, armName: arm.name, search: arm.search, rep, ...rest2, ...(v.frames ? { rec } : {}) });
            const m = r.metrics;
            log(`${profile.id} ${arm.name} rep ${rep}: reversals ${m.reversalsNoFinger}, jumps ${m.jumps.n} (max ${m.jumps.max}), script jumps ${m.scriptJumps.n} (max ${m.scriptJumps.max}), writes ${m.writes.n} (down ${m.writes.down}, free ${m.writes.free})`);
          }
        } finally { await srv.close(); }
      }
    }
    const out = { schema: 'fw.replay.combo/1', engine: `chromium ${browser.version()}`, playwright: playwrightVersion(), throttle: Number(v.throttle), passes };
    mkdirSync(resolve(v.out), { recursive: true });
    writeFileSync(join(resolve(v.out), 'run.json'), JSON.stringify(out) + '\n');
    writeFileSync(join(resolve(v.out), 'table.md'), table(out));
    process.stdout.write(table(out));
  } finally { await browser.close(); }
}
if (process.argv[1] && process.argv[1].endsWith('combo-cli.mjs')) main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = 1; });
