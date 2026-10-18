// Runs the fixture cells in the layout Lean decided (Fw.Measure.WktrLayout.layout, golden/measure/wktr.fixtures.jsonl).
//   node lanes.mjs run --root <archive root> --out <dir> [--passes 3] [--mode auto|probe] [--req 1,2,3]
//   node lanes.mjs cleanup          delete every Simulator device this script made (fw-wktr, fw-wktr-1, ...)
// A layout is a list of phases (one per variant, run one after the other); a phase has `width` lanes, each its own Simulator
// device (fw-wktr for lane 0, fw-wktr-<i>) and its own driver process (src/cli.mjs), run side by side; a lane runs its cells one
// after the other. Results go to <out>/<tag>/<fixture>-f<frames>/counts-<variant>-<pass>.json: tag `auto` for the production
// layout (mode auto, request 3) and `k<w>` for the premise test (mode probe, one layout per request w). Nothing here decides
// the layout: it only reads it. Wall times are CI VM time, not phone time.
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import * as sim from '../src/sim.mjs';
import { recorder } from '../src/spans.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, '..', 'src', 'cli.mjs');
const GOLDEN = join(HERE, '..', '..', 'contracts', 'golden', 'measure', 'wktr.fixtures.jsonl');
const DEVICE = 'fw-wktr';
export const deviceOf = (lane) => (lane === 0 ? DEVICE : `${DEVICE}-${lane}`);

/** The layout line of the golden for `mode` and request `req` (an error when the golden has none). */
export function layoutOf(lines, mode, req) {
  const l = lines.find((x) => x.kind === 'layout' && x.mode === mode && x.req === req);
  if (!l) throw new Error(`no layout line for mode ${mode}, request ${req}`);
  return l;
}

export const readGolden = (path = GOLDEN) => readFileSync(path, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));

/** The cli.mjs argument list of one cell on one lane. */
export function cellArgs({ root, out, passes, cell, lane }) {
  return [CLI, 'run', '--keep', '--root', root, '--site', join(HERE, cell.fixture), '--out', join(out, `${cell.fixture}-f${cell.frames}`),
    '--passes', String(passes), '--step', '100', '--frames', String(cell.frames), '--settle', '2000', '--variants', cell.variant,
    '--label', cell.fixture, '--device-name', deviceOf(lane)];
}

const children = new Set(); // driver processes this script started (and only those) so a failure can stop them
const runNode = (args, prefix) => new Promise((ok, bad) => {
  const p = spawn(process.execPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  children.add(p);
  const pipe = (s, to) => { let buf = ''; s.on('data', (d) => { buf += d; const ls = buf.split('\n'); buf = ls.pop(); for (const l of ls) to.write(`${prefix} ${l}\n`); }); s.on('end', () => { if (buf) to.write(`${prefix} ${buf}\n`); }); };
  pipe(p.stdout, process.stdout); pipe(p.stderr, process.stderr);
  p.on('close', (code) => (children.delete(p), code === 0 ? ok() : bad(new Error(`${prefix} exited ${code}`))));
});

/** Run one layout; returns its span record. */
export async function runLayout({ layout, root, out, passes }) {
  const rec = recorder();
  const phases = [];
  for (const ph of layout.phases) {
    // lane devices above this phase's width stay shut so an idle device never shares the VM with a phase that does not use it
    for (const d of sim.listDevices().filter((x) => /^fw-wktr(-\d+)?$/.test(x.name) && x.state === 'Booted')) {
      const lane = d.name === DEVICE ? 0 : Number(d.name.slice(DEVICE.length + 1));
      if (lane >= ph.width) sim.shutdown(d.udid);
    }
    rec.mark('_gap');
    const laneMs = await Promise.all(ph.lanes.map(async (cells, lane) => {
      const t0 = Date.now();
      for (const cell of cells) await runNode(cellArgs({ root, out, passes, cell, lane }), `[${ph.variant} lane ${lane}/${ph.width} ${cell.fixture}-f${cell.frames}]`);
      return Date.now() - t0;
    }));
    rec.mark(`phase_${ph.variant}`);
    phases.push({ variant: ph.variant, width: ph.width, cells: ph.lanes.map((l) => l.length), laneMs });
  }
  return { schema: 'fw.wktr.spans.layout/1', totalMs: rec.sinceStart(), phases, spans: rec.spans() };
}

export function cleanup() {
  for (const d of sim.listDevices().filter((x) => /^fw-wktr(-\d+)?$/.test(x.name))) { sim.shutdown(d.udid); sim.deleteDevice(d.udid); }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { values: v, positionals } = parseArgs({
    allowPositionals: true,
    options: { root: { type: 'string' }, out: { type: 'string' }, passes: { type: 'string', default: '3' }, mode: { type: 'string', default: 'auto' }, req: { type: 'string', default: '1' }, golden: { type: 'string' } },
  });
  if (positionals[0] === 'cleanup') { cleanup(); process.exit(0); }
  if (positionals[0] !== 'run' || !v.root || !v.out) { console.error('usage: lanes.mjs run --root <dir> --out <dir> [--passes N] [--mode auto|probe] [--req 1,2,3] | cleanup'); process.exit(2); }
  const lines = readGolden(v.golden);
  const reqs = v.mode === 'auto' ? [3] : v.req.split(',').map(Number);
  try {
    for (const req of reqs) {
      const tag = v.mode === 'auto' ? 'auto' : `k${req}`;
      const layout = layoutOf(lines, v.mode, req);
      const out = resolve(v.out, tag);
      mkdirSync(out, { recursive: true });
      console.log(`layout ${tag}: ${layout.phases.map((p) => `${p.variant} width ${p.width} (${p.lanes.map((l) => l.length).join('+')} cells)`).join(', ')}`);
      const r = await runLayout({ layout, root: resolve(v.root), out, passes: Number(v.passes) });
      writeFileSync(join(out, 'spans-layout.json'), JSON.stringify({ tag, mode: v.mode, req, ...r }));
      console.log(`layout ${tag}: ${r.totalMs} ms ${JSON.stringify(r.spans)}`);
      cleanup(); // the next layout starts from no devices: the premise test must not inherit booted ones
    }
  } catch (e) { console.error(String(e?.stack || e)); for (const c of children) c.kill('SIGTERM'); cleanup(); process.exit(1); }
}
