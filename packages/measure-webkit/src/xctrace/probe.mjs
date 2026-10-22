#!/usr/bin/env node
import { spawnSync, spawn } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { attempt } from './attempt.mjs';
import { makeGuard, assertOwnDir, sweepStale } from './guard.mjs';

const { values: v } = parseArgs({ options: { site: { type: 'string' }, target: { type: 'string', default: 'both' }, out: { type: 'string' }, seconds: { type: 'string', default: '6' }, 'attach-seconds': { type: 'string', default: '16' }, arms: { type: 'string', default: 'orig,base,hx,mp,pf' }, 'mac-all': { type: 'string', default: 'yes' }, device: { type: 'string', default: 'fw-mac-safari-27' } } });
if (!v.out) { console.error('usage: probe.mjs --site <dir> --target sim|mac|both --out <file.json>'); process.exit(2); }
process.env.FW_SIM_NAME = v.device;
const log = (s) => console.error(`${new Date().toISOString().slice(11, 19)} ${s}`);
const quick = (cmd, args) => { const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: 15000 }); return r.stdout || ''; };
const TEMPLATES = ['Animation Hitches', 'Metal System Trace'];
const secs = Number(v.seconds);
const attachSecs = Number(v['attach-seconds']);

const out = resolve(v.out);
const root = join(dirname(out), '.xctrace');
mkdirSync(root, { recursive: true });
const swept = sweepStale(root);
if (swept.length) log(`removed ${swept.length} work dir(s) of earlier probes that are gone`);
const workDir = assertOwnDir(join(root, `work-${process.pid}`));
const guard = makeGuard({ workDir });
const results = [];
const flush = () => writeFileSync(out, JSON.stringify({ lane: 'local', seconds: secs, results }, null, 1) + '\n');
let lease = null;
let closing = false;
const onExit = [];
const cleanup = async () => {
  if (closing) return; closing = true;
  guard.killAll();
  for (const f of onExit) { try { f(); } catch {} }
  rmSync(workDir, { recursive: true, force: true });
  try { rmSync(root, { recursive: false }); } catch {}
  await lease?.release().catch((e) => log(`release: ${e.message}`));
};
for (const sig of ['SIGTERM', 'SIGINT', 'SIGHUP']) process.on(sig, () => { log(`${sig}: stopping`); cleanup().finally(() => process.exit(130)); });
guard.watchParent(() => { log('the parent process is gone: stopping'); cleanup().finally(() => process.exit(1)); });

const rec = (target, template, recordArgs, during, limitS = secs) => attempt({ guard, lease, target, template, recordArgs, during, limitS, log });
try {
  const { holdSimSlot, holdMeasureSlot } = await import('../safari-local-lease.mjs');
  if (v.target === 'mac') {
    lease = await holdMeasureSlot({ cwd: process.cwd(), leaseS: 900, renewEveryS: 120, log });
    if (!(await lease.pass.start(Math.max(300, secs * 8), 300))) throw new Error('the slot gave no exclusive pass: other holders stayed live');
  } else lease = await holdSimSlot({ cwd: process.cwd(), leaseS: 900, renewEveryS: 120, log });
  const site = v.site ? resolve(v.site) : null;
  if (v.target === 'sim' || v.target === 'both') {
    const { ensureDevice } = await import('../sim-local.mjs');
    const { findDevice, bootDevice, shutdownDevice, openUrl, sleep } = await import('../sim.mjs');
    ensureDevice(v.device);
    const d = await bootDevice({ log });
    try {
      const srv = site ? await (await import('../safari-local.mjs')).armServer([{ id: 'base', tree: { dir: site, search: '' } }]) : null;
      openUrl(d.udid, srv ? srv.url : 'https://example.com/');
      await sleep(4000);
      for (const t of TEMPLATES) results.push(await rec('sim', t, ['--device', findDevice().udid, '--all-processes'], () => sleep(secs * 500)));
      if (srv) await srv.close();
    } finally { shutdownDevice(d.udid, { log }); }
  }
  if ((v.target === 'mac' || v.target === 'both') && site) {
    const { armServer, webdriver, freePort } = await import('../safari-local.mjs');
    const { RECORDER_SRC, TO_END_JS, heroJs, endJs } = await import('../profile/recorder.mjs');
    const { HERO_BURST, END_PUSH } = await import('../../../gate-breakpoints/src/smooth/schedule.mjs');
    const { localArms } = await import('../safari-local-run.mjs');
    const { arms: all } = localArms(site);
    const arms = all.filter((a) => v.arms.split(',').includes(a.id));
    const server = await armServer(arms);
    const port = await freePort();
    const pgrep = () => quick('pgrep', ['-x', 'Safari']).split('\n').filter(Boolean).map(Number);
    const before = new Set(pgrep());
    const drv = spawn('safaridriver', ['-p', String(port)], { detached: true, stdio: 'ignore' }); drv.unref();
    onExit.push(() => process.kill(drv.pid));
    const wd = webdriver(`http://127.0.0.1:${port}`);
    const wait = (ms) => new Promise((r) => setTimeout(r, ms));
    const load = async (id) => { server.setArm(id); await wd.navigate(`${server.url}${arms.find((a) => a.id === id).search}`); await wait(4000); await wd.sync(RECORDER_SRC); };
    try {
      await wait(1500);
      await wd.newSession(); await wd.timeouts(90000);
      await wd.setRect({ x: 0, y: 0, width: 430, height: 932 }).catch(() => null);
      const zone = { hero: () => wd.expr(heroJs(HERO_BURST)), end: async () => { await wd.expr(TO_END_JS); await wd.expr(endJs(END_PUSH)); } };
      if (v['mac-all'] === 'yes') {
        await load(arms[0].id);
        for (const t of TEMPLATES) results.push(await rec('mac', t, ['--all-processes'], zone.hero));
      }
      const mine = pgrep().filter((p) => !before.has(p));
      if (mine.length) for (const a of arms) for (const w of ['hero', 'end']) {
        await load(a.id);
        results.push({ ...(await rec('mac-attach', 'Animation Hitches', ['--attach', String(mine[0])], zone[w], attachSecs)), arm: a.id, zone: w });
        flush();
      }
    } finally {
      await wd.close();
      try { process.kill(drv.pid); } catch {}
      for (const p of pgrep()) if (!before.has(p)) { try { process.kill(p); } catch {} }
      await server.close();
    }
  }
  writeFileSync(out, JSON.stringify({ lane: 'local', xctrace: quick('xctrace', ['version']).trim(), seconds: secs, results }, null, 1) + '\n');
} finally { await cleanup(); }
