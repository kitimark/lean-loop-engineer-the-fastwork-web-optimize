import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { loadavg, cpus } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { zoneSums } from './fwcore.mjs';
import { parseKind, readOk } from './profile.mjs';
import { fileURLToPath } from 'node:url';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const IMAGE = 'fw-measure-chromium:1';
const argv = process.argv.slice(2).filter((a) => a !== '--');
const opt = (name, dflt) => { const i = argv.indexOf(`--${name}`); return i >= 0 ? argv[i + 1] : dflt; };
const flag = (name) => argv.includes(`--${name}`);
const profile = opt('profile', 'swipe-v1');
const label = opt('label', 'latest');

function sh(cmd, args, o = {}) { return execFileSync(cmd, args, { encoding: 'utf8', ...o }).trim(); }

function findSnapshot() {
  if (process.env.FW_SNAPSHOT_DIR) return resolve(process.env.FW_SNAPSHOT_DIR);
  const common = resolve(PKG, sh('git', ['-C', PKG, 'rev-parse', '--git-common-dir']));
  return join(dirname(common), 'snapshot', 'site');
}
const target = opt('target', 'original');
const search = opt('search', '');
const repoRoot = sh('git', ['-C', PKG, 'rev-parse', '--show-toplevel']);
const rewriteDir = resolve(opt('site-dir', join(repoRoot, 'apps', 'site', 'dist', 'aot')));
if (!['original', 'rewrite', 'fixture'].includes(target)) { console.error('--target must be original, rewrite or fixture'); process.exit(2); }
const snapshot = target === 'original' ? findSnapshot() : rewriteDir;
if (!existsSync(join(snapshot, 'index.html'))) { console.error(`${target} not found at ${snapshot} (original: set FW_SNAPSHOT_DIR; rewrite: pnpm --filter @fw/site build, or --site-dir)`); process.exit(2); }
let snapshotId = null;
try { snapshotId = JSON.parse(readFileSync(join(repoRoot, 'snapshot.lock.json'), 'utf8')).snapshot; } catch {}

const have = spawnSync('docker', ['image', 'inspect', IMAGE], { stdio: 'ignore' }).status === 0;
if (!have || flag('rebuild')) {
  console.error(`building ${IMAGE} ...`);
  const b = spawnSync('docker', ['build', '-t', IMAGE, PKG], { stdio: 'inherit' });
  if (b.status !== 0) process.exit(b.status ?? 1);
}
const imageId = sh('docker', ['image', 'inspect', '--format', '{{.Id}}', IMAGE]);

const out = join(PKG, 'out', profile, label);
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
const inProfiles = existsSync(join(PKG, 'profiles', `${profile}.json`));
const inProbes = existsSync(join(PKG, 'probes', `${profile}.json`));
if (!inProfiles && !inProbes) { console.error(`profile ${profile} is in neither profiles/ nor probes/`); process.exit(2); }
const declared = parseKind(JSON.parse(readFileSync(join(PKG, inProbes ? 'probes' : 'profiles', `${profile}.json`), 'utf8')).kind);
if (declared === null || !readOk(inProfiles, inProbes, declared)) { console.error(`profile ${profile}: refused, a counts profile sits in profiles/ and a probe in probes/, each name in one of them`); process.exit(2); }
const isProbe = declared === 'probe';
const inner = [isProbe ? '/driver/crash-probe.mjs' : '/driver/run.mjs', `--profile=${profile}`, `--target=${target}`, ...(search ? [`--search=${search}`] : []), ...(flag('dump-trace') ? ['--dump-trace'] : [])];
const t0 = Date.now();
const loadStamp = () => { let idle = null; try { const m = /([\d.]+)% idle/.exec(sh('top', ['-l', '1', '-n', '0'])); idle = m ? +m[1] : null; } catch {} return { at: new Date().toISOString(), load1: +loadavg()[0].toFixed(2), cpuIdlePct: idle, cores: cpus().length }; };
const loadBefore = loadStamp();
const MAX_ATTEMPTS = 5;
let r, attempts = 0;
while (attempts < MAX_ATTEMPTS) {
  attempts++;
  r = spawnSync('docker', [
  'run', '--rm', '--init', '--shm-size=1g', ...(process.env.FW_DOCKER_CPUS ? ['--cpus', process.env.FW_DOCKER_CPUS] : []),
  ...Object.entries(process.env).filter(([k]) => /^FW_(DROP_FLAGS|NO_LAYERS|BARRIER_MIN_MS|CHROME_EXTRA|EXTRA_CATEGORIES|PROBE|LOAD_TRACE|BF_TIMEOUT_MS|BARRIER_MS|NOTOUCH|DEBUG|TOUCH_ACK_MS|TOUCH_SETTLE_MS)$/.test(k)).flatMap(([k, v]) => ['-e', `${k}=${v}`]), '-e', `FW_IMAGE_ID=${imageId}`, '-e', `FW_SNAPSHOT_ID=${target === 'original' ? snapshotId ?? '' : ''}`, ...(flag('debug') ? ['-e', 'FW_DEBUG=1'] : []),
  '-v', `${join(PKG, 'src')}:/driver:ro`, '-v', `${join(PKG, '../contracts/src')}:/contracts/src:ro`, '-v', `${join(PKG, 'profiles')}:/profiles:ro`, '-v', `${join(PKG, 'probes')}:/probes:ro`,
  '-v', `${snapshot}:/snapshot/site:ro`, '-v', `${out}:/out`,
  '--entrypoint', 'node', IMAGE, ...inner,
], { stdio: ['ignore', 'inherit', 'inherit'] });
  if (r.status !== 75) break;
  console.error(`attempt ${attempts} hit a BeginFrame hang; running again`);
}
const loadAfter = loadStamp();
writeFileSync(join(out, 'host.json'), JSON.stringify({ note: 'host-side wall facts for this run, not part of the result', attempts, loadBefore, loadAfter, hostWallS: +((Date.now() - t0) / 1000).toFixed(1) }, null, 1) + '\n');
console.error(`attempts=${attempts} (not part of the result)`);
console.error(`wrote ${join(out, 'counts.json')} (host wall ${((Date.now() - t0) / 1000).toFixed(1)} s)`);
if (r.status !== 0) process.exit(r.status ?? 1);
if (isProbe) { writeFileSync(join(out, 'zones.json'), JSON.stringify({ schema: 'fw.zones/1', counts: 'counts.json', zoneHeightPx: 0, zones: [], note: 'crash probe: no counts' }) + '\n'); process.exit(0); }
if (flag('no-zones')) process.exit(0);
try {
  const counts = JSON.parse(readFileSync(join(out, 'counts.json'), 'utf8'));
  const zoneHeightPx = JSON.parse(readFileSync(join(PKG, 'profiles', `${profile}.json`), 'utf8')).zoneHeightPx;
  const zones = zoneSums(counts.frames, zoneHeightPx);
  writeFileSync(join(out, 'zones.json'), JSON.stringify({ schema: 'fw.zones/1', counts: 'counts.json', zoneHeightPx, zones }, null, 1) + '\n');
  console.error(`wrote ${join(out, 'zones.json')} (${zones.length} zones, from fwcore)`);
} catch (e) {
  console.error(`zones.json not written: ${e.message}`);
  process.exit(3);
}
process.exit(0);
