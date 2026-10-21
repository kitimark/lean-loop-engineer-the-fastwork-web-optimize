#!/usr/bin/env node
// node src/xctrace/cli.mjs run [--arms a,b] [--passes 2] [--reps 4] [--step 25] [--frames 2] [--sudo auto|yes|no] [--limit s] [--stop-wait s] [--natural] [--out dir] [--keep-traces]
//   one Simulator session: Safari loads the page once; for each arm and pass one `xctrace record` of the scripted two-zone scroll,
//   `xctrace export` of the wanted tables, and <out>/<arm>-p<n>.json with the sweep windows and what xctrace said.
// node src/xctrace/cli.mjs serve [--port 8731]   the snapshot, read-only, until SIGTERM (the XCTHitchMetric job)
// node src/xctrace/cli.mjs reduce --dir out [--json file]   per-zone counts of every exported pass (reduce.mjs)
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { withSession, snapshotRoot, FIXTURES } from '../session.mjs';
import { serveTree } from '../serve.mjs';
import { watch } from '../watchdog.mjs';
import { loadFresh, pageInfo } from '../page.mjs';
import { sleep, findDevice } from '../sim.mjs';
import { ARMS, armById } from './arms.mjs';
import { startRecording, exportTrace } from './record.mjs';
import { scrollZones } from './scroll.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: {
    arms: { type: 'string', default: ARMS.map((a) => a.id).join(',') }, passes: { type: 'string', default: '2' }, reps: { type: 'string', default: '4' },
    step: { type: 'string', default: '25' }, frames: { type: 'string', default: '2' }, sudo: { type: 'string', default: 'auto' },
    out: { type: 'string', default: 'out/xctrace' }, 'keep-traces': { type: 'boolean', default: false }, natural: { type: 'boolean', default: false },
    site: { type: 'string' }, search: { type: 'string', default: '' }, settle: { type: 'string', default: '6000' },
    limit: { type: 'string', default: '90' }, 'stop-wait': { type: 'string', default: '90' },
    dir: { type: 'string' }, json: { type: 'string' }, port: { type: 'string', default: '8731' },
  },
  allowNegative: true,
});
const log = (s) => console.error(s);

/** One recorded pass of an arm. Never throws for an xctrace problem: the problem is the result. */
async function onePass(ctx, arm, pass, info, outDir) {
  const name = `${arm.id}-p${pass}`;
  const trace = join(outDir, `${name}.trace`);
  const rec = { arm: arm.id, pass, startedAt: null, windows: null, notes: [] };
  let sudo = v.sudo === 'yes';
  let r = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    try { rmSync(trace, { recursive: true, force: true }); } catch { /* a trace left by a sudo recording belongs to root */ }
    r = await startRecording(arm, { udid: ctx.udid, out: trace, sudo, log, limitS: Number(v.limit), stopMs: Number(v['stop-wait']) * 1000 });
    if (r.started || v.sudo !== 'auto' || sudo) break;
    rec.notes.push(`without sudo: ${r.exited ? `exited ${r.exited.code ?? r.exited.sig}` : 'no start line'}: ${r.output.trim().split('\n').slice(-3).join(' | ')}`);
    await r.stop();
    sudo = true;
  }
  rec.sudo = sudo;
  rec.started = r.started;
  rec.startedAt = r.startedAt;
  if (r.started) {
    await sleep(2000); // the recorder warms up before the first sweep
    try { rec.windows = await scrollZones(ctx.c, info, { step: Number(v.step), frames: Number(v.frames), reps: Number(v.reps) }); } catch (e) { rec.notes.push(`scroll: ${e.message}`); }
    await sleep(1500);
  }
  const stopped = await r.stop({ natural: v.natural });
  rec.stopped = stopped;
  rec.xctraceOutput = r.output.slice(-4000);
  if (r.started) {
    const ex = exportTrace(trace, join(outDir, name), { log, sudo });
    rec.schemas = ex.schemas;
    rec.tables = ex.tables;
  }
  writeFileSync(join(outDir, `${name}.json`), JSON.stringify(rec, null, 1) + '\n');
  if (!v['keep-traces']) { try { rmSync(trace, { recursive: true, force: true }); } catch (e) { rec.notes.push(`trace not removed: ${e.code}`); } }
  log(`${name}: started ${rec.started}, ${rec.windows ? rec.windows.length : 0} sweeps, ${rec.tables?.length ?? 0} tables`);
  return rec;
}

async function main() {
  switch (cmd) {
    case 'run': {
      const outDir = resolve(v.out);
      mkdirSync(outDir, { recursive: true });
      const arms = v.arms.split(',').filter(Boolean).map(armById);
      await withSession(async (ctx) => {
        ctx.udid = findDevice().udid;
        await loadFresh(ctx.c, { clock: 'pinned', settleMs: Number(v.settle) });
        const info = await pageInfo(ctx.c);
        log(`page: vw ${info.vw} vh ${info.vh} dpr ${info.dpr} maxY ${info.maxY}`);
        writeFileSync(join(outDir, 'page.json'), JSON.stringify(info) + '\n');
        for (let pass = 1; pass <= Number(v.passes); pass++) for (const arm of arms) await onePass(ctx, arm, pass, info, outDir);
      }, { keep: true, vendors: 'off', site: v.site ? { dir: v.site, search: v.search } : null });
      break;
    }
    case 'serve': {
      // the snapshot on a fixed port for the XCTHitchMetric job (Safari is opened on it by `simctl openurl`); ends on SIGTERM
      const root = snapshotRoot();
      const server = await serveTree(root, { port: Number(v.port), vendors: 'off', mounts: { '/__fixtures': FIXTURES } });
      log(`serving the snapshot read-only at ${server.url}`);
      await new Promise((res) => { for (const s of ['SIGTERM', 'SIGINT']) process.once(s, () => server.close().finally(res)); });
      break;
    }
    case 'reduce': {
      const { reduceDir } = await import('./reduce.mjs');
      const dir = resolve(v.dir ?? v.out);
      const res = reduceDir(dir, { readFileSync, readdirSync, existsSync, join });
      const text = JSON.stringify(res, null, 1) + '\n';
      if (v.json) writeFileSync(resolve(v.json), text); else process.stdout.write(text);
      break;
    }
    default:
      console.error('usage: run|reduce');
      process.exitCode = 2;
  }
}
const guard = watch();
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = e.exitCode ?? 1; }).finally(() => guard.done(process.exitCode ?? 0));
