import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const s = a.replace(/^--/, ''); const i = s.indexOf('='); return i < 0 ? [s, true] : [s.slice(0, i), s.slice(i + 1)]; }));
for (const k of ['site', 'rows', 'out', 'work']) if (!args[k]) { console.error(`--${k} is required`); process.exit(2); }
const IMAGE = args.image ?? 'fw-measure-chromium:1';
const REPS = +(args.reps ?? 2);
const site = resolve(args.site);
const rows = resolve(args.rows);
const out = resolve(args.out);
const work = resolve(args.work);
const LIB_DIR = '/usr/share/fonts/truetype/liberation';
const golden = readFileSync(join(PKG, '../contracts/golden/measure/profile.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
let sets = golden.find((l) => l.kind === 'fontSets').sets;
if (typeof args.sets === 'string') sets = sets.filter((s) => args.sets.split(',').includes(s.name));
mkdirSync(out, { recursive: true });
mkdirSync(work, { recursive: true });

const sh = (cmd, argv, opts = {}) => spawnSync(cmd, argv, { encoding: 'utf8', maxBuffer: 1 << 28, ...opts });
const confOf = (dirs) => `<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n<fontconfig>\n${dirs.map((d) => `  <dir>${d}</dir>\n`).join('')}  <cachedir>/tmp/fontconfig-cache</cachedir>\n</fontconfig>\n`;

const libHost = join(work, 'liberation');
if (!existsSync(libHost)) {
  mkdirSync(libHost, { recursive: true });
  const r = sh('docker', ['run', '--rm', '--user', 'root', '--entrypoint', 'sh', '-v', `${libHost}:/o`, IMAGE, '-c', `cp ${LIB_DIR}/*.ttf /o/`]);
  if (r.status !== 0) { console.error(`cannot copy liberation out of ${IMAGE}: ${r.stderr}`); process.exit(1); }
}

const FETCH = `set -eu
apt-get update -qq
mkdir -p /pk/debs/partial
apt-get install -y -qq --no-install-recommends --download-only -o Dir::Cache::archives=/pk/debs -o APT::Sandbox::User=root $PKGS
mkdir -p /pk/x
for d in /pk/debs/*.deb; do dpkg-deb -x "$d" /pk/x; printf '%s=%s\\n' "$(dpkg-deb -f "$d" Package)" "$(dpkg-deb -f "$d" Version)"; done > /pk/packages.txt
rm -rf /pk/debs`;

function fcCovered(name, conf, cps) {
  const f = join(work, `fc-${name}.conf`);
  writeFileSync(f, conf);
  const covered = [];
  for (const cp of cps) {
    const r = sh('fc-list', ['-f', '%{family}\\n', `:charset=${cp.toString(16)}`], { env: { ...process.env, FONTCONFIG_FILE: f } });
    if (r.status === 0 && r.stdout.trim() !== '') covered.push(cp);
  }
  return covered;
}

let failed = 0;
for (const set of sets) {
  const extras = set.pkgs.filter((p) => p !== 'fonts-liberation');
  const dir = join(work, set.name);
  mkdirSync(join(dir, 'x'), { recursive: true });
  let installed = '';
  if (extras.length > 0) {
    const r = sh('docker', ['run', '--rm', '--user', 'root', '--entrypoint', 'sh', '-e', `PKGS=${extras.join(' ')}`, '-v', `${dir}:/pk`, IMAGE, '-c', FETCH]);
    if (r.status !== 0) { console.error(`set ${set.name}: package fetch failed\n${(r.stderr || r.stdout).slice(-1500)}`); failed++; continue; }
    installed = readFileSync(join(dir, 'packages.txt'), 'utf8');
  }
  writeFileSync(join(out, `packages-${set.name}.txt`), installed);
  const fontsRoot = join(dir, 'x/usr/share/fonts');
  const withLib = set.pkgs.includes('fonts-liberation');
  const hasExtra = extras.length > 0 && existsSync(fontsRoot);
  const containerConf = confOf([...(withLib ? [LIB_DIR] : []), ...(hasExtra ? ['/extra/usr/share/fonts'] : [])]);
  const hostConf = confOf([...(withLib ? [libHost] : []), ...(hasExtra ? [fontsRoot] : [])]);
  const confFile = join(dir, 'fonts.conf');
  writeFileSync(confFile, containerConf);
  const nfonts = hasExtra ? sh('sh', ['-c', `find ${JSON.stringify(fontsRoot)} -type f | wc -l`]).stdout.trim() : '0';
  console.error(`set ${set.name}: packages ${set.pkgs.join(',') || '-'}; extra font files ${nfonts}`);
  for (let rep = 1; rep <= REPS; rep++) {
    const o = join(out, `rep${rep}`);
    mkdirSync(o, { recursive: true });
    const argv = ['run', '--rm', '--init', '--shm-size=1g', '-v', `${join(PKG, 'src')}:/driver:ro`, '-v', `${site}:/snapshot/site:ro`, '-v', `${dirname(rows)}:/exprs:ro`, '-v', `${confFile}:/etc/fonts/fw-lane-fonts.conf:ro`,
      ...(hasExtra ? ['-v', `${join(dir, 'x')}:/extra:ro`] : []), '-v', `${o}:/out`, '--entrypoint', 'node', IMAGE, '/driver/fidelity.mjs', `--variant=${set.name}`, `--rows=/exprs/${rows.split('/').pop()}`];
    const r = sh('docker', argv, { stdio: ['ignore', 'inherit', 'inherit'], encoding: undefined });
    const file = join(o, `fidelity-${set.name}.json`);
    if (r.status !== 0 || !existsSync(file)) { console.error(`set ${set.name} rep ${rep}: run failed (status ${r.status})`); failed++; continue; }
    const j = JSON.parse(readFileSync(file, 'utf8'));
    j.set = set;
    j.installed = installed.split('\n').filter(Boolean);
    for (const v of Object.values(j.views)) v.systemCovered = fcCovered(set.name, hostConf, (v.uncovered ?? []).map(([cp]) => cp));
    writeFileSync(join(out, `fidelity-${set.name}-r${rep}.json`), `${JSON.stringify(j)}\n`);
  }
}
console.error(`fidelity-host: ${sets.length} sets, ${failed} failures`);
process.exit(failed > 0 ? 1 : 0);
