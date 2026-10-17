// Hands per-zone and per-frame counts of a base run and variant runs to fwcore (`screen`, `ticks`) and records the replies.
// No decision logic here: this builds the requests from counts.json and writes request + reply side by side.
//   node src/fwcore-screen.mjs --out out/fwcore/touch.json --base out/P/default/counts.json --var name=out/P/x/counts.json [--var ...]
//   [--fwcore /path/to/fwcore]   default: <main checkout>/lean/.lake/build/bin/fwcore
// Count vectors (fixed order, all Nat; types that can go negative or that are GC-bound are never used):
//   W (rendering work):  trace.UpdateLayoutTree.elementCount, trace.Layout.dirtyObjects, trace.Paint, trace.UpdateLayer, trace.RasterTask
//   S (script/dispatch): trace.FunctionCall, trace.EventDispatch, trace.FireAnimationFrame, trace.HitTest
// Runs: Z = per 500 px zone (frames aligned by construction: same zone ids), F = per frame (only when both runs have the
// same frame count and the same trajectory hash; otherwise omitted, and the reason is recorded).
import { spawn, execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const argv = process.argv.slice(2);
const all = (name) => argv.flatMap((a, i) => (a === `--${name}` ? [argv[i + 1]] : []));
const one = (name, d) => all(name)[0] ?? d;
const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const common = resolve(PKG, execFileSync('git', ['-C', PKG, 'rev-parse', '--git-common-dir'], { encoding: 'utf8' }).trim());
const fwcore = one('fwcore', join(dirname(common), 'lean', '.lake', 'build', 'bin', 'fwcore'));
const W = ['trace.UpdateLayoutTree.elementCount', 'trace.Layout.dirtyObjects', 'trace.Paint', 'trace.UpdateLayer', 'trace.RasterTask'];
const S = ['trace.FunctionCall', 'trace.EventDispatch', 'trace.FireAnimationFrame', 'trace.HitTest'];
const load = (f) => JSON.parse(readFileSync(f, 'utf8'));
const vec = (counts, keys) => keys.map((k) => counts[k] ?? 0);
const zoneRun = (r, keys) => r.zones.map((z) => vec(z.sums, keys));
const frameRun = (r, keys) => r.frames.map((f) => vec(f.counts, keys));

const base = load(one('base'));
const vars = all('var').map((s) => { const [name, f] = s.split('='); return { name, file: f, run: load(f) }; });
const reqs = [];
let id = 0;
const add = (what, req) => reqs.push({ what, req: { id: ++id, ...req } });
for (const v of vars) {
  for (const [vn, keys] of [['W', W], ['S', S]]) {
    add({ variant: v.name, vector: vn, runs: 'Z', keys, zones: base.zones.map((z) => z.id), sameZones: JSON.stringify(base.zones.map((z) => z.id)) === JSON.stringify(v.run.zones.map((z) => z.id)) },
      { op: 'screen', base: zoneRun(base, keys), var: zoneRun(v.run, keys) });
    const same = base.frames.length === v.run.frames.length && base.meta.trajectorySha256 === v.run.meta.trajectorySha256;
    if (same) add({ variant: v.name, vector: vn, runs: 'F', keys, frames: base.frames.length }, { op: 'screen', base: frameRun(base, keys), var: frameRun(v.run, keys) });
    else add({ variant: v.name, vector: vn, runs: 'F', skipped: `frame counts ${base.frames.length}/${v.run.frames.length} or trajectories differ` }, null);
  }
}
// ticks: the counts lane has no frame durations (virtual time), so the nominal 60 Hz frame time is handed over for every frame.
const dt = Math.round(1e9 / base.meta.hz);
add({ variant: 'base', note: 'nominal frame time for every frame, hz and count of frames only', frames: base.frames.length }, { op: 'ticks', hz: base.meta.hz, dtNs: base.frames.map(() => dt), thresholdsNs: [34000000, 50000000] });

const child = spawn(fwcore, [], { env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, stdio: ['pipe', 'pipe', 'inherit'] });
const sendable = reqs.filter((r) => r.req);
const replies = new Map();
let buf = '';
const done = new Promise((res) => {
  child.stdout.on('data', (d) => {
    buf += d;
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i); buf = buf.slice(i + 1);
      const j = JSON.parse(line); replies.set(j.id, j);
      if (replies.size === sendable.length) res();
    }
  });
});
for (const r of sendable) child.stdin.write(JSON.stringify(r.req) + '\n');
await done;
child.stdin.end();
const out = reqs.map((r) => ({ ...r.what, request: r.req ? { op: r.req.op, id: r.req.id, shape: r.req.base ? [r.req.base.length, r.req.base[0]?.length] : undefined } : null, reply: r.req ? replies.get(r.req.id) : null }));
const outFile = one('out', 'out/fwcore/replies.json');
mkdirSync(dirname(outFile), { recursive: true });
writeFileSync(outFile, JSON.stringify({ fwcore, base: one('base'), replies: out }, null, 1) + '\n');
for (const o of out) console.log(JSON.stringify({ variant: o.variant, vector: o.vector, runs: o.runs, skipped: o.skipped, reply: o.reply ? (o.reply.screen ?? (o.reply.error ? 'error: ' + o.reply.error : { ticksLen: o.reply.ticks?.length, ticksSum: o.reply.ticks?.reduce((a, b) => a + b, 0), above: o.reply.above })) : undefined }));
