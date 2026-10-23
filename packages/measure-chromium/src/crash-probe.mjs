import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const s = a.replace(/^--/, ''); const i = s.indexOf('='); return i < 0 ? [s, true] : [s.slice(0, i), s.slice(i + 1)]; }));
const name = args.profile;
const base = JSON.parse(readFileSync(`/profiles/${name}.json`, 'utf8'));
const variants = base.probe?.variants ?? [];
if (variants.length === 0) { console.error(`profile ${name}: no probe.variants`); process.exit(2); }
const OUT = args.out ?? '/out';
const PER_VARIANT_MS = +(base.probe.timeoutMs ?? 150000);
mkdirSync('/tmp/probe', { recursive: true });
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
  const file = `/tmp/probe/${v.id}.json`;
  writeFileSync(file, JSON.stringify(p));
  const t0 = Date.now();
  const r = spawnSync('node', ['/driver/run.mjs', `--profile-file=${file}`, `--out=/tmp/probe/${v.id}-out`, `--target=${args.target ?? 'original'}`, ...(args.search ? [`--search=${args.search}`] : [])], {
    encoding: 'utf8', timeout: PER_VARIANT_MS, maxBuffer: 1 << 26,
    env: { ...process.env, FW_LOAD_ONLY: '1', FW_PROFILE_DIR: `/tmp/probe/${v.id}-chrome`, FW_NO_N0: process.env.FW_NO_N0 ?? '', FW_SKIP: (v.skip ?? []).join(','), ...(v.env ?? {}) },
  });
  const err = r.stderr ?? '';
  const status = r.status === 0 && /FW_LOAD_OK/.test(err) ? 'ok' : r.status === 76 ? 'crash' : r.status === 75 ? 'hang' : r.signal ? `timeout(${r.signal})` : `other(${r.status})`;
  const sig = /Received signal (\d+) (\w+) ([0-9a-f]+)/.exec(err);
  const frames = [...err.matchAll(/#\d+ 0x[0-9a-f]+ \([^)]*\+0x([0-9a-f]+)\)/g)].map((m) => m[1]);
  const row = { id: v.id, status, wallMs: Date.now() - t0, signal: sig ? `${sig[1]} ${sig[2]} ${sig[3]}` : null, frameCount: frames.length, frames: frames.slice(0, 12), tail: status === 'ok' ? null : err.split('\n').filter((l) => l && !/^\s*#\d+ 0x/.test(l)).slice(-4).join(' | ').slice(0, 300) };
  rows.push(row);
  console.error(`PROBE ${v.id.padEnd(28)} ${status.padEnd(8)} ${String(row.wallMs).padStart(6)} ms ${row.signal ?? ''} frames=${frames.length}`);
  if (status === 'crash' && v === variants[0]) writeFileSync(`${OUT}/first-crash.txt`, err.slice(-16000));
}
writeFileSync(`${OUT}/counts.json`, JSON.stringify({ schema: 'fw.crash-probe/1', profile: name, target: args.target ?? 'original', search: args.search ?? '', note: 'diagnostic rows, not counts', rows }, null, 1) + '\n');
console.error('PROBE-SUMMARY ' + rows.map((r) => `${r.id}=${r.status}`).join(' '));
process.exit(0);
