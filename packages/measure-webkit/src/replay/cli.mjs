#!/usr/bin/env node
//   node packages/measure-webkit/src/replay/cli.mjs run --profile packages/measure-chromium/profiles/user-fixture.json \
//        [--kinds recorded,fast-fling,cold] [--reps 2] [--throttle 6] [--out out/device-replay]
//   node packages/measure-webkit/src/replay/cli.mjs table --in out/device-replay/run.json     (markdown for the step summary)
import { parseArgs } from 'node:util';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { loadPlaywright, playwrightVersion } from '../linux/run.mjs';
import { startServer } from '../linux/serve.mjs';
import { fromCiProfile, makeProfile, schedule, LIM } from '../device-replay.mjs';
import { chromiumPass, table } from './chromium-replay.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: {
    profile: { type: 'string' }, kinds: { type: 'string', default: 'recorded,fast-fling,cold' }, reps: { type: 'string', default: '2' }, throttle: { type: 'string', default: '6' },
    n: { type: 'string', default: '5' }, gap: { type: 'string', default: '300' }, out: { type: 'string', default: 'out/device-replay' }, in: { type: 'string' }, settle: { type: 'string', default: '4000' },
  },
});
const log = (s) => console.error(s);

async function main() {
  if (cmd === 'table') {
    process.stdout.write(table(JSON.parse(readFileSync(resolve(v.in), 'utf8'))));
    return;
  }
  if (cmd !== 'run' || !v.profile) { console.error('usage: run --profile <ci profile.json> [--kinds ..] [--reps n] [--throttle 6] [--out dir] | table --in run.json'); process.exitCode = 2; return; }
  const base = fromCiProfile(JSON.parse(readFileSync(resolve(v.profile), 'utf8')));
  const kinds = v.kinds.split(',').filter(Boolean);
  const gen = { n: Number(v.n), gap: Math.round(Number(v.gap) * 100), reps: 1 };
  const pw = loadPlaywright();
  const srv = await startServer();
  const browser = await pw.chromium.launch();
  const passes = [];
  try {
    for (const run of schedule(kinds, Number(v.reps), 1)) {
      const profile = makeProfile({ profile: base, zone: null }, run.kind, gen);
      if (profile === null) { log(`kind ${run.kind}: nothing to replay; skipped`); continue; }
      const r = await chromiumPass({ browser, origin: srv.origin, profile, throttle: Number(v.throttle), settleMs: Number(v.settle), log });
      passes.push({ kind: run.kind, rep: run.rep, profile: profile.id, ...r });
      log(`${run.kind} rep ${run.rep}: replayMatches ${r.matches}, ${r.swipesSeen}/${r.swipesSent} swipes, frames >34 ms ${r.report.total.over34}/${r.report.total.n}`);
    }
    const out = { schema: 'fw.replay.chromium/1', engine: `chromium ${browser.version()}`, playwright: playwrightVersion(), throttle: Number(v.throttle), lim: LIM, profile: base.id, passes };
    mkdirSync(resolve(v.out), { recursive: true });
    writeFileSync(join(resolve(v.out), 'run.json'), JSON.stringify(out, null, 1) + '\n');
    writeFileSync(join(resolve(v.out), 'table.md'), table(out));
    process.stdout.write(table(out));
  } finally {
    await browser.close();
    await srv.close();
  }
}
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = 1; });
