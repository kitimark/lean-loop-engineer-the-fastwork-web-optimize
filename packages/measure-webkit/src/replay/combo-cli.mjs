#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { loadPlaywright, playwrightVersion } from '../linux/run.mjs';
import { startServer } from './combo-serve.mjs';
import { canonSearch } from '../../../contracts/src/flag-key.mjs';
import { comboPass } from './combo-replay.mjs';
import { ranScripted } from './combo-metrics.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: { dist: { type: 'string' }, profile: { type: 'string', multiple: true }, arms: { type: 'string' }, throttle: { type: 'string', default: '6' }, reps: { type: 'string', default: '1' }, out: { type: 'string', default: 'out/combo' }, in: { type: 'string' }, settle: { type: 'string', default: '4000' }, frames: { type: 'boolean', default: false } },
});
const log = (s) => console.error(s);

export function table(run) {
  const rows = ['| profile | arm | rep | frames | morph opens/closes | reversals no finger | jumps >= 20 px (max px) | script jumps >= 20 px (max px) | script writes (finger down / free) | px written (down / free) |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'];
  for (const p of run.passes) {
    const m = p.metrics;
    rows.push(`| ${p.profile} | ${p.armName} | ${p.rep} | ${m.frames} | ${m.morph.opens}/${m.morph.closes} | ${m.reversalsNoFinger} | ${m.jumps.n} (${m.jumps.max}) | ${m.scriptJumps.n} (${m.scriptJumps.max}) | ${m.writes.n} (${m.writes.down} / ${m.writes.free}) | ${Math.round(m.writes.pxDown)} / ${Math.round(m.writes.pxFree)} |`);
  }
  return `${rows.join('\n')}\n`;
}

export function summary(run) {
  const by = new Map();
  for (const p of run.passes) {
    const m = p.metrics;
    const a = by.get(p.armName) ?? { passes: 0, ran: 0, fight: 0, rev: 0, sj: 0, sjMax: 0, wd: 0, wf: 0 };
    a.passes++;
    if (ranScripted(m.morph)) a.ran++;
    if (m.reversalsNoFinger > 0 || m.scriptJumps.n > 0 || m.writes.n > 0) a.fight++;
    a.rev += m.reversalsNoFinger; a.sj += m.scriptJumps.n; a.sjMax = Math.max(a.sjMax, m.scriptJumps.max); a.wd += m.writes.down; a.wf += m.writes.free;
    by.set(p.armName, a);
  }
  const rows = ['| arm | passes | morph ran (2 opens, 1 close) | passes with a script write or jump | reversals no finger | script jumps >= 20 px (max px) | script writes (finger down / free) |', '| --- | --- | --- | --- | --- | --- | --- |'];
  for (const [k, a] of by) rows.push(`| ${k} | ${a.passes} | ${a.ran} | ${a.fight} | ${a.rev} | ${a.sj} (${a.sjMax}) | ${a.wd} / ${a.wf} |`);
  return `${rows.join('\n')}\n`;
}

async function main() {
  if (cmd === 'table') { process.stdout.write(table(JSON.parse(readFileSync(resolve(v.in), 'utf8')))); return; }
  if (cmd === 'summary') { process.stdout.write(summary(JSON.parse(readFileSync(resolve(v.in), 'utf8')))); return; }
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
