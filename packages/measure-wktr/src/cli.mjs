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
import { parseVariant } from './variants.mjs';
import { recorder, timed } from './spans.mjs';

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
    keep: { type: 'boolean', default: false }, variants: { type: 'string', default: 'live' }, timeout: { type: 'string', default: '240000' },
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
  const passes = Number(v.passes), step = Number(v.step), frames = Number(v.frames), settleMs = Number(v.settle);
  const variants = v.variants.split(',').map((x) => x.trim()).filter(Boolean).map(parseVariant);

  // wall-time spans of this invocation (spans-arm-<label>.json): device setup, serving, per-pass teardown, device teardown
  const arm = recorder();
  const dev = await timed(arm, 'ensureDevice', () => sim.ensureDevice({ name: v['device-name'], typeName: v['device-type'], version: v['ios-version'] }));
  console.log(`device ${v['device-name']} (${v['device-type']}, iOS ${dev.runtime.version} build ${dev.runtime.buildversion}) created=${dev.created}`);
  await timed(arm, 'boot', () => sim.boot(dev.udid));
  await timed(arm, 'install', () => sim.install(dev.udid, app));
  const results = [];
  let srv = null;
  try {
   for (const vr of variants) {
    arm.mark('_gap');
    srv = await serveOriginal(site, harnessSource({ step, frames, settleMs, warm: vr.warm, vt: vr.vt, trace: vr.trace, still: vr.still }));
    console.log(`variant ${vr.name}: serving ${site} at ${srv.url}`);
    arm.mark('serve');
    const tag = `${vr.name}-`;
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
      const pass = recorder();
      writeFileSync(join(out, `raw-${tag}${p}.txt`), r.stdout);
      writeFileSync(join(out, `stderr-${tag}${p}.txt`), r.stderr);
      const parsed = parseOutput(r.stdout);
      const run = buildRun(parsed, {
        lane: 'wktr', label: v.label, pass: p, archive: { revision: ARCHIVE.revision, commit: ARCHIVE.commit, sha256: ARCHIVE.sha256 },
        device: { name: v['device-type'], runtime: dev.runtime.version, runtimeBuild: dev.runtime.buildversion },
        header: v.header, variant: vr.name, vt: vr.vt, warm: vr.warm, trace: vr.trace, still: vr.still, step, frames, settleMs, attempts, wallMs: r.ms,
      });
      writeFileSync(join(out, `counts-${tag}${p}.json`), JSON.stringify(run));
      pass.mark('reduce');
      const spans = { ...r.spans, settleInRun: settleMs, ...pass.spans() };
      writeFileSync(join(out, `spans-${tag}${p}.json`), JSON.stringify({ schema: 'fw.wktr.spans/1', label: v.label, variant: vr.name, pass: p, attempts, device: v['device-name'], spans }));
      console.log(`spans ${vr.name} pass ${p}: ${JSON.stringify(spans)}`);
      const tot = {};
      for (const f of run.frames) for (const [k, n] of Object.entries(f.counts)) tot[k] = (tot[k] || 0) + n;
      results.push(tot);
      console.log(`${vr.name} pass ${p}: ${run.frames.length} steps, ${r.ms} ms wall (not phone time); totals ${JSON.stringify(tot)}`);
      console.log(`viewport ${run.meta.page.innerWidth}x${run.meta.page.innerHeight}, dpr ${run.meta.page.dpr}`);
    }
    arm.mark('passes');
    await srv.close();
    srv = null;
   }
  } finally {
    if (srv) await srv.close();
    arm.mark('_gap');
    sim.terminate(dev.udid, ARCHIVE.bundleId);
    if (!v.keep) { sim.shutdown(dev.udid); sim.deleteDevice(dev.udid); }
    arm.mark('deviceTeardown');
    const total = arm.sinceStart();
    writeFileSync(join(out, `spans-arm-${v.variants.replace(/,/g, '+')}.json`), JSON.stringify({ schema: 'fw.wktr.spans.arm/1', label: v.label, variants: v.variants, passes, device: v['device-name'], totalMs: total, spans: arm.spans() }));
    console.log(`arm spans ${v.label} ${v.variants}: total ${total} ms ${JSON.stringify(arm.spans())}`);
  }
}

main().catch((e) => { console.error(String(e?.stack || e)); process.exit(1); });
