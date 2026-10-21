#!/usr/bin/env node
// Linux WebKit frame-cause probe (task linux-webkit-probe).
//   node src/linux/cli.mjs run   --out <dir> [--vm 1] [--arms id,id] [--steps 10] [--idle-ms 3000] [--run-id N]
//       Every arm twice (round A over all arms, then round B), one fresh Playwright WebKit per run; writes
//       <dir>/vm<vm>.json (reduced numbers), <dir>/vm<vm>-raw.json (Timeline records and rAF timestamps) and <dir>/env.txt data in vm<vm>.json meta.
//   node src/linux/cli.mjs table --runs <dir> --note <file> [--check]
//       Reads <dir>/*.json (not *-raw.json), regenerates the tables and splices them into <file> between the generated markers;
//       --check fails when the note differs from the regeneration.
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { cpus, arch, platform, release } from 'node:os';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { armList, schedule, selectArms } from './arms.mjs';
import { loadPlaywright, playwrightVersion, runArm } from './run.mjs';
import { startServer } from './serve.mjs';
import { renderBlock, splice } from './table.mjs';

const { positionals, values: v } = parseArgs({
  allowPositionals: true,
  options: {
    out: { type: 'string' }, vm: { type: 'string', default: '1' }, arms: { type: 'string', default: '' }, steps: { type: 'string', default: '10' },
    'idle-ms': { type: 'string', default: '3000' }, 'run-id': { type: 'string', default: process.env.GITHUB_RUN_ID ?? 'local' },
    runs: { type: 'string' }, note: { type: 'string' }, check: { type: 'boolean', default: false }, headline: { type: 'string', default: 'orig-w390-d3' },
  },
});

async function run() {
  if (!v.out) throw new Error('--out <dir> required');
  mkdirSync(v.out, { recursive: true });
  const pw = loadPlaywright();
  const server = await startServer();
  const arms = selectArms(v.arms);
  const meta = {
    vm: v.vm, runId: v['run-id'], sha: process.env.GITHUB_SHA ?? null, node: process.version, os: `${platform()} ${arch()} ${release()}`,
    cpus: cpus().length, cpuModel: cpus()[0]?.model ?? null, steps: Number(v.steps), idleMs: Number(v['idle-ms']),
    playwrightCore: playwrightVersion(),
    webkitEnv: Object.fromEntries(Object.entries(process.env).filter(([k]) => /^(WEBKIT|LP_|GALLIUM|LIBGL|MESA)/.test(k))),
  };
  const out = { meta, runs: [] };
  const rawOut = { meta, runs: [] };
  try {
    for (const { round, arm } of schedule(arms)) {
      const t = Date.now();
      const { raw, reduced } = await runArm({ pw, origin: server.origin, arm, steps: Number(v.steps), idleMs: Number(v['idle-ms']) });
      const { id, page, width, dpr, sw } = arm;
      out.runs.push({ arm: { id, page, width, dpr, sw }, round, reduced });
      rawOut.runs.push({ arm: id, round, records: raw.records, idleRaf: raw.idleRaf, scrollRaf: raw.scrollRaf, steps: raw.steps, fps: raw.fps });
      meta.browser = reduced.browser ?? meta.browser;
      console.log(`${round} ${id}: idle p50 ${reduced.idle.p50} scroll p50 ${reduced.scroll.p50} records ${reduced.timeline.records} steps ${reduced.timeline.stepsDelimited}/${v.steps} ${reduced.error ? `ERROR ${reduced.error}` : ''} (${Date.now() - t} ms)`);
      writeFileSync(join(v.out, `vm${v.vm}.json`), JSON.stringify(out, null, 1));
      writeFileSync(join(v.out, `vm${v.vm}-raw.json`), JSON.stringify(rawOut));
    }
  } finally {
    await server.close();
  }
}

function table() {
  if (!v.runs || !v.note) throw new Error('--runs <dir> and --note <file> required');
  const files = readdirSync(v.runs).filter((f) => f.endsWith('.json') && !f.endsWith('-raw.json')).sort().map((f) => JSON.parse(readFileSync(join(v.runs, f), 'utf8')));
  if (!files.length) throw new Error(`no result files in ${v.runs}`);
  const note = readFileSync(v.note, 'utf8');
  const next = splice(note, renderBlock(files, { headline: v.headline }));
  if (v.check) {
    if (next !== note) { console.error(`${v.note}: generated block differs from ${v.runs}; run the table command`); process.exit(1); }
    console.log(`${v.note}: generated block matches ${files.length} result file(s)`);
    return;
  }
  writeFileSync(v.note, next);
  console.log(`${v.note}: block written from ${files.length} result file(s)`);
}

const cmd = positionals[0];
if (cmd === 'run') await run();
else if (cmd === 'table') table();
else if (cmd === 'arms') console.log(armList().map((a) => a.id).join('\n'));
else { console.error('usage: cli.mjs run|table|arms'); process.exit(64); }
