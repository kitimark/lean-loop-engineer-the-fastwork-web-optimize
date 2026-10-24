import { parseArgs } from 'node:util';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serveOriginal } from './server.mjs';
import { serveBuilt } from './repaint-serve.mjs';
import { repaintHarnessSource } from './repaint-page.mjs';
import { runOnce, DEFAULT_HEADER } from './wktr.mjs';
import { parseRepaint, buildRepaintRun, reduceRun, ZONES, ARMS } from './repaint.mjs';
import * as sim from './sim.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ARCHIVE = JSON.parse(readFileSync(join(HERE, 'archive.json'), 'utf8'));

const { values: v, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    root: { type: 'string' }, site: { type: 'string' }, dist: { type: 'string' }, out: { type: 'string', default: 'out' },
    passes: { type: 'string', default: '1' }, arms: { type: 'string', default: 'orig,rewrite,v2' },
    settle: { type: 'string', default: '6000' }, 'max-frames': { type: 'string', default: '0' }, header: { type: 'string', default: DEFAULT_HEADER },
    'device-name': { type: 'string', default: 'fw-wktr' }, 'device-type': { type: 'string', default: 'iPhone 17' },
    'ios-version': { type: 'string', default: '26.5' }, label: { type: 'string', default: 'local' },
    keep: { type: 'boolean', default: false }, timeout: { type: 'string', default: '900000' },
  },
});

async function main() {
  if (positionals[0] !== 'run') throw new Error('usage: repaint-cli.mjs run --root <dir> --site <snapshot/site> --dist <apps/site/dist/aot> --out <dir>');
  const root = resolve(v.root ?? '.cache/wktr-root-324039', ARCHIVE.buildRoot);
  const app = join(root, ARCHIVE.app);
  if (!existsSync(app)) throw new Error(`${app} not found; extract the archive first (scripts/fetch-archive.sh)`);
  const arms = v.arms.split(',').map((x) => x.trim()).filter(Boolean);
  for (const a of arms) if (!ARMS[a]) throw new Error(`unknown arm ${a}; known: ${Object.keys(ARMS).join(', ')}`);
  const site = resolve(v.site ?? process.env.FW_SNAPSHOT_SITE ?? 'snapshot/site');
  if (arms.includes('orig') && !existsSync(join(site, 'index.html'))) throw new Error(`${site}/index.html not found`);
  const dist = v.dist ? resolve(v.dist) : null;
  if (arms.some((a) => ARMS[a].tree === 'built') && !(dist && existsSync(join(dist, 'configs.json')))) throw new Error('--dist <apps/site/dist/aot> with configs.json is needed for the rewrite arms');
  const out = resolve(v.out);
  mkdirSync(out, { recursive: true });
  const passes = Number(v.passes);
  const js = repaintHarnessSource({ settleMs: Number(v.settle), maxFrames: Number(v['max-frames']) });

  const dev = await sim.ensureDevice({ name: v['device-name'], typeName: v['device-type'], version: v['ios-version'] });
  console.log(`device ${v['device-name']} (${v['device-type']}, iOS ${dev.runtime.version} build ${dev.runtime.buildversion}) created=${dev.created}`);
  await sim.boot(dev.udid);
  await sim.install(dev.udid, app);
  const failures = [];
  try {
    for (const arm of arms) {
      const spec = ARMS[arm];
      const srv = spec.tree === 'snapshot' ? await serveOriginal(site, js) : await serveBuilt(dist, spec.search, js);
      console.log(`arm ${arm}: serving ${spec.tree} at ${srv.url}${spec.search}`);
      try {
        for (let p = 1; p <= passes; p++) {
          let r, attempts = 0;
          for (;;) {
            attempts++;
            try { r = await runOnce({ udid: dev.udid, root, bundleId: ARCHIVE.bundleId, url: srv.url + spec.search, header: v.header, timeoutMs: Number(v.timeout) }); break; }
            catch (e) {
              console.log(`arm ${arm} pass ${p} attempt ${attempts} failed: ${String(e.message).split('\n')[0].slice(0, 300)}`);
              if (attempts > 2 || !/closed before the end marker|did not connect/.test(e.message)) { r = null; failures.push(`${arm}-${p}: ${String(e.message).split('\n')[0].slice(0, 200)}`); break; }
            }
          }
          if (!r) continue;
          writeFileSync(join(out, `raw-${arm}-${p}.txt.gz`), gzipSync(r.stdout));
          writeFileSync(join(out, `stderr-${arm}-${p}.txt`), r.stderr);
          const parsed = parseRepaint(r.stdout);
          let run;
          try { run = buildRepaintRun(parsed); } catch (e) { console.log(`arm ${arm} pass ${p}: ${e.message}`); failures.push(`${arm}-${p}: ${e.message.slice(0, 200)}`); continue; }
          const red = reduceRun(run);
          const info = {
            lane: 'wktr-repaint', arm, pass: p, label: v.label, attempts, wallMs: r.ms, archive: { revision: ARCHIVE.revision, commit: ARCHIVE.commit },
            device: { name: v['device-type'], runtime: dev.runtime.version, runtimeBuild: dev.runtime.buildversion }, header: v.header, configHash: srv.hash ?? null,
            page: { ...run.meta, els: undefined }, probe: run.meta.probe,
          };
          for (const z of ZONES) writeFileSync(join(out, `counts-${arm}-${z}-${p}.json`), JSON.stringify({ schema: 'fw.wktr.scroll/1', meta: { ...info, zone: z }, frames: red.byZone[z] }));
          writeFileSync(join(out, `table-${arm}-${p}.json`), JSON.stringify({ schema: 'fw.paintvisible.table/1', meta: info, frames: red.frames, calls: red.calls, table: red.table, els: run.meta.els }));
          console.log(`arm ${arm} pass ${p}: ${run.frames.length} frames (${JSON.stringify(red.frames)}), ${r.ms} ms wall (not phone time); probe ${JSON.stringify(run.meta.probe)}; viewport ${run.meta.innerWidth}x${run.meta.innerHeight} dpr ${run.meta.dpr}`);
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

main().catch((e) => { console.error(String(e?.stack || e)); process.exit(1); });
