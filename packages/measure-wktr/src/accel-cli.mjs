import { parseArgs } from 'node:util';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serveBuilt } from './repaint-serve.mjs';
import { accelHarnessSource, parseAccel } from './accel-page.mjs';
import { runOnce, DEFAULT_HEADER } from './wktr.mjs';
import * as sim from './sim.mjs';
import { frameSummary, midSummary } from './midflip.mjs';
import { SWEEP_ARMS, sweepTally } from './sweep-pause.mjs';
import { RS_ARMS, recalcTally } from './recalc-source.mjs';
import { BS_ARMS, bisectTally } from './recalc-bisect.mjs';
import { glintLines } from './glint-hold.mjs';
import { glintCompositorLines } from './glint-compositor.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ARCHIVE = JSON.parse(readFileSync(join(HERE, 'archive.json'), 'utf8'));
export const MODES = {
  scrubbed: 'morph.geom:on',
  timed: 'morph.geom:on,morph.tween:geom-timed',
  mid: 'morph.geom:on,morph.tween:geom-timed',
  'mid-thr-off': 'morph.geom:on,morph.tween:geom-timed',
  'sweep-thr-off': 'morph.geom:on,morph.tween:geom-timed',
  'recalc-thr-off': 'morph.geom:on,morph.tween:geom-timed',
  'bisect-thr-off': 'morph.geom:on,morph.tween:geom-timed',
  'glint-base-thr-off': 'morph.geom:on,morph.tween:geom-timed',
  'glint-hold-thr-off': 'morph.geom:on,morph.tween:geom-timed,platform.glint:hold-freeze',
  'glint-comp-thr-off': 'morph.geom:on,morph.tween:geom-timed,platform.glint:compositor',
};
export const MID_AT = [0.3, 0.5, 0.8];
export const MID_ARMS = ['all', 'idle', 'no-translate', 'no-transform', 'none', 'all-again'];
export const THREADED_OFF = 'ThreadedTimeBasedAnimationsEnabled=false';
export const isMid = (mode) => mode === 'mid' || mode === 'mid-thr-off';
export const isSweep = (mode) => mode === 'sweep-thr-off';
export const isRecalc = (mode) => mode === 'recalc-thr-off';
export const isBisect = (mode) => mode === 'bisect-thr-off';
export const isGlint = (mode) => mode === 'glint-base-thr-off' || mode === 'glint-hold-thr-off' || mode === 'glint-comp-thr-off';
export const GLINT_BASE_ARMS = ['rs-idle', 'rs-idle-smil', 'rs-idle', 'rs-flip', 'rs-flip-smil', 'rs-flip'];
export const GLINT_HOLD_ARMS = ['rs-idle', 'rs-flip'];
export const GLINT_OPTS = { rsIdleMs: 5000, rsReps: 16, gh: true };
export const headerOf = (mode, base) => (mode === 'mid-thr-off' || isSweep(mode) || isRecalc(mode) || isBisect(mode) || isGlint(mode) ? `${base} ${THREADED_OFF}` : base);

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
  const glintReports = new Map();
  try {
    for (const mode of modes) {
      const search = `?fw=${MODES[mode]}`;
      const srv = await serveBuilt(dist, search, accelHarnessSource({ mode: isMid(mode) || isSweep(mode) || isRecalc(mode) || isBisect(mode) || isGlint(mode) ? 'timed' : mode, arms: arms ?? (isMid(mode) ? MID_ARMS : isSweep(mode) ? SWEEP_ARMS : isRecalc(mode) ? RS_ARMS : isBisect(mode) ? BS_ARMS : isGlint(mode) ? (mode === 'glint-base-thr-off' ? GLINT_BASE_ARMS : GLINT_HOLD_ARMS) : undefined), mid: isMid(mode) ? MID_AT : undefined, ...(isGlint(mode) ? GLINT_OPTS : {}) }));
      console.log(`mode ${mode}: serving ${srv.url}${search}`);
      try {
        for (let p = 1; p <= passes; p++) {
          let r, attempts = 0;
          for (;;) {
            attempts++;
            try { r = await runOnce({ udid: dev.udid, root, bundleId: ARCHIVE.bundleId, url: `${srv.url}${search}`, header: headerOf(mode, v.header), timeoutMs: isBisect(mode) || isGlint(mode) ? Math.max(Number(v.timeout), 840000) : Number(v.timeout) }); break; }
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
            device: { name: v['device-type'], runtime: dev.runtime.version, runtimeBuild: dev.runtime.buildversion }, header: headerOf(mode, v.header),
          };
          writeFileSync(join(out, `accel-${mode}-${p}.json`), JSON.stringify({ schema: 'fw.track-accel.wktr/1', meta, ...got.report }));
          if (isMid(mode)) {
            try {
              for (const m of midSummary(got.report).filter((x) => x.arm === 'all')) console.log(`${mode} pass ${p} all ${m.bin} ph ${m.ph}: ${Object.entries(m.groups).map(([k, g]) => `${k} n${g.n} acc${g.accel} tick${g.oracleTicks}/${g.leanTicks}`).join(' ')}`);
              for (const f of frameSummary(got.report)) console.log(`${mode} pass ${p} ${f.arm}: frames ${f.frames} recalc/frame ${f.recalcPerFrame} rcMax ${f.rcMax}`);
            } catch (e) { console.log(`${mode} pass ${p}: summary failed ${String(e.message).slice(0, 120)}`); }
          }
          if (isSweep(mode)) {
            try { for (const l of sweepTally(got.report)) console.log(`${mode} pass ${p} ${l}`); } catch (e) { console.log(`${mode} pass ${p}: sweep summary failed ${String(e.message).slice(0, 120)}`); }
          }
          if (isRecalc(mode)) {
            try { for (const l of recalcTally(got.report)) console.log(`${mode} pass ${p} ${l}`); } catch (e) { console.log(`${mode} pass ${p}: recalc summary failed ${String(e.message).slice(0, 120)}`); }
          }
          if (isBisect(mode)) {
            try { for (const l of bisectTally(got.report)) console.log(`${mode} pass ${p} ${l}`); } catch (e) { console.log(`${mode} pass ${p}: bisect summary failed ${String(e.message).slice(0, 120)}`); }
          }
          if (isGlint(mode)) glintReports.set(`${mode}:${p}`, got.report);
          if (isGlint(mode) && glintReports.has(`glint-base-thr-off:${p}`) && glintReports.has(`glint-comp-thr-off:${p}`)) {
            try { for (const l of glintCompositorLines(`${v.label} pass ${p}`, glintReports.get(`glint-base-thr-off:${p}`), glintReports.get(`glint-comp-thr-off:${p}`))) console.log(l); } catch (e) { console.log(`${mode} pass ${p}: glint compositor summary failed ${String(e.message).slice(0, 120)}`); }
          }
          if (isGlint(mode) && glintReports.has(`glint-base-thr-off:${p}`) && glintReports.has(`glint-hold-thr-off:${p}`)) {
            try { for (const l of glintLines(`${v.label} pass ${p}`, glintReports.get(`glint-base-thr-off:${p}`), glintReports.get(`glint-hold-thr-off:${p}`))) console.log(l); } catch (e) { console.log(`${mode} pass ${p}: glint summary failed ${String(e.message).slice(0, 120)}`); }
          }
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
