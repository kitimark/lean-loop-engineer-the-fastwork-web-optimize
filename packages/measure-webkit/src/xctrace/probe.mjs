#!/usr/bin/env node
// Local xctrace probe (mac-safari-measure): does Animation Hitches and/or Metal System Trace record (a) the iOS Simulator's Safari,
// (b) macOS Safari on this Mac? Each attempt records a few seconds while the page scrolls, then exports the table of contents and the
// hitch tables. The answer is the exact refusal or the row count; nothing here decides (Lean `hitchesRecorded` does, through parse.mjs).
//   node probe.mjs --site <build dir> --target sim|mac|both [--out file.json] [--seconds 6]
import { spawnSync, spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { parseToc, countRows, errorLines, verdictOf } from './parse.mjs';

const { values: v } = parseArgs({ options: { site: { type: 'string' }, target: { type: 'string', default: 'both' }, out: { type: 'string' }, seconds: { type: 'string', default: '6' }, 'attach-seconds': { type: 'string', default: '16' }, arms: { type: 'string', default: 'orig,base,hx,mp,pf' }, 'mac-all': { type: 'string', default: 'yes' }, device: { type: 'string', default: 'fw-mac-safari-27' } } });
process.env.FW_SIM_NAME = v.device;
const log = (s) => console.error(`${new Date().toISOString().slice(11, 19)} ${s}`);
const sh = (cmd, args, timeout = 120000) => { const r = spawnSync(cmd, args, { encoding: 'utf8', timeout, maxBuffer: 64 << 20 }); return { status: r.status, out: r.stdout || '', err: r.stderr || '', timedOut: r.error?.code === 'ETIMEDOUT' }; };
const TEMPLATES = ['Animation Hitches', 'Metal System Trace'];
const secs = Number(v.seconds);
const attachSecs = Number(v['attach-seconds']);

/** Record one template while `during()` runs, then export. Returns the entry for the result file. */
async function attempt(target, template, recordArgs, during, dir, limit = secs) {
  const trace = join(dir, `${target}-${template.replace(/\W+/g, '-')}.trace`);
  const args = ['record', '--template', template, ...recordArgs, '--time-limit', `${limit}s`, '--output', trace, '--no-prompt'];
  log(`xctrace ${target} ${template}`);
  const rec = spawn('xctrace', args, { stdio: ['ignore', 'pipe', 'pipe'] });
  let text = '';
  rec.stdout.on('data', (d) => { text += d; }); rec.stderr.on('data', (d) => { text += d; });
  await new Promise((r) => setTimeout(r, 2500));
  await during().catch((e) => { text += `\n[during] ${e.message}`; });
  const code = await new Promise((r) => {
    const stop = setTimeout(() => { try { rec.kill('SIGINT'); } catch { /* gone */ } }, (limit + 60) * 1000);
    const hard = setTimeout(() => { try { rec.kill(); } catch { /* gone */ } r('timeout'); }, (limit + 300) * 1000);
    rec.on('close', (c) => { clearTimeout(stop); clearTimeout(hard); r(c); });
  });
  const tocRun = sh('xctrace', ['export', '--input', trace, '--toc']);
  const toc = parseToc(tocRun.out);
  const exportErr = tocRun.err;
  const hitchSchemas = toc.schemas.filter((s) => /hitch/i.test(s));
  let rows = 0;
  const tables = {};
  for (const s of hitchSchemas) { tables[s] = countRows(sh('xctrace', ['export', '--input', trace, '--xpath', `/trace-toc/run[1]/data/table[@schema="${s}"]`], 300000).out); rows += tables[s]; }
  rmSync(trace, { recursive: true, force: true });
  return { target, template, exit: code, ...verdictOf({ toc, rows }), hitchSchemas, tables, refusal: errorLines(text + '\n' + exportErr) };
}

const dir = mkdtempSync(join(tmpdir(), 'fw-xctrace-'));
const results = [];
const flush = () => { if (v.out) writeFileSync(v.out, JSON.stringify({ lane: 'local', seconds: secs, results }, null, 1) + '\n'); };
const { holdSimSlot } = await import('../safari-local-lease.mjs');
const lease = await holdSimSlot({ cwd: process.cwd(), leaseS: 900, renewEveryS: 120, log });
try {
  const site = v.site ? resolve(v.site) : null;
  if (v.target === 'sim' || v.target === 'both') {
    const { ensureDevice, removeDevice } = await import('../sim-local.mjs');
    const { findDevice, bootDevice, shutdownDevice, openUrl, sleep } = await import('../sim.mjs');
    const made = ensureDevice(v.device).created;
    try {
      const d = await bootDevice({ log });
      const srv = site ? await (await import('../safari-local.mjs')).armServer([{ id: 'base', tree: { dir: site, search: '' } }]) : null;
      openUrl(d.udid, srv ? srv.url : 'https://example.com/');
      await sleep(4000);
      for (const t of TEMPLATES) results.push(await attempt('sim', t, ['--device', findDevice().udid, '--all-processes'], () => sleep(secs * 500), dir));
      if (srv) await srv.close();
      shutdownDevice(d.udid, { log });
    } finally { if (made) { try { removeDevice(v.device); } catch (e) { log(`device delete: ${e.message}`); } } }
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
    const before = new Set(sh('pgrep', ['-x', 'Safari']).out.split('\n').filter(Boolean).map(Number));
    const drv = spawn('safaridriver', ['-p', String(port)], { detached: true, stdio: 'ignore' }); drv.unref();
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
        for (const t of TEMPLATES) results.push(await attempt('mac', t, ['--all-processes'], zone.hero, dir));
      }
      const mine = sh('pgrep', ['-x', 'Safari']).out.split('\n').filter(Boolean).map(Number).filter((p) => !before.has(p));
      if (mine.length) for (const a of arms) for (const w of ['hero', 'end']) {
        await load(a.id);
        results.push({ ...(await attempt('mac-attach', 'Animation Hitches', ['--attach', String(mine[0])], zone[w], dir, attachSecs)), arm: a.id, zone: w });
        flush();
      }
    } finally {
      await wd.close();
      try { process.kill(drv.pid); } catch { /* gone */ }
      for (const p of sh('pgrep', ['-x', 'Safari']).out.split('\n').filter(Boolean).map(Number)) if (!before.has(p)) { try { process.kill(p); } catch { /* gone */ } }
      await server.close();
    }
  }
} finally { rmSync(dir, { recursive: true, force: true }); await lease.release().catch((e) => log(`release: ${e.message}`)); }
const doc = { lane: 'local', xctrace: sh('xctrace', ['version']).out.trim(), seconds: secs, results };
if (v.out) writeFileSync(v.out, JSON.stringify(doc, null, 1) + '\n'); else console.log(JSON.stringify(doc, null, 1));
