// WKTR lane driver.   node src/cli.mjs run --root <extracted archive dir> --site <snapshot/site> --out <dir> [options]
// Per pass (a fresh WebKitTestRunnerApp process each): load the original with the harness script, scroll it with native
// requestAnimationFrame, and write <out>/counts-<pass>.json (frames for the class policy) and <out>/raw-<pass>.txt.
import { parseArgs } from 'node:util';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { harnessSource } from './harness.mjs';
import { serveOriginal } from './server.mjs';
import { runOnce, DEFAULT_HEADER } from './wktr.mjs';
import { buildRun, parseOutput } from './reduce.mjs';
import * as sim from './sim.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ARCHIVE = JSON.parse(readFileSync(join(HERE, 'archive.json'), 'utf8'));

const { values: v, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    root: { type: 'string' }, site: { type: 'string' }, out: { type: 'string', default: 'out' },
    passes: { type: 'string', default: '2' }, step: { type: 'string', default: '50' }, frames: { type: 'string', default: '2' },
    settle: { type: 'string', default: '6000' }, header: { type: 'string', default: DEFAULT_HEADER },
    'device-name': { type: 'string', default: 'fw-wktr' }, 'device-type': { type: 'string', default: 'iPhone 17' },
    'ios-version': { type: 'string', default: '26.5' }, label: { type: 'string', default: 'local' },
    keep: { type: 'boolean', default: false }, warm: { type: 'boolean', default: false }, timeout: { type: 'string', default: '240000' },
  },
});

async function main() {
  if (positionals[0] !== 'run') throw new Error('usage: cli.mjs run --root <dir> --site <snapshot/site> --out <dir>');
  const root = resolve(v.root ?? '.cache/wktr-root-324039', ARCHIVE.buildRoot);
  const app = join(root, ARCHIVE.app);
  if (!existsSync(app)) throw new Error(`${app} not found; extract the archive first (scripts/fetch-archive.sh)`);
  const site = resolve(v.site ?? process.env.FW_SNAPSHOT_SITE ?? 'snapshot/site');
  if (!existsSync(join(site, 'index.html'))) throw new Error(`${site}/index.html not found`);
  const out = resolve(v.out);
  mkdirSync(out, { recursive: true });
  const passes = Number(v.passes), step = Number(v.step), frames = Number(v.frames), settleMs = Number(v.settle), warm = v.warm;
  const tag = warm ? 'warm-' : '';

  const dev = sim.ensureDevice({ name: v['device-name'], typeName: v['device-type'], version: v['ios-version'] });
  console.log(`device ${v['device-name']} (${v['device-type']}, iOS ${dev.runtime.version} build ${dev.runtime.buildversion}) created=${dev.created}`);
  sim.boot(dev.udid);
  sim.install(dev.udid, app);
  const srv = await serveOriginal(site, harnessSource({ step, frames, settleMs, warm }));
  console.log(`serving ${site} at ${srv.url}`);
  const results = [];
  try {
    for (let p = 1; p <= passes; p++) {
      // The app's GPU process sometimes crashes at launch on a runner ("#CRASHED - com.apple.WebKit.GPU.Development", no
      // output at all): such a pass has no counts, so launch a fresh process again (up to 2 retries) and record the attempts.
      let r, attempts = 0;
      for (;;) {
        attempts++;
        try { r = await runOnce({ udid: dev.udid, root, bundleId: ARCHIVE.bundleId, url: srv.url, header: v.header, timeoutMs: Number(v.timeout) }); break; }
        catch (e) {
          console.log(`pass ${p} attempt ${attempts} failed: ${String(e.message).split('\n')[0].slice(0, 300)}`);
          if (attempts > 2 || !/closed before the end marker|did not connect/.test(e.message)) throw e;
        }
      }
      writeFileSync(join(out, `raw-${tag}${p}.txt`), r.stdout);
      writeFileSync(join(out, `stderr-${tag}${p}.txt`), r.stderr);
      const parsed = parseOutput(r.stdout);
      const run = buildRun(parsed, {
        lane: 'wktr', label: v.label, pass: p, archive: { revision: ARCHIVE.revision, commit: ARCHIVE.commit, sha256: ARCHIVE.sha256 },
        device: { name: v['device-type'], runtime: dev.runtime.version, runtimeBuild: dev.runtime.buildversion },
        header: v.header, step, frames, settleMs, warm, attempts, wallMs: r.ms,
      });
      writeFileSync(join(out, `counts-${tag}${p}.json`), JSON.stringify(run));
      const tot = {};
      for (const f of run.frames) for (const [k, n] of Object.entries(f.counts)) tot[k] = (tot[k] || 0) + n;
      results.push(tot);
      console.log(`pass ${p}: ${run.frames.length} steps, ${r.ms} ms wall (not phone time); totals ${JSON.stringify(tot)}`);
      console.log(`viewport ${run.meta.page.innerWidth}x${run.meta.page.innerHeight}, dpr ${run.meta.page.dpr}`);
    }
  } finally {
    await srv.close();
    sim.terminate(dev.udid, ARCHIVE.bundleId);
    if (!v.keep) { sim.shutdown(dev.udid); sim.deleteDevice(dev.udid); }
  }
}

main().catch((e) => { console.error(String(e?.stack || e)); process.exit(1); });
