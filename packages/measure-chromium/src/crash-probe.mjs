import { spawnSync } from 'node:child_process';
import { appendFileSync, existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { arch, cpus, platform, release, tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseKind, readOk, runnable } from './profile.mjs';

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const s = a.replace(/^--/, ''); const i = s.indexOf('='); return i < 0 ? [s, true] : [s.slice(0, i), s.slice(i + 1)]; }));
const name = args.profile;
const DRIVER = args.driver ?? '/driver';
const OUT = args.out ?? '/out';
const WORK = args.tmp ?? join(tmpdir(), 'probe');
const dirs = { profiles: args.profiles ?? '/profiles', probes: args.probes ?? '/probes' };
const inProfiles = existsSync(join(dirs.profiles, `${name}.json`));
const inProbes = existsSync(join(dirs.probes, `${name}.json`));
if (!inProfiles && !inProbes) { console.error(`profile ${name}: not in ${dirs.profiles} or ${dirs.probes}`); process.exit(2); }
const base = JSON.parse(readFileSync(join(inProbes ? dirs.probes : dirs.profiles, `${name}.json`), 'utf8'));
const kind = parseKind(base.kind);
if (kind === null || !readOk(inProfiles, inProbes, kind) || !runnable(kind, 'load')) {
  console.error(`profile ${name}: refused, a probe is read from probes/ only (in profiles: ${inProfiles}, in probes: ${inProbes}, kind ${base.kind})`);
  process.exit(2);
}
const variants = base.probe?.variants ?? [];
if (variants.length === 0) { console.error(`profile ${name}: no probe.variants`); process.exit(2); }
const PER_VARIANT_MS = +(base.probe.timeoutMs ?? 150000);
mkdirSync(WORK, { recursive: true });
mkdirSync(OUT, { recursive: true });

const rows = [];
for (const v of variants) {
  const p = JSON.parse(JSON.stringify(base));
  delete p.probe;
  p.id = `${name}.${v.id}`;
  if (v.width) p.viewport.width = v.width;
  if (v.height) p.viewport.height = v.height;
  if (v.dpr) p.viewport.dpr = v.dpr;
  if (v.css) p.css = v.css;
  if (v.dropFlags) p.dropFlags = v.dropFlags;
  const file = join(WORK, `${v.id}.json`);
  writeFileSync(file, JSON.stringify(p));
  const t0 = Date.now();
  const r = spawnSync(process.execPath, [join(DRIVER, 'run.mjs'), `--profile-file=${file}`, `--out=${join(WORK, `${v.id}-out`)}`, `--target=${args.target ?? 'original'}`, ...(args.root ? [`--root=${args.root}`] : []), ...(args.search ? [`--search=${args.search}`] : [])], {
    encoding: 'utf8', timeout: PER_VARIANT_MS, maxBuffer: 1 << 26,
    env: { ...process.env, FW_LOAD_ONLY: '1', FW_PROFILE_DIR: join(WORK, `${v.id}-chrome`), FW_NO_N0: process.env.FW_NO_N0 ?? '', FW_SKIP: (v.skip ?? []).join(','), ...(v.env ?? {}) },
  });
  const err = r.stderr ?? '';
  const status = r.status === 0 && /FW_LOAD_OK/.test(err) ? 'ok' : r.status === 76 ? 'crash' : r.status === 75 ? 'hang' : r.signal ? `timeout(${r.signal})` : `other(${r.status})`;
  const sig = /Received signal (\d+) (\w+) ([0-9a-f]+)/.exec(err);
  const frames = [...err.matchAll(/#\d+ 0x[0-9a-f]+ \([^)]*\+0x([0-9a-f]+)\)/g)].map((m) => m[1]);
  const launch = /FW_STOCK (\S+) (.+?) (headed|headless) (\S+) url/.exec(err);
  let facts = null;
  try { const m = /FW_STOCK_RESULT (\{.*\})/.exec(err); facts = m ? JSON.parse(m[1]) : null; } catch {}
  const row = {
    id: v.id, status, wallMs: Date.now() - t0, signal: sig ? `${sig[1]} ${sig[2]} ${sig[3]}` : null, frameCount: frames.length, frames: frames.slice(0, 12),
    browser: launch ? launch[2] : null, mode: launch ? launch[3] : null, host: launch ? launch[4] : null,
    innerWidth: facts?.innerWidth ?? null, fonts: facts?.fonts ?? null, platformFonts: facts?.platformFonts ?? null, titleHeight: facts?.titleHeight ?? null,
    crash: /FW_RENDERER_CRASH: ([^\n]*)/.exec(err)?.[1] ?? null,
    tail: status === 'ok' ? null : err.split('\n').filter((l) => l && !/^\s*#\d+ 0x/.test(l)).slice(-6).join(' | ').slice(0, 1600),
  };
  rows.push(row);
  console.error(`PROBE ${v.id.padEnd(28)} ${status.padEnd(8)} ${String(row.wallMs).padStart(6)} ms ${row.signal ?? ''} frames=${frames.length} innerWidth=${row.innerWidth ?? '-'}`);
  if (status === 'crash' && v === variants[0]) writeFileSync(join(OUT, 'first-crash.txt'), err.slice(-16000));
}
const machine = {
  leg: args.leg ?? null, platform: platform(), arch: arch(), release: release(), cpu: cpus()[0]?.model ?? null, headed: !!process.env.FW_STOCK_HEADED, fontconfig: process.env.FONTCONFIG_FILE ? 'empty (container fonts.conf)' : 'system',
  image: process.env.ImageOS ? `${process.env.ImageOS} ${process.env.ImageVersion ?? ''}`.trim() : null,
};
writeFileSync(join(OUT, 'counts.json'), JSON.stringify({ schema: 'fw.crash-probe/1', profile: name, target: args.target ?? 'original', search: args.search ?? '', machine, note: 'diagnostic rows, not counts', rows }, null, 1) + '\n');
if (typeof args.summary === 'string') {
  const head = `### ${machine.leg ?? 'probe'}: ${machine.platform} ${machine.arch} ${machine.headed ? 'headed' : 'headless'}, ${machine.image ?? machine.release}\n\n| variant | status | browser | innerWidth | title h | signal |\n|---|---|---|---|---|---|\n`;
  appendFileSync(args.summary, head + rows.map((r) => `| ${r.id} | ${r.status} | ${r.browser ?? ''} | ${r.innerWidth ?? ''} | ${r.titleHeight ?? ''} | ${r.signal ?? ''} |`).join('\n') + '\n\n');
}
console.error('PROBE-SUMMARY ' + rows.map((r) => `${r.id}=${r.status}`).join(' '));
process.exit(0);
