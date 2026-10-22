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

const { values: v } = parseArgs({ options: { site: { type: 'string' }, target: { type: 'string', default: 'both' }, out: { type: 'string' }, seconds: { type: 'string', default: '6' }, device: { type: 'string', default: 'fw-mac-safari-27' } } });
process.env.FW_SIM_NAME = v.device;
const log = (s) => console.error(`${new Date().toISOString().slice(11, 19)} ${s}`);
const sh = (cmd, args, timeout = 120000) => { const r = spawnSync(cmd, args, { encoding: 'utf8', timeout, maxBuffer: 64 << 20 }); return { status: r.status, out: r.stdout || '', err: r.stderr || '', timedOut: r.error?.code === 'ETIMEDOUT' }; };
const TEMPLATES = ['Animation Hitches', 'Metal System Trace'];
const secs = Number(v.seconds);

/** Record one template while `during()` runs, then export. Returns the entry for the result file. */
async function attempt(target, template, recordArgs, during, dir) {
  const trace = join(dir, `${target}-${template.replace(/\W+/g, '-')}.trace`);
  const args = ['record', '--template', template, ...recordArgs, '--time-limit', `${secs}s`, '--output', trace, '--no-prompt'];
  log(`xctrace ${target} ${template}`);
  const rec = spawn('xctrace', args, { stdio: ['ignore', 'pipe', 'pipe'] });
  let text = '';
  rec.stdout.on('data', (d) => { text += d; }); rec.stderr.on('data', (d) => { text += d; });
  await new Promise((r) => setTimeout(r, 2500));
  await during().catch((e) => { text += `\n[during] ${e.message}`; });
  const code = await new Promise((r) => { const t = setTimeout(() => { try { rec.kill(); } catch { /* gone */ } r('timeout'); }, (secs + 90) * 1000); rec.on('close', (c) => { clearTimeout(t); r(c); }); });
  const tocRun = sh('xctrace', ['export', '--input', trace, '--toc']);
  const toc = parseToc(tocRun.out);
  const exportErr = tocRun.err;
  const hitchSchemas = toc.schemas.filter((s) => /hitch/i.test(s));
  let rows = 0;
  for (const s of hitchSchemas) rows += countRows(sh('xctrace', ['export', '--input', trace, '--xpath', `/trace-toc/run[1]/data/table[@schema="${s}"]`], 300000).out);
  return { target, template, exit: code, ...verdictOf({ toc, rows }), hitchSchemas, refusal: errorLines(text + '\n' + exportErr) };
}

const dir = mkdtempSync(join(tmpdir(), 'fw-xctrace-'));
const results = [];
try {
  const site = v.site ? resolve(v.site) : null;
  if (v.target === 'sim' || v.target === 'both') {
    const { ensureDevice, removeDevice } = await import('../sim-local.mjs');
    const { findDevice, bootDevice, shutdownDevice, openUrl, sleep } = await import('../sim.mjs');
    const made = ensureDevice(v.device).created;
    try {
      const d = await bootDevice({ log });
      openUrl(d.udid, 'about:blank');
      for (const t of TEMPLATES) results.push(await attempt('sim', t, ['--device', findDevice().udid, '--all-processes'], () => sleep(secs * 500), dir));
      shutdownDevice(d.udid, { log });
    } finally { if (made) { try { removeDevice(v.device); } catch (e) { log(`device delete: ${e.message}`); } } }
  }
  if ((v.target === 'mac' || v.target === 'both') && site) {
    const { armServer, webdriver, freePort } = await import('../safari-local.mjs');
    const { heroJs } = await import('../profile/recorder.mjs');
    const { HERO_BURST } = await import('../../../gate-breakpoints/src/smooth/schedule.mjs');
    const server = await armServer([{ id: 'base', tree: { dir: site, search: '' } }]);
    const port = await freePort();
    const before = new Set(sh('pgrep', ['-x', 'Safari']).out.split('\n').filter(Boolean).map(Number));
    const drv = spawn('safaridriver', ['-p', String(port)], { detached: true, stdio: 'ignore' }); drv.unref();
    const wd = webdriver(`http://127.0.0.1:${port}`);
    try {
      await new Promise((r) => setTimeout(r, 1500));
      await wd.newSession(); await wd.timeouts(90000);
      await wd.navigate(server.url);
      await new Promise((r) => setTimeout(r, 4000));
      const { RECORDER_SRC } = await import('../profile/recorder.mjs');
      for (const t of TEMPLATES) {
        results.push(await attempt('mac', t, ['--all-processes'], async () => { await wd.sync(RECORDER_SRC); await wd.expr(heroJs(HERO_BURST)); }, dir));
      }
    } finally {
      await wd.close();
      try { process.kill(drv.pid); } catch { /* gone */ }
      for (const p of sh('pgrep', ['-x', 'Safari']).out.split('\n').filter(Boolean).map(Number)) if (!before.has(p)) { try { process.kill(p); } catch { /* gone */ } }
      await server.close();
    }
  }
} finally { rmSync(dir, { recursive: true, force: true }); }
const doc = { lane: 'local', xctrace: sh('xctrace', ['version']).out.trim(), seconds: secs, results };
if (v.out) writeFileSync(v.out, JSON.stringify(doc, null, 1) + '\n'); else console.log(JSON.stringify(doc, null, 1));
