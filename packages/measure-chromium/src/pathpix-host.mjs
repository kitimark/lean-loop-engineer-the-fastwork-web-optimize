import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { BOX_EXPR, FREEZE_EXPR, IMAGES_READY_EXPR } from '../../measure-webkit/src/pathpix-page.mjs';
import { PIN_ACCENT_EXPR, EXIT_BOX_EXPR, EXIT_GEOM_EXPR, EXIT_LIVE_EXPR, EXIT_NUDGE_EXPR } from '../../measure-webkit/src/pathpix-exit-page.mjs';
import { analyzeDir } from '../../measure-webkit/src/pathpix-exit.mjs';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const IMAGE = 'fw-measure-chromium:1';
const { values: v } = parseArgs({
  args: process.argv.slice(2).filter((a) => a !== '--'),
  options: { site: { type: 'string' }, out: { type: 'string' }, layers: { type: 'string' }, offsets: { type: 'string' }, run: { type: 'string' }, strips: { type: 'string', default: 'changed' }, mode: { type: 'string', default: 'layers' }, flag: { type: 'string' }, rebuild: { type: 'boolean', default: false }, 'analyze-only': { type: 'boolean', default: false } },
});
if (!v.out) { console.error('usage: pathpix-host.mjs --site <dist/aot> --out <dir> [--layers a,b] [--offsets 0,4,8] [--run ID] [--strips all|changed|none] [--mode exit --flag <id:variant>] [--rebuild] | --analyze-only --out <dir>'); process.exit(2); }
const out = resolve(v.out);

if (!v['analyze-only']) {
  if (!v.site) { console.error('--site is required'); process.exit(2); }
  const site = resolve(v.site);
  if (!existsSync(join(site, 'index.html'))) { console.error(`no prerendered site at ${site} (pnpm --filter @fw/site build)`); process.exit(2); }
  const have = spawnSync('docker', ['image', 'inspect', IMAGE], { stdio: 'ignore' }).status === 0;
  if (!have || v.rebuild) {
    console.error(`building ${IMAGE} ...`);
    const b = spawnSync('docker', ['build', '-t', IMAGE, PKG], { stdio: 'inherit' });
    if (b.status !== 0) process.exit(b.status ?? 1);
  }
  rmSync(out, { recursive: true, force: true });
  mkdirSync(join(out, 'shots'), { recursive: true });
  const exprDir = mkdtempSync(join(tmpdir(), 'fw-pathpix-exprs-'));
  writeFileSync(join(exprDir, 'page.json'), JSON.stringify({ boxes: BOX_EXPR, freeze: FREEZE_EXPR, imagesReady: IMAGES_READY_EXPR, exitBoxes: EXIT_BOX_EXPR, exitGeom: EXIT_GEOM_EXPR, exitLive: EXIT_LIVE_EXPR, exitNudge: EXIT_NUDGE_EXPR, pinAccent: PIN_ACCENT_EXPR }));
  const run = v.run ?? process.env.GITHUB_RUN_ID ?? 'local';
  const inner = ['/driver/pathpix.mjs', `--run=${run}`, `--mode=${v.mode}`, ...(v.flag ? [`--flag=${v.flag}`] : []), ...(v.layers ? [`--layers=${v.layers}`] : []), ...(v.offsets ? [`--offsets=${v.offsets}`] : [])];
  let r;
  for (let attempt = 1; attempt <= 3; attempt++) {
    r = spawnSync('docker', [
      'run', '--rm', '--init', '--shm-size=1g',
      '-v', `${join(PKG, 'src')}:/driver:ro`, '-v', `${join(PKG, 'profiles')}:/profiles:ro`, '-v', `${site}:/site:ro`, '-v', `${exprDir}:/exprs:ro`, '-v', `${out}:/out`,
      '--entrypoint', 'node', IMAGE, ...inner,
    ], { stdio: ['ignore', 'inherit', 'inherit'] });
    if (r.status === 0) { rmSync(join(out, 'error.json'), { force: true }); break; }
    console.error(`attempt ${attempt} failed (status ${r.status}); ${attempt < 3 ? 'running again' : 'giving up'}`);
  }
  rmSync(exprDir, { recursive: true, force: true });
  if (r.status !== 0) process.exit(r.status ?? 1);
}
mkdirSync(join(out, 'strips'), { recursive: true });
const { res, md } = analyzeDir(out, { strips: v.strips, emit: (name, png) => writeFileSync(join(out, name), png) });
writeFileSync(join(out, 'cells.json'), JSON.stringify(res) + '\n');
writeFileSync(join(out, 'summary.md'), md + '\n');
console.log(md);
