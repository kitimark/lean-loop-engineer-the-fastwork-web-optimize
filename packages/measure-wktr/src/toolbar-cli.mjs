// Toolbar forced-inset gate driver (task toolbar-wktr-gate).
//   node src/toolbar-cli.mjs run --root <extracted archive dir> --out <dir> [--flags default,touch-first,open-once,unthrottle] [--passes 2]
// Per flag and pass (a fresh WebKitTestRunnerApp process each) it loads the flag's fixture page (toolbar-page.mjs), which walks
// the interactive obscured-insets change, and writes <out>/toolbar-<flag>-<pass>.json (the page's report) and raw-<flag>-<pass>.txt.
// Judging is gate.mjs. Counts and latencies only; nothing here is phone time.
import http from 'node:http';
import { parseArgs } from 'node:util';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runOnce, DEFAULT_HEADER } from './wktr.mjs';
import * as sim from './sim.mjs';
import { FLAGS, toolbarHtml } from './toolbar-page.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ARCHIVE = JSON.parse(readFileSync(join(HERE, 'archive.json'), 'utf8'));

/** The page report (`FWWKTR toolbar {...}`) and any `error` line of a WKTR output. */
export function parseToolbar(text) {
  const got = { report: null, error: null, done: false };
  for (const line of text.split('\n')) {
    const m = /FWWKTR (toolbar|error|done) (.*)$/.exec(line.trim());
    if (!m) continue;
    const v = JSON.parse(m[2]);
    if (m[1] === 'toolbar') got.report = v;
    else if (m[1] === 'error') got.error = v;
    else got.done = true;
  }
  return got;
}

/** Serve `/<flag>` as that flag's page, no-store, on 127.0.0.1. */
export function serveFlags(flags) {
  const pages = Object.fromEntries(flags.map((f) => [`/${f}`, toolbarHtml({ flag: f })]));
  const server = http.createServer((req, res) => {
    const body = pages[(req.url || '/').split('?')[0]];
    if (!body) {
      res.writeHead(404, { 'content-type': 'text/plain', 'cache-control': 'no-store' });
      return res.end('not found');
    }
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
    res.end(body);
  });
  return new Promise((ok, bad) => {
    server.once('error', bad);
    server.listen(0, '127.0.0.1', () => ok({ url: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((r) => server.close(() => r())) }));
  });
}

async function main() {
  const { values: v, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      root: { type: 'string' }, out: { type: 'string', default: 'out' }, flags: { type: 'string', default: FLAGS.join(',') }, passes: { type: 'string', default: '2' },
      header: { type: 'string', default: DEFAULT_HEADER }, 'device-name': { type: 'string', default: 'fw-wktr' }, 'device-type': { type: 'string', default: 'iPhone 17' },
      'ios-version': { type: 'string', default: '26.5' }, label: { type: 'string', default: 'local' }, keep: { type: 'boolean', default: false }, timeout: { type: 'string', default: '120000' },
    },
  });
  if (positionals[0] !== 'run') throw new Error('usage: toolbar-cli.mjs run --root <dir> --out <dir>');
  const root = resolve(v.root ?? '.cache/wktr-root-324039', ARCHIVE.buildRoot);
  const app = join(root, ARCHIVE.app);
  if (!existsSync(app)) throw new Error(`${app} not found; extract the archive first (scripts/fetch-archive.sh)`);
  const flags = v.flags.split(',').map((x) => x.trim()).filter(Boolean);
  for (const f of flags) if (!FLAGS.includes(f)) throw new Error(`unknown flag ${f}; known: ${FLAGS.join(', ')}`);
  const out = resolve(v.out);
  mkdirSync(out, { recursive: true });
  const passes = Number(v.passes);
  const dev = await sim.ensureDevice({ name: v['device-name'], typeName: v['device-type'], version: v['ios-version'] });
  console.log(`device ${v['device-name']} (${v['device-type']}, iOS ${dev.runtime.version} build ${dev.runtime.buildversion}) created=${dev.created}`);
  await sim.boot(dev.udid);
  await sim.install(dev.udid, app);
  const srv = await serveFlags(flags);
  const failures = [];
  try {
    for (const flag of flags) {
      for (let p = 1; p <= passes; p++) {
        let r, attempts = 0;
        for (;;) {
          attempts++;
          try { r = await runOnce({ udid: dev.udid, root, bundleId: ARCHIVE.bundleId, url: `${srv.url}/${flag}`, header: v.header, timeoutMs: Number(v.timeout) }); break; }
          catch (e) {
            console.log(`${flag} pass ${p} attempt ${attempts} failed: ${String(e.message).split('\n')[0].slice(0, 300)}`);
            if (attempts > 2 || !/closed before the end marker|did not connect/.test(e.message)) { r = null; failures.push(`${flag}-${p}: ${String(e.message).split('\n')[0].slice(0, 200)}`); break; }
          }
        }
        if (!r) continue;
        writeFileSync(join(out, `raw-${flag}-${p}.txt`), r.stdout);
        writeFileSync(join(out, `stderr-${flag}-${p}.txt`), r.stderr);
        const got = parseToolbar(r.stdout);
        if (!got.report) {
          failures.push(`${flag}-${p}: no report (${JSON.stringify(got.error)})`);
          console.log(`${flag} pass ${p}: no report ${JSON.stringify(got.error)}`);
          continue;
        }
        const meta = {
          lane: 'wktr-toolbar', flag, pass: p, label: v.label, attempts, wallMs: r.ms, archive: { revision: ARCHIVE.revision, commit: ARCHIVE.commit, sha256: ARCHIVE.sha256 },
          device: { name: v['device-type'], runtime: dev.runtime.version, runtimeBuild: dev.runtime.buildversion }, header: v.header,
        };
        writeFileSync(join(out, `toolbar-${flag}-${p}.json`), JSON.stringify({ schema: 'fw.wktr.toolbar/1', meta, ...got.report }));
        console.log(`${flag} pass ${p}: ${got.report.steps.length} steps, ${r.ms} ms wall (not phone time)`);
      }
    }
  } finally {
    await srv.close();
    sim.terminate(dev.udid, ARCHIVE.bundleId);
    if (!v.keep) { sim.shutdown(dev.udid); sim.deleteDevice(dev.udid); }
    writeFileSync(join(out, 'failures.json'), JSON.stringify(failures));
  }
  if (failures.length) { console.log(`failures: ${failures.join(' | ')}`); process.exitCode = 1; }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch((e) => { console.error(String(e?.stack || e)); process.exit(1); });
