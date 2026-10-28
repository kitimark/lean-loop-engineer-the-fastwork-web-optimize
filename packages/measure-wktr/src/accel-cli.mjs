// WebKit half of the geom-track-style probe (task geom-track-style): per morph.geom Web Animation track, does WebKit hold it as an
// accelerated animation (internals.acceleratedAnimationsForElement) and how many style recalcs does each arm pay
// (internals.styleRecalcCount between the arm's windows). One fresh WebKitTestRunnerApp process per mode and pass, the prerendered
// rewrite (apps/site/dist/aot) served with the probe as /__fw/harness.js. Counts only: nothing measured here is phone time.
import { parseArgs } from 'node:util';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serveBuilt } from './repaint-serve.mjs';
import { accelHarnessSource, parseAccel } from './accel-page.mjs';
import { runOnce, DEFAULT_HEADER } from './wktr.mjs';
import * as sim from './sim.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ARCHIVE = JSON.parse(readFileSync(join(HERE, 'archive.json'), 'utf8'));
export const MODES = { scrubbed: 'morph.geom:on', timed: 'morph.geom:on,morph.tween:geom-timed' };

async function main() {
  const { values: v, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      root: { type: 'string' }, dist: { type: 'string' }, out: { type: 'string', default: 'out' }, passes: { type: 'string', default: '1' },
      modes: { type: 'string', default: 'scrubbed,timed' }, arms: { type: 'string' }, header: { type: 'string', default: DEFAULT_HEADER },
      'device-name': { type: 'string', default: 'fw-wktr' }, 'device-type': { type: 'string', default: 'iPhone 17' },
      'ios-version': { type: 'string', default: '26.5' }, label: { type: 'string', default: 'local' }, keep: { type: 'boolean', default: false },
      timeout: { type: 'string', default: '420000' },
    },
  });
  if (positionals[0] !== 'run') throw new Error('usage: accel-cli.mjs run --root <dir> --dist <apps/site/dist/aot> --out <dir>');
  const root = resolve(v.root ?? '.cache/wktr-root-324039', ARCHIVE.buildRoot);
  const app = join(root, ARCHIVE.app);
  if (!existsSync(app)) throw new Error(`${app} not found; extract the archive first (scripts/fetch-archive.sh)`);
  const dist = v.dist ? resolve(v.dist) : null;
  if (!(dist && existsSync(join(dist, 'configs.json')))) throw new Error('--dist <apps/site/dist/aot> with configs.json is needed');
  const modes = v.modes.split(',').map((x) => x.trim()).filter(Boolean);
  for (const m of modes) if (!MODES[m]) throw new Error(`unknown mode ${m}; known: ${Object.keys(MODES).join(', ')}`);
  const arms = v.arms ? v.arms.split(',').map((x) => x.trim()).filter(Boolean) : undefined;
  const out = resolve(v.out);
  mkdirSync(out, { recursive: true });
  const passes = Number(v.passes);
  const dev = await sim.ensureDevice({ name: v['device-name'], typeName: v['device-type'], version: v['ios-version'] });
  console.log(`device ${v['device-name']} (${v['device-type']}, iOS ${dev.runtime.version} build ${dev.runtime.buildversion}) created=${dev.created}`);
  await sim.boot(dev.udid);
  await sim.install(dev.udid, app);
  const failures = [];
  try {
    for (const mode of modes) {
      const search = `?fw=${MODES[mode]}`;
      const srv = await serveBuilt(dist, search, accelHarnessSource({ mode, arms }));
      console.log(`mode ${mode}: serving ${srv.url}${search}`);
      try {
        for (let p = 1; p <= passes; p++) {
          let r, attempts = 0;
          for (;;) {
            attempts++;
            try { r = await runOnce({ udid: dev.udid, root, bundleId: ARCHIVE.bundleId, url: `${srv.url}${search}`, header: v.header, timeoutMs: Number(v.timeout) }); break; }
            catch (e) {
              console.log(`mode ${mode} pass ${p} attempt ${attempts} failed: ${String(e.message).split('\n')[0].slice(0, 300)}`);
              if (attempts > 2 || !/closed before the end marker|did not connect/.test(e.message)) { r = null; failures.push(`${mode}-${p}: ${String(e.message).split('\n')[0].slice(0, 200)}`); break; }
            }
          }
          if (!r) continue;
          writeFileSync(join(out, `raw-${mode}-${p}.txt`), r.stdout);
          writeFileSync(join(out, `stderr-${mode}-${p}.txt`), r.stderr);
          const got = parseAccel(r.stdout);
          if (!got.report) {
            failures.push(`${mode}-${p}: no report (${JSON.stringify(got.error)})`);
            console.log(`${mode} pass ${p}: no report ${JSON.stringify(got.error)}`);
            continue;
          }
          const meta = {
            lane: 'wktr-accel', mode, fw: MODES[mode], pass: p, label: v.label, attempts, wallMs: r.ms, archive: { revision: ARCHIVE.revision, commit: ARCHIVE.commit, sha256: ARCHIVE.sha256 },
            device: { name: v['device-type'], runtime: dev.runtime.version, runtimeBuild: dev.runtime.buildversion }, header: v.header,
          };
          writeFileSync(join(out, `accel-${mode}-${p}.json`), JSON.stringify({ schema: 'fw.track-accel.wktr/1', meta, ...got.report }));
          const all = got.report.rows.find((x) => x.arm === 'all');
          const tbl = all?.table ?? [];
          const acc = tbl.filter((x) => x.accel).length;
          console.log(`${mode} pass ${p}: ${got.report.rows.length} arms, tracks ${all?.tracks ?? 0}, accelerated ${acc}, errors ${got.report.errors.length}${got.report.errors[0] ? ` ${got.report.errors[0].slice(0, 200)}` : ''}, ${r.ms} ms wall (not phone time); viewport ${got.report.facts?.w}x${got.report.facts?.h}`);
        }
      } finally { await srv.close(); }
    }
  } finally {
    sim.terminate(dev.udid, ARCHIVE.bundleId);
    if (!v.keep) { sim.shutdown(dev.udid); sim.deleteDevice(dev.udid); }
    writeFileSync(join(out, 'failures.json'), JSON.stringify(failures));
  }
  if (failures.length) { console.log(`failures: ${failures.join(' | ')}`); process.exitCode = 1; }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch((e) => { console.error(String(e?.stack || e)); process.exit(1); });
