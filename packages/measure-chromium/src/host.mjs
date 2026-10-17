// Host-side launcher: builds the image if needed, then runs the in-container driver against the read-only snapshot.
//   node src/host.mjs --profile swipe-v1 [--label NAME] [--rebuild] [--debug] [--dump-trace]
// Output: out/<profile>/<label>/counts.json (gitignored). Needs Docker (Docker Desktop is fine) and the local snapshot.
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { writeFileSync } from 'node:fs';
import { zoneSums } from './fwcore.mjs';
import { fileURLToPath } from 'node:url';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const IMAGE = 'fw-measure-chromium:1';
const argv = process.argv.slice(2).filter((a) => a !== '--');
const opt = (name, dflt) => { const i = argv.indexOf(`--${name}`); return i >= 0 ? argv[i + 1] : dflt; };
const flag = (name) => argv.includes(`--${name}`);
const profile = opt('profile', 'swipe-v1');
const label = opt('label', 'latest');

function sh(cmd, args, o = {}) { return execFileSync(cmd, args, { encoding: 'utf8', ...o }).trim(); }

// The snapshot lives in the main checkout (gitignored); a worktree finds it through the common git dir.
function findSnapshot() {
  if (process.env.FW_SNAPSHOT_DIR) return resolve(process.env.FW_SNAPSHOT_DIR);
  const common = resolve(PKG, sh('git', ['-C', PKG, 'rev-parse', '--git-common-dir']));
  return join(dirname(common), 'snapshot', 'site');
}
const snapshot = findSnapshot();
if (!existsSync(join(snapshot, 'index.html'))) { console.error(`snapshot not found at ${snapshot} (set FW_SNAPSHOT_DIR)`); process.exit(2); }
const repoRoot = sh('git', ['-C', PKG, 'rev-parse', '--show-toplevel']);
let snapshotId = null;
try { snapshotId = JSON.parse(readFileSync(join(repoRoot, 'snapshot.lock.json'), 'utf8')).snapshot; } catch { /* lock file absent */ }

const have = spawnSync('docker', ['image', 'inspect', IMAGE], { stdio: 'ignore' }).status === 0;
if (!have || flag('rebuild')) {
  console.error(`building ${IMAGE} ...`);
  const r = spawnSync('docker', ['build', '-t', IMAGE, PKG], { stdio: 'inherit' });
  if (r.status !== 0) process.exit(r.status ?? 1);
}
const imageId = sh('docker', ['image', 'inspect', '--format', '{{.Id}}', IMAGE]);

const out = join(PKG, 'out', profile, label);
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
const inner = ['/driver/run.mjs', `--profile=${profile}`, ...(flag('dump-trace') ? ['--dump-trace'] : [])];
const t0 = Date.now();
const r = spawnSync('docker', [
  'run', '--rm', '--init', '--shm-size=1g',
  ...Object.entries(process.env).filter(([k]) => /^FW_(BARRIER_MS|NOTOUCH|DEBUG)$/.test(k)).flatMap(([k, v]) => ['-e', `${k}=${v}`]), '-e', `FW_IMAGE_ID=${imageId}`, '-e', `FW_SNAPSHOT_ID=${snapshotId ?? ''}`, ...(flag('debug') ? ['-e', 'FW_DEBUG=1'] : []),
  '-v', `${join(PKG, 'src')}:/driver:ro`, '-v', `${join(PKG, 'profiles')}:/profiles:ro`,
  '-v', `${snapshot}:/snapshot/site:ro`, '-v', `${out}:/out`,
  '--entrypoint', 'node', IMAGE, ...inner,
], { stdio: ['ignore', 'inherit', 'inherit'] });
console.error(`wrote ${join(out, 'counts.json')} (host wall ${((Date.now() - t0) / 1000).toFixed(1)} s)`);
if (r.status !== 0) process.exit(r.status ?? 1);
// Per-zone sums come from fwcore (Lean Fw.Measure.zoneSums), never from TS. Without a built fwcore the raw counts stay
// valid and only zones.json is missing.
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
